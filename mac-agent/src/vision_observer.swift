import Foundation
import CoreGraphics
import Vision
import AppKit
import ApplicationServices
import ScreenCaptureKit

// MARK: - Agent Types

enum AgentType: String {
    case claudeCode  = "Claude Code"
    case codexApp    = "OpenAI Codex"
    case antigravity = "Antigravity IDE"
    case aider       = "Aider"
    case unknown     = "AI Agent"
}

enum PromptInteractionType: String, Codable {
    case clickable    = "CLICK_TYPE"
    case numberedMenu = "NUM_TYPE"
    case yOrN         = "YN_TYPE"
    case yNAlways     = "YNA_TYPE"
}

// MARK: - Data Models

struct VisionOptionItem: Codable {
    let key: String
    let label: String
    let isPrimary: Bool
    let isDestructive: Bool
}

struct VisionPromptPayload: Codable {
    let type: String
    let id: String
    let agent: String
    let title: String
    let command: String
    let description: String
    let risk: String
    let promptType: PromptInteractionType
    let options: [String]
    let optionsList: [VisionOptionItem]
}

struct VisionCommandInput: Codable {
    let action: String
    let promptId: String?
}

// MARK: - US keyboard key code map
private let keyCodeMap: [Character: CGKeyCode] = [
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "y": 16, "n": 45, "a": 0, " ": 49,
    "e": 14, "w": 13, "r": 15, "l": 37,
]

// MARK: - Screen coordinate for Codex button clicks
struct ClickTarget {
    let key: String
    let label: String
    let screenPoint: CGPoint
}

// MARK: - Main Engine

class VisionObserverEngine {
    private var isScanning = false
    private var lastScreenHash: Int = 0
    private var activePromptId: String = ""
    private var activePrompt: VisionPromptPayload? = nil
    private var isApprovedRecently = false
    private var cooldownUntil: Date = .distantPast

    // Retina / HiDPI scale factor (1.0 on non-Retina, 2.0 on Retina)
    private var displayScaleFactor: CGFloat = 1.0
    // Capture dimensions (logical pixels of the display)
    private var captureWidth: Int = 1920
    private var captureHeight: Int = 1080

    // Codex web-app button locations (updated each OCR pass)
    private var codexClickTargets: [ClickTarget] = []

    func start() {
        // Detect display scale factor once
        if let screen = NSScreen.main {
            displayScaleFactor = screen.backingScaleFactor
        }

        emitDict(["type": "vision_ready",
                  "scaleFactor": String(format: "%.1f", displayScaleFactor)])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readStdinLoop()
        }

        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.captureAndProcess() }
        }

        RunLoop.main.run()
    }

    // MARK: - Capture

    private func captureAndProcess() async {
        guard !isScanning, Date() > cooldownUntil else { return }
        isScanning = true
        defer { isScanning = false }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            captureWidth  = display.width
            captureHeight = display.height

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config  = SCStreamConfiguration()
            // Capture at logical resolution (not physical) so Vision coords map cleanly
            config.width  = captureWidth
            config.height = captureHeight
            config.showsCursor = false

            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            processWithVision(img)
        } catch {}
    }

    private func processWithVision(_ image: CGImage) {
        let req = VNRecognizeTextRequest { [weak self] (r, err) in
            guard let self, err == nil,
                  let obs = r.results as? [VNRecognizedTextObservation] else { return }
            self.analyzeObservations(obs)
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US", "zh-Hans"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
    }

    // MARK: - Analysis

    private func analyzeObservations(_ observations: [VNRecognizedTextObservation]) {
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let full  = lines.joined(separator: "\n")
        let lower = full.lowercased()

        let agent = detectAgent(lower: lower)
        guard isApprovalContext(agent: agent, lower: lower) else {
            handleClear(); return
        }

        let hash = lower.prefix(500).hashValue
        if hash == lastScreenHash { return }
        lastScreenHash = hash

        // For Codex web-app: extract button coordinates from Vision bounding boxes
        if agent == .codexApp {
            codexClickTargets = extractCodexButtons(from: observations)
        }

        let command     = extractCommand(agent: agent, lines: lines, lower: lower)
        let risk        = evaluateRisk(command: command)
        let optionsList = buildOptionList(agent: agent, lower: lower)

        let newId = "vis_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))"
        activePromptId = newId

        let payload = VisionPromptPayload(
            type:        "vision_prompt_detected",
            id:          newId,
            agent:       agent.rawValue,
            title:       promptTitle(agent: agent),
            command:     command,
            description: promptDescription(agent: agent),
            risk:        risk,
            promptType:  agent == .codexApp ? .clickable : .numberedMenu,
            options:     optionsList.map { $0.key },
            optionsList: optionsList
        )
        activePrompt = payload

        if let data = try? JSONEncoder().encode(payload),
           let json  = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write("\(json)\n".data(using: .utf8)!)
        }
        cooldownUntil = Date().addingTimeInterval(2.5)
    }

    private func handleClear() {
        if activePrompt != nil && isApprovedRecently {
            activePrompt       = nil
            isApprovedRecently = false
            lastScreenHash     = 0
            codexClickTargets  = []
            emitDict(["type": "prompt_cleared"])
        }
    }

    // MARK: - Detection

    private func detectAgent(lower: String) -> AgentType {
        if lower.contains("claude") || lower.contains("yes, allow once") ||
           lower.contains("yes, allow for this session") ||
           lower.contains("do you want to run this command") { return .claudeCode }
        if lower.contains("openai") || lower.contains("codex") ||
           (lower.contains("approve") && lower.contains("reject")) { return .codexApp }
        if lower.contains("antigravity") { return .antigravity }
        if lower.contains("aider")       { return .aider }
        return .unknown
    }

    private func isApprovalContext(agent: AgentType, lower: String) -> Bool {
        switch agent {
        case .claudeCode:
            return lower.contains("yes, allow once") ||
                   lower.contains("yes, allow for this session") ||
                   lower.contains("do you want to run this command")
        case .codexApp:
            return lower.contains("approve") && lower.contains("reject")
        default:
            return lower.contains("(y/n)") || lower.contains("[y/n") ||
                   lower.contains("1. yes") || lower.contains("allow this time")
        }
    }

    // MARK: - Codex Button Coordinate Extraction

    /// Vision returns normalized bounding boxes with (0,0) at bottom-left.
    /// We convert to logical screen pixels (top-left origin), then account for Retina scaling.
    private func extractCodexButtons(from observations: [VNRecognizedTextObservation]) -> [ClickTarget] {
        var targets: [ClickTarget] = []

        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let l = t.lowercased()

            guard l == "approve" || l == "reject" || l == "✓ approve" ||
                  l == "✗ reject" || l == "approve task" || l == "reject task" else { continue }

            let box = obs.boundingBox
            // Convert Vision normalized coords → logical screen pixels (no Retina factor here,
            // because ScreenCaptureKit already returns logical-resolution images)
            let x = box.midX * CGFloat(captureWidth)
            let y = (1.0 - box.midY) * CGFloat(captureHeight)
            let key = l.contains("approve") ? "approve" : "reject"
            targets.append(ClickTarget(key: key, label: t, screenPoint: CGPoint(x: x, y: y)))
        }
        return targets
    }

    // MARK: - Option Lists

    private func buildOptionList(agent: AgentType, lower: String) -> [VisionOptionItem] {
        switch agent {
        case .claudeCode:
            // Canonical Claude Code v2.x options — matches the TUI exactly
            return [
                VisionOptionItem(key: "1", label: "1. Yes, allow once",
                                 isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "2", label: "2. Yes, allow for this session",
                                 isPrimary: false, isDestructive: false),
                VisionOptionItem(key: "3", label: "3. No",
                                 isPrimary: false, isDestructive: true),
            ]
        case .codexApp:
            return [
                VisionOptionItem(key: "approve", label: "Approve",
                                 isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "reject",  label: "Reject",
                                 isPrimary: false, isDestructive: true),
            ]
        default:
            if lower.contains("always") {
                return [
                    VisionOptionItem(key: "y",      label: "y — Yes, allow once",  isPrimary: true,  isDestructive: false),
                    VisionOptionItem(key: "always", label: "a — Always allow",      isPrimary: false, isDestructive: false),
                    VisionOptionItem(key: "n",      label: "n — No, deny",          isPrimary: false, isDestructive: true),
                ]
            }
            return [
                VisionOptionItem(key: "y", label: "y — Yes, allow", isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "n", label: "n — No, deny",   isPrimary: false, isDestructive: true),
            ]
        }
    }

    // MARK: - Command Extraction

    private func extractCommand(agent: AgentType, lines: [String], lower: String) -> String {
        switch agent {
        case .claudeCode: return extractClaudeCommand(lines: lines)
        case .codexApp:   return extractCodexCommand(lines: lines)
        default:          return extractGenericCommand(lines: lines)
        }
    }

    private func extractClaudeCommand(lines: [String]) -> String {
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasPrefix("tool:") {
                let rest = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let p1 = rest.firstIndex(of: "("), let p2 = rest.lastIndex(of: ")") {
                    return String(rest[rest.index(after: p1)..<p2])
                }
                return rest
            }
            if t.lowercased().contains("do you want to run") {
                for j in (i+1)..<min(i+5, lines.count) {
                    let n = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    let nl = n.lowercased()
                    if !n.isEmpty && !nl.hasPrefix("1") && !nl.hasPrefix("2") && !nl.hasPrefix("3") { return n }
                }
            }
        }
        return extractGenericCommand(lines: lines)
    }

    private func extractCodexCommand(lines: [String]) -> String {
        if let idx = lines.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "approve" }) {
            for j in stride(from: idx - 1, through: max(0, idx - 6), by: -1) {
                let c = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if c.count > 8 && !["reject","codex","openai","approve"].contains(c.lowercased()) { return c }
            }
        }
        return extractGenericCommand(lines: lines)
    }

    private func extractGenericCommand(lines: [String]) -> String {
        let pfx = ["npm ","git ","node ","python","rm ","npx ","chmod ","docker ","bash ","sh ","curl ","wget ","pip ","make ","sudo "]
        for line in lines {
            var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("$") { t = t.dropFirst().trimmingCharacters(in: .whitespaces) }
            if pfx.contains(where: { t.hasPrefix($0) }) { return t }
        }
        return "AI Agent Task"
    }

    private func evaluateRisk(command: String) -> String {
        let c = command.lowercased()
        if ["rm ","--force","chmod ","drop ","delete ","sudo ","truncate"].contains(where: { c.contains($0) }) { return "high" }
        if ["push","deploy","npx ","npm ","curl","install"].contains(where: { c.contains($0) }) { return "medium" }
        return "low"
    }

    private func promptTitle(agent: AgentType) -> String {
        switch agent {
        case .claudeCode: return "Claude Code — Permission Required"
        case .codexApp:   return "OpenAI Codex — Approval Required"
        default:          return "\(agent.rawValue) — Permission Required"
        }
    }

    private func promptDescription(agent: AgentType) -> String {
        switch agent {
        case .claudeCode: return "Claude Code wants to execute a command. Tap an option:"
        case .codexApp:   return "OpenAI Codex is waiting for your approval to continue."
        default:          return "An AI agent is requesting permission to proceed."
        }
    }

    // MARK: - Decision Dispatch  ←  CORE STRATEGY

    private func readStdinLoop() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let cmd  = try? JSONDecoder().decode(VisionCommandInput.self, from: data) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.dispatchDecision(action: cmd.action)
            }
        }
    }

    private func dispatchDecision(action: String) {
        isApprovedRecently = true
        let key   = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let agent = activePrompt.map { AgentType(rawValue: $0.agent) ?? .unknown } ?? .unknown

        switch agent {

        // ────────────────────────────────────────────────
        // Claude Code: KEYBOARD IS PRIMARY — most stable
        //   • Presses number key (1/2/3) + Enter directly into the TUI
        //   • First activates the Claude Code terminal window via NSWorkspace
        //   • No coordinate dependency — works regardless of window position
        // ────────────────────────────────────────────────
        case .claudeCode:
            let digit: String
            switch key {
            case "1", "approve", "yes", "y": digit = "1"
            case "2":                          digit = "2"
            case "3", "reject", "no", "n":    digit = "3"
            default:                           digit = key
            }

            // Activate the terminal running Claude Code so keystrokes land correctly
            activateClaudeCodeWindow()
            usleep(150_000) // 150ms for window activation
            sendKeystroke(digit + "\r")

            emitDict(["type":   "keystroke_dispatched",
                      "agent":  "claude_code",
                      "method": "keyboard",
                      "sent":   digit + "↵"])

        // ────────────────────────────────────────────────
        // OpenAI Codex: MOUSE CLICK IS PRIMARY — only real option
        //   • Finds the Approve/Reject button via Vision OCR bounding box
        //   • Applies HiDPI scale correction automatically
        //   • Falls back to Tab+Enter if button not yet located
        // ────────────────────────────────────────────────
        case .codexApp:
            let isApprove = (key == "approve" || key == "yes" || key == "1" || key == "y")
            let targetKey = isApprove ? "approve" : "reject"

            if let target = codexClickTargets.first(where: { $0.key == targetKey }) {
                clickAt(target.screenPoint)
                emitDict(["type":   "keystroke_dispatched",
                          "agent":  "codex_app",
                          "method": "mouse_click",
                          "sent":   "click(\(Int(target.screenPoint.x)),\(Int(target.screenPoint.y)))",
                          "label":  target.label])
            } else {
                // Button not yet located — Tab to focus the primary button, Enter to confirm
                sendKeystroke("\t\r")
                emitDict(["type":   "keystroke_dispatched",
                          "agent":  "codex_app",
                          "method": "tab_enter_fallback",
                          "sent":   "Tab+↵",
                          "note":   "button_not_found_in_ocr"])
            }

        // ────────────────────────────────────────────────
        // Generic agents: prefer keyboard y/n
        // ────────────────────────────────────────────────
        default:
            let k: String
            switch key {
            case "1", "approve", "yes", "y": k = "y"
            case "always", "a":              k = "always"
            case "reject", "no", "n":        k = "n"
            default:                          k = key
            }
            sendKeystroke(k + "\r")
            emitDict(["type": "keystroke_dispatched", "agent": agent.rawValue,
                      "method": "keyboard", "sent": k + "↵"])
        }

        lastScreenHash = 0
    }

    // MARK: - Window Activation (for Claude Code keyboard strategy)

    /// Brings the terminal window running Claude Code to the foreground
    /// so that CGEvent keystrokes are delivered to it.
    private func activateClaudeCodeWindow() {
        let terminalBundleIDs = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty",
            "com.github.wez.wezterm",
        ]
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        // Activate the first matching terminal emulator that is running
        for bundleID in terminalBundleIDs {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }) {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
                return
            }
        }
        // Fallback: activate whatever is frontmost (user likely has terminal focused)
    }

    // MARK: - Mouse Click (Codex web-app)

    private func clickAt(_ point: CGPoint) {
        // ScreenCaptureKit captures at logical resolution; CGEvent expects logical points too.
        // No additional scale factor needed — they share the same coordinate space.
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard input

    private func sendKeystroke(_ str: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for ch in str {
            if ch == "\r" || ch == "\n" {
                postVKey(36, source: source)          // Return
            } else if let kc = keyCodeMap[ch] {
                postVKey(kc, source: source)
            } else {
                // Unicode fallback (e.g. "always" → a-l-w-a-y-s)
                var u16 = Array(String(ch).utf16)
                if let d = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                    d.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
                    d.post(tap: .cghidEventTap)
                }
                usleep(20_000)
                if let u = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    u.keyboardSetUnicodeString(stringLength: u16.count, unicodeString: &u16)
                    u.post(tap: .cghidEventTap)
                }
                usleep(20_000)
            }
        }
    }

    private func postVKey(_ code: CGKeyCode, source: CGEventSource?) {
        guard let d = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let u = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        d.post(tap: .cghidEventTap); usleep(30_000)
        u.post(tap: .cghidEventTap); usleep(30_000)
    }

    // MARK: - Emit

    private func emitDict(_ dict: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json  = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write("\(json)\n".data(using: .utf8)!)
        }
    }
}

// MARK: - Entry Point
let engine = VisionObserverEngine()
engine.start()
