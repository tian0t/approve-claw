import Foundation
import CoreGraphics
import Vision
import AppKit
import ApplicationServices
import ScreenCaptureKit

// MARK: - Agent Types

enum AgentType: String {
    case claudeCode  = "Claude Code"     // React Ink TUI — arrow keys + Enter, or mouse click
    case codexApp    = "OpenAI Codex"    // Web/desktop app — Approve/Reject buttons
    case antigravity = "Antigravity IDE"
    case aider       = "Aider"
    case unknown     = "AI Agent"
}

enum PromptInteractionType: String, Codable {
    case clickable   = "CLICK_TYPE"      // Both Claude Code TUI and Codex web: use mouse clicks
    case yOrN        = "YN_TYPE"
    case yNAlways    = "YNA_TYPE"
    case numberedMenu = "NUM_TYPE"
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

// MARK: - Detected clickable region on screen

struct ClickTarget {
    let label: String      // e.g. "1. Yes, allow once"
    let key: String        // e.g. "1"
    let screenPoint: CGPoint
}

// MARK: - Keystroke key map (US keyboard, fallback only)
private let keyCodeMap: [Character: CGKeyCode] = [
    "1": 18, "2": 19, "3": 20, "y": 16, "Y": 16,
    "n": 45, "N": 45, "a": 0, " ": 49,
]

// MARK: - Main Engine

class VisionObserverEngine {
    private var isScanning = false
    private var lastScreenHash: Int = 0
    private var activePromptId: String = ""
    private var activePrompt: VisionPromptPayload? = nil
    private var isApprovedRecently = false
    private var cooldownUntil: Date = .distantPast

    // Screen resolution for coordinate mapping
    private var captureWidth: Int = 1920
    private var captureHeight: Int = 1080

    // Live click targets discovered from the current screen frame
    private var currentClickTargets: [ClickTarget] = []

    func start() {
        emitDict(["type": "vision_ready"])

        // Read mobile decisions from stdin (piped by Node.js bridge)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readStdinLoop()
        }

        // Screen capture loop — 800ms is responsive without overloading
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.captureAndProcess() }
        }

        RunLoop.main.run()
    }

    // MARK: - Screen Capture

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
            config.width  = captureWidth
            config.height = captureHeight
            config.showsCursor = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            processWithVision(cgImage)
        } catch {}
    }

    private func processWithVision(_ image: CGImage) {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let req = VNRecognizeTextRequest { [weak self] (r, err) in
            guard let self, err == nil,
                  let obs = r.results as? [VNRecognizedTextObservation] else { return }
            self.analyzeObservations(obs)
        }
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = ["en-US", "zh-Hans"]
        try? handler.perform([req])
    }

    // MARK: - Analysis

    private func analyzeObservations(_ observations: [VNRecognizedTextObservation]) {
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let fullText = lines.joined(separator: "\n")
        let lower    = fullText.lowercased()

        let agent = detectAgent(lower: lower)

        guard isApprovalContext(agent: agent, lower: lower) else {
            handleClear()
            return
        }

        let hash = lower.prefix(500).hashValue
        if hash == lastScreenHash { return }
        lastScreenHash = hash

        // Build click targets from bounding boxes
        currentClickTargets = buildClickTargets(from: observations, agent: agent, lower: lower)

        let command      = extractCommand(agent: agent, lines: lines, lower: lower)
        let risk         = evaluateRisk(command: command)
        let optionsList  = buildOptionList(agent: agent, clickTargets: currentClickTargets, lower: lower)

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
            promptType:  .clickable,
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
            currentClickTargets = []
            emitDict(["type": "prompt_cleared"])
        }
    }

    // MARK: - Agent Detection

    private func detectAgent(lower: String) -> AgentType {
        // Claude Code: its TUI contains distinctive phrases
        if lower.contains("claude") ||
           lower.contains("yes, allow once") ||
           lower.contains("yes, allow for this session") ||
           lower.contains("do you want to run") {
            return .claudeCode
        }
        // OpenAI Codex web/desktop app
        if lower.contains("openai") || lower.contains("codex") ||
           (lower.contains("approve") && lower.contains("reject")) {
            return .codexApp
        }
        if lower.contains("antigravity") { return .antigravity }
        if lower.contains("aider")       { return .aider }
        return .unknown
    }

    private func isApprovalContext(agent: AgentType, lower: String) -> Bool {
        switch agent {
        case .claudeCode:
            return lower.contains("yes, allow once") ||
                   lower.contains("yes, allow for this session") ||
                   lower.contains("do you want to run this command") ||
                   (lower.contains("claude") && lower.contains("allow"))
        case .codexApp:
            return (lower.contains("approve") && lower.contains("reject")) ||
                   lower.contains("ask for approval") ||
                   lower.contains("waiting for approval") ||
                   lower.contains("needs approval")
        default:
            return lower.contains("allow this time") ||
                   lower.contains("(y/n)") || lower.contains("[y/n") ||
                   lower.contains("1. yes") || lower.contains("wants to run")
        }
    }

    // MARK: - Click Target Extraction (Vision bounding boxes → screen pixels)

    /// Scans all OCR observations for clickable option text and converts
    /// their normalized bounding boxes to actual screen pixel coordinates.
    private func buildClickTargets(from observations: [VNRecognizedTextObservation],
                                   agent: AgentType,
                                   lower: String) -> [ClickTarget] {
        var targets: [ClickTarget] = []

        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let tLow    = trimmed.lowercased()

            // Vision gives normalized coords with (0,0) at bottom-left.
            // Convert to screen coords with (0,0) at top-left.
            let box = obs.boundingBox
            let screenX = box.midX * CGFloat(captureWidth)
            let screenY = (1.0 - box.midY) * CGFloat(captureHeight)
            let point   = CGPoint(x: screenX, y: screenY)

            switch agent {
            case .claudeCode:
                // React Ink TUI options: lines starting with ❯ or a number like "1. Yes, allow once"
                if let key = claudeCodeOptionKey(tLow) {
                    targets.append(ClickTarget(label: trimmed, key: key, screenPoint: point))
                }

            case .codexApp:
                // Codex web app: standalone "Approve" and "Reject" button labels
                if tLow == "approve" || tLow == "✓ approve" || tLow == "approve task" {
                    targets.append(ClickTarget(label: trimmed, key: "approve", screenPoint: point))
                } else if tLow == "reject" || tLow == "✗ reject" || tLow == "reject task" {
                    targets.append(ClickTarget(label: trimmed, key: "reject", screenPoint: point))
                }

            default:
                // Generic: numbered options or y/n
                if let fc = trimmed.unicodeScalars.first, fc.value >= 49, fc.value <= 57 {
                    let digit = String(trimmed.prefix(1))
                    targets.append(ClickTarget(label: trimmed, key: digit, screenPoint: point))
                } else if tLow.hasPrefix("y ") || tLow == "y" || tLow.hasPrefix("yes") {
                    targets.append(ClickTarget(label: trimmed, key: "y", screenPoint: point))
                } else if tLow.hasPrefix("n ") || tLow == "n" || tLow.hasPrefix("no") {
                    targets.append(ClickTarget(label: trimmed, key: "n", screenPoint: point))
                }
            }
        }

        return targets
    }

    /// Maps known Claude Code TUI option text to a canonical key
    private func claudeCodeOptionKey(_ lower: String) -> String? {
        // Strip leading selector markers (❯, >, *, spaces)
        let stripped = lower.trimmingCharacters(in: CharacterSet(charactersIn: "❯>* \t"))

        if stripped.hasPrefix("1") || stripped.contains("allow once") {
            return "1"
        }
        if stripped.hasPrefix("2") || stripped.contains("allow for this session") || stripped.contains("allow always") {
            return "2"
        }
        if stripped.hasPrefix("3") || stripped == "no" || stripped.hasPrefix("no ") ||
           stripped.contains("no (") || stripped.contains("esc)") {
            return "3"
        }
        return nil
    }

    // MARK: - Option List for iOS display

    private func buildOptionList(agent: AgentType, clickTargets: [ClickTarget], lower: String) -> [VisionOptionItem] {
        // Prefer click targets found on screen (verbatim labels)
        if !clickTargets.isEmpty {
            return clickTargets.map { target in
                let isPrimary     = target.key == "1" || target.key == "approve" || target.key == "y"
                let isDestructive = target.key == "3" || target.key == "reject"  || target.key == "n"
                return VisionOptionItem(key: target.key, label: target.label,
                                        isPrimary: isPrimary, isDestructive: isDestructive)
            }
        }

        // Hardcoded fallbacks per agent
        switch agent {
        case .claudeCode:
            return [
                VisionOptionItem(key: "1", label: "1. Yes, allow once",             isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "2", label: "2. Yes, allow for this session",  isPrimary: false, isDestructive: false),
                VisionOptionItem(key: "3", label: "3. No",                           isPrimary: false, isDestructive: true),
            ]
        case .codexApp:
            return [
                VisionOptionItem(key: "approve", label: "Approve", isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "reject",  label: "Reject",  isPrimary: false, isDestructive: true),
            ]
        default:
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
        case .codexApp:   return extractCodexCommand(lines: lines, lower: lower)
        default:          return extractGenericCommand(lines: lines)
        }
    }

    /// Claude Code TUI: "Tool: Bash(command)" or the line after "Do you want to run"
    private func extractClaudeCommand(lines: [String]) -> String {
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // "Tool: Bash(git push origin main)"
            if t.lowercased().hasPrefix("tool:") {
                let rest = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let p1 = rest.firstIndex(of: "("), let p2 = rest.lastIndex(of: ")") {
                    return String(rest[rest.index(after: p1)..<p2])
                }
                return rest
            }
            // "Do you want to run this command?" — command is on the next substantive line
            if t.lowercased().contains("do you want to run") {
                for j in (i+1)..<min(i+5, lines.count) {
                    let next = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !next.isEmpty && claudeCodeOptionKey(next.lowercased()) == nil {
                        return next
                    }
                }
            }
        }
        return extractGenericCommand(lines: lines)
    }

    /// Codex web: task description appears above the Approve button
    private func extractCodexCommand(lines: [String], lower: String) -> String {
        if let idx = lines.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "approve" }) {
            for j in stride(from: idx - 1, through: max(0, idx - 6), by: -1) {
                let c = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if c.count > 8 && !c.lowercased().contains("reject") &&
                   !c.lowercased().contains("codex") && !c.lowercased().contains("openai") {
                    return c
                }
            }
        }
        return extractGenericCommand(lines: lines)
    }

    private func extractGenericCommand(lines: [String]) -> String {
        let shellPrefixes = ["npm ", "git ", "node ", "python", "rm ", "npx ", "chmod ",
                             "docker ", "bash ", "sh ", "curl ", "wget ", "pip ", "make ", "sudo "]
        for line in lines {
            var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("$") { t = t.dropFirst().trimmingCharacters(in: .whitespaces) }
            if shellPrefixes.contains(where: { t.hasPrefix($0) }) { return t }
        }
        return "AI Agent Task"
    }

    private func evaluateRisk(command: String) -> String {
        let c = command.lowercased()
        if ["rm ", "--force", "chmod ", "drop ", "delete ", "sudo ", "truncate"].contains(where: { c.contains($0) }) { return "high" }
        if ["push", "deploy", "npx ", "npm ", "curl", "install"].contains(where: { c.contains($0) }) { return "medium" }
        return "low"
    }

    // MARK: - Labels

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

    // MARK: - Decision Dispatch (Mouse Click Primary Strategy)

    private func readStdinLoop() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let cmd = try? JSONDecoder().decode(VisionCommandInput.self, from: data) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.dispatchDecision(action: cmd.action)
            }
        }
    }

    private func dispatchDecision(action: String) {
        isApprovedRecently = true
        let key = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Normalize action to canonical key
        let resolvedKey: String
        switch key {
        case "approve", "yes", "y": resolvedKey = "approve_or_1"
        case "reject", "no", "n":   resolvedKey = "reject_or_3"
        default:                     resolvedKey = key
        }

        // Strategy 1: Click the matching target found on screen (most reliable)
        if let target = findClickTarget(for: resolvedKey) {
            clickAt(target.screenPoint)
            emitDict([
                "type":   "keystroke_dispatched",
                "agent":  activePrompt?.agent ?? "unknown",
                "action": key,
                "sent":   "mouse_click(\(Int(target.screenPoint.x)),\(Int(target.screenPoint.y)))",
                "label":  target.label
            ])
            lastScreenHash = 0
            return
        }

        // Strategy 2: Fallback — send keyboard input based on agent type
        let agent = activePrompt.map { AgentType(rawValue: $0.agent) ?? .unknown } ?? .unknown
        let keystroke: String

        switch agent {
        case .claudeCode:
            // Claude Code TUI also accepts number keys
            switch resolvedKey {
            case "approve_or_1": keystroke = "1\r"
            case "reject_or_3":  keystroke = "3\r"
            default:             keystroke = key + "\r"
            }
        case .codexApp:
            // No reliable keystroke for Codex web — Tab to focus, Enter to click
            keystroke = "\t\r"
        default:
            switch resolvedKey {
            case "approve_or_1": keystroke = "y\r"
            case "reject_or_3":  keystroke = "n\r"
            default:             keystroke = key + "\r"
            }
        }

        sendKeystrokeString(keystroke)
        emitDict([
            "type":   "keystroke_dispatched",
            "agent":  activePrompt?.agent ?? "unknown",
            "action": key,
            "sent":   keystroke.replacingOccurrences(of: "\r", with: "↵"),
            "note":   "fallback_keyboard"
        ])
        lastScreenHash = 0
    }

    /// Find the click target on screen matching the user's choice
    private func findClickTarget(for resolvedKey: String) -> ClickTarget? {
        switch resolvedKey {
        case "approve_or_1":
            return currentClickTargets.first { $0.key == "1" || $0.key == "approve" || $0.key == "y" }
        case "reject_or_3":
            return currentClickTargets.first { $0.key == "3" || $0.key == "reject" || $0.key == "n" }
        case "2":
            return currentClickTargets.first { $0.key == "2" }
        default:
            return currentClickTargets.first { $0.key == resolvedKey }
        }
    }

    // MARK: - Mouse Click

    private func clickAt(_ point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard Fallback

    private func sendKeystrokeString(_ str: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for ch in str {
            if ch == "\r" || ch == "\n" {
                postVKey(36, source: source)
            } else if let kc = keyCodeMap[ch] {
                postVKey(kc, source: source)
            } else {
                var utf16 = Array(String(ch).utf16)
                if let d = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                    d.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    d.post(tap: .cghidEventTap)
                }
                usleep(20_000)
                if let u = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    u.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    u.post(tap: .cghidEventTap)
                }
                usleep(20_000)
            }
        }
    }

    private func postVKey(_ keyCode: CGKeyCode, source: CGEventSource?) {
        guard let d = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let u = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        d.post(tap: .cghidEventTap); usleep(30_000)
        u.post(tap: .cghidEventTap); usleep(30_000)
    }

    // MARK: - Stdout helper

    private func emitDict(_ dict: [String: String]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write("\(json)\n".data(using: .utf8)!)
        }
    }
}

// MARK: - Entry Point
let engine = VisionObserverEngine()
engine.start()
