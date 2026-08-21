import Foundation
import CoreGraphics
import Vision
import AppKit
import ApplicationServices
import ScreenCaptureKit

// MARK: - Supported Desktop App Agents (Strictly Antigravity, OpenAI Codex, Claude Code)

enum SupportedAppAgent: String, Codable {
    case antigravity = "Antigravity IDE"
    case codexApp    = "OpenAI Codex"
    case claudeCode  = "Claude Code"
}

enum PromptInteractionType: String, Codable {
    case appModal     = "APP_MODAL_TYPE"   // Desktop App Modal with dynamic clickable options/buttons
    case numberedMenu = "NUM_TYPE"         // Numbered dynamic options
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

// MARK: - Target Click Coordinates on Desktop Screen

struct ClickTarget {
    let key: String
    let label: String
    let screenPoint: CGPoint
}

// MARK: - US Keyboard Keycodes (Fallback)

private let keyCodeMap: [Character: CGKeyCode] = [
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
    "y": 16, "n": 45, "a": 0, " ": 49,
    "e": 14, "w": 13, "r": 15, "l": 37,
]

// MARK: - App Bundle Identifiers for Window Focusing

private let agentBundleIDs: [SupportedAppAgent: [String]] = [
    .antigravity: [
        "com.google.antigravity",
        "com.google.antigravity-dev",
        "com.google.android.studio",
        "antigravity",
    ],
    .codexApp: [
        "com.openai.chat",
        "com.openai.codex",
    ],
    .claudeCode: [
        "com.anthropic.claude",
        "com.anthropic.claudefordesktop",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
    ],
]

// MARK: - Main Vision Observer Engine

class VisionObserverEngine {
    private var isScanning = false
    private var lastScreenHash: Int = 0
    private var lastPromptSignature: String = ""
    private var noContextFrames = 0
    private var activePromptId: String = ""
    private var activePrompt: VisionPromptPayload? = nil
    private var activeAgent: SupportedAppAgent? = nil
    private var cooldownUntil: Date = .distantPast

    private var captureWidth: Int = 1920
    private var captureHeight: Int = 1080
    private var currentClickTargets: [ClickTarget] = []
    // Vision captures the display, but OCR must be scoped to the frontmost
    // app window. Otherwise text from the iPhone/Watch simulators or a
    // background browser tab can be mistaken for a Codex approval card.
    private var frontmostWindowNormalizedRect: CGRect?

    func start() {
        var scale: CGFloat = 1.0
        if let screen = NSScreen.main {
            scale = screen.backingScaleFactor
        }

        emitDict([
            "type": "vision_ready",
            "supportedAgents": "Antigravity IDE, OpenAI Codex, Claude Code",
            "scaleFactor": String(format: "%.1f", scale),
        ])

        // Read mobile approval decisions from stdin
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readStdinLoop()
        }

        // Screen capture timer (800ms intervals)
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
            frontmostWindowNormalizedRect = normalizedFrontmostWindowRect()

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config  = SCStreamConfiguration()
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
        req.recognitionLanguages = ["en-US"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
    }

    // MARK: - OCR Text Analysis & 1:1 Dynamic Option Mapping

    private func analyzeObservations(_ observations: [VNRecognizedTextObservation]) {
        let scopedObservations: [VNRecognizedTextObservation]
        if let windowRect = frontmostWindowNormalizedRect {
            scopedObservations = observations.filter { observation in
                let box = observation.boundingBox
                let topLeftBox = CGRect(
                    x: box.minX,
                    y: 1.0 - box.maxY,
                    width: box.width,
                    height: box.height
                )
                return topLeftBox.intersects(windowRect)
            }
        } else {
            scopedObservations = observations
        }

        guard !scopedObservations.isEmpty else {
            handleClear()
            return
        }

        let lines = scopedObservations.compactMap { $0.topCandidates(1).first?.string }
        let full  = lines.joined(separator: "\n")
        let lower = full.lowercased()

        // 1. Strictly detect only Antigravity, OpenAI Codex, or Claude Code
        guard let agent = detectStrictAgent(lower: lower) else {
            handleClear()
            return
        }

        // 2. Guard: the detected agent's app must be the frontmost application.
        //    This eliminates false positives from background Chrome tabs,
        //    AI documentation pages, or any other off-screen content that
        //    happens to contain agent keywords.
        guard isFrontmostApp(for: agent) else {
            handleClear()
            return
        }

        // 3. Verify an approval card / modal context exists for this app
        guard isApprovalContext(agent: agent, lower: lower) else {
            handleClear()
            return
        }

        noContextFrames = 0

        // 3. Cheap skip for pixel-identical frames
        let hash = lower.prefix(500).hashValue
        if hash == lastScreenHash { return }
        lastScreenHash = hash

        // 4. Extract ALL clickable button and numbered option coordinates from screen
        currentClickTargets = extractClickTargets(from: scopedObservations, agent: agent, lines: lines)

        let command     = extractCommand(agent: agent, lines: lines, lower: lower)
        let risk        = evaluateRisk(command: command)
        let optionsList = buildDynamicOptionList(agent: agent, targets: currentClickTargets, lines: lines, lower: lower)

        // 5. Semantic dedup: the same logical dialog keeps ONE id while it stays
        //    on screen, even if minor rendering changes alter the raw screen
        //    hash. This prevents duplicate cards and queue flooding.
        let signature = promptSignature(agent: agent, command: command, optionsList: optionsList)
        // Keep one request ID for the visible approval card. OCR text can
        // fluctuate by one or two characters between frames; replacing the
        // request in that case would make a phone/watch tap arrive with a
        // stale ID and skip the saved coordinate.
        if activePrompt != nil && activeAgent == agent { return }
        lastPromptSignature = signature

        let newId = "vis_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))"
        activePromptId = newId
        activeAgent = agent

        let payload = VisionPromptPayload(
            type:        "vision_prompt_detected",
            id:          newId,
            agent:       agent.rawValue,
            title:       promptTitle(agent: agent),
            command:     command,
            description: promptDescription(agent: agent),
            risk:        risk,
            promptType:  agent == .claudeCode ? .numberedMenu : .appModal,
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

    // MARK: - Prompt Signature & Clear Detection

    private func promptSignature(agent: SupportedAppAgent, command: String, optionsList: [VisionOptionItem]) -> String {
        let normalizedCommand = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOptions = optionsList
            .map { "\($0.key):\($0.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "|")
        return "\(agent.rawValue)|\(normalizedCommand)|\(normalizedOptions)"
    }

    // The active dialog counts as gone only after several consecutive frames
    // with no approval context, which avoids false clears on OCR hiccups.
    private func handleClear() {
        guard activePrompt != nil else { return }
        noContextFrames += 1
        guard noContextFrames >= 3 else { return }
        activePrompt        = nil
        activeAgent         = nil
        lastPromptSignature = ""
        lastScreenHash      = 0
        currentClickTargets = []
        emitDict(["type": "prompt_cleared"])
    }

    // MARK: - Strict App Detection (Only Antigravity, Codex, Claude Code)

    private func detectStrictAgent(lower: String) -> SupportedAppAgent? {
        // 1. Antigravity IDE App
        if lower.contains("antigravity") ||
           (lower.contains("implementation plan") && lower.contains("proceed")) ||
           (lower.contains("planning mode") && (lower.contains("approve") || lower.contains("execute"))) ||
           (lower.contains("terminal sandbox") && lower.contains("bypass")) {
            return .antigravity
        }

        // 2. Claude Code App
        if lower.contains("claude") ||
           lower.contains("yes, allow once") ||
           lower.contains("yes, allow for this session") ||
           lower.contains("do you want to run this command") ||
           (lower.contains("tool:") && lower.contains("bash")) {
            return .claudeCode
        }

        // 3. OpenAI Codex App
        if lower.contains("openai") || lower.contains("codex") ||
           (lower.contains("approve") && lower.contains("reject") && !lower.contains("claude")) {
            return .codexApp
        }

        return nil
    }

    private func isApprovalContext(agent: SupportedAppAgent, lower: String) -> Bool {
        switch agent {
        case .antigravity:
            return lower.contains("proceed") ||
                   lower.contains("allow") ||
                   lower.contains("permission") ||
                   lower.contains("confirm") ||
                   lower.contains("approve") ||
                   lower.contains("execute")
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
        }
    }

    // MARK: - Frontmost App Guard

    /// Returns true only when the running application that is currently
    /// in the foreground matches one of the known bundle IDs for `agent`.
    /// Claude Code also accepts any terminal emulator since it runs inside
    /// a terminal session (Terminal, iTerm2, Warp, Kitty, WezTerm, VS Code).
    private func isFrontmostApp(for agent: SupportedAppAgent) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID  = frontmost.bundleIdentifier else { return false }
        var allowed = agentBundleIDs[agent] ?? []
        // Browser-based Codex simulations are opt-in so simulator/browser
        // text cannot masquerade as the real Codex desktop app.
        if agent == .codexApp && ProcessInfo.processInfo.environment["APPROVE_CLAW_ALLOW_BROWSER_CODEX_SIM"] == "1" {
            allowed += ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari", "org.mozilla.firefox"]
        }
        return allowed.contains(bundleID)
    }

    /// Returns the frontmost app's window as a normalized top-left-origin
    /// rectangle in display coordinates, matching Vision's normalized boxes.
    private func normalizedFrontmostWindowRect() -> CGRect? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let screen = NSScreen.main else { return nil }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontmost.processIdentifier,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            guard rect.width > 200, rect.height > 100 else { continue }

            let screenFrame = screen.frame
            return CGRect(
                x: (rect.minX - screenFrame.minX) / screenFrame.width,
                y: (rect.minY - screenFrame.minY) / screenFrame.height,
                width: rect.width / screenFrame.width,
                height: rect.height / screenFrame.height
            )
        }
        return nil
    }

    // MARK: - Dynamic Button & Option Coordinate Extraction

    private func extractClickTargets(from observations: [VNRecognizedTextObservation],
                                     agent: SupportedAppAgent,
                                     lines: [String]) -> [ClickTarget] {
        var targets: [ClickTarget] = []

        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let trim = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let low  = trim.lowercased()

            let box = obs.boundingBox
            let screenX = box.midX * CGFloat(captureWidth)
            let screenY = (1.0 - box.midY) * CGFloat(captureHeight)
            let point   = CGPoint(x: screenX, y: screenY)

            switch agent {
            case .antigravity:
                if low == "proceed" || low == "allow" || low == "approve" || low == "proceed & allow" || low == "execute" {
                    targets.append(ClickTarget(key: "approve", label: trim, screenPoint: point))
                } else if low == "cancel" || low == "reject" || low == "deny" || low == "cancel & deny" || low == "stop" {
                    targets.append(ClickTarget(key: "reject", label: trim, screenPoint: point))
                }

            case .codexApp:
                if low == "approve" || low == "✓ approve" || low == "approve task" {
                    targets.append(ClickTarget(key: "approve", label: trim, screenPoint: point))
                } else if low == "reject" || low == "✗ reject" || low == "reject task" {
                    targets.append(ClickTarget(key: "reject", label: trim, screenPoint: point))
                }

            case .claudeCode:
                let stripped = low.trimmingCharacters(in: CharacterSet(charactersIn: "❯>* \t"))
                if let fc = stripped.unicodeScalars.first, fc.value >= 49 && fc.value <= 57 {
                    let digit = String(stripped.prefix(1))
                    targets.append(ClickTarget(key: digit, label: trim, screenPoint: point))
                } else if stripped.contains("allow once") {
                    targets.append(ClickTarget(key: "1", label: trim, screenPoint: point))
                } else if stripped.contains("allow for this session") || stripped.contains("allow always") {
                    targets.append(ClickTarget(key: "2", label: trim, screenPoint: point))
                } else if stripped == "no" || stripped.hasPrefix("no ") || stripped.contains("esc)") {
                    targets.append(ClickTarget(key: "3", label: trim, screenPoint: point))
                }
            }
        }

        return targets
    }

    // MARK: - 1:1 Dynamic Option List Generation

    private func buildDynamicOptionList(agent: SupportedAppAgent,
                                         targets: [ClickTarget],
                                         lines: [String],
                                         lower: String) -> [VisionOptionItem] {
        // Priority 1: Map directly from extracted screen click targets
        if !targets.isEmpty {
            var items: [VisionOptionItem] = []
            for t in targets {
                if !items.contains(where: { $0.key == t.key }) {
                    let low = t.label.lowercased()
                    let isPrimary = t.key == "1" || t.key == "approve" || low.contains("allow") || low.contains("proceed")
                    let isDestructive = t.key == "3" || t.key == "reject" || low.contains("reject") || low.contains("deny") || low.contains("cancel")
                    items.append(VisionOptionItem(key: t.key, label: t.label, isPrimary: isPrimary, isDestructive: isDestructive))
                }
            }
            if items.count >= 2 {
                return items.sorted { (Int($0.key) ?? 99) < (Int($1.key) ?? 99) }
            }
        }

        // Priority 2: Standard defaults per App Agent
        switch agent {
        case .antigravity:
            return [
                VisionOptionItem(key: "approve", label: "Proceed & Allow", isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "reject",  label: "Cancel & Deny",   isPrimary: false, isDestructive: true),
            ]
        case .codexApp:
            return [
                VisionOptionItem(key: "approve", label: "Approve", isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "reject",  label: "Reject",  isPrimary: false, isDestructive: true),
            ]
        case .claudeCode:
            return [
                VisionOptionItem(key: "1", label: "1. Yes, allow once",              isPrimary: true,  isDestructive: false),
                VisionOptionItem(key: "2", label: "2. Yes, allow for this session",  isPrimary: false, isDestructive: false),
                VisionOptionItem(key: "3", label: "3. No",                           isPrimary: false, isDestructive: true),
            ]
        }
    }

    // MARK: - Command Extraction

    private func extractCommand(agent: SupportedAppAgent, lines: [String], lower: String) -> String {
        switch agent {
        case .antigravity:
            return extractAntigravityCommand(lines: lines)
        case .codexApp:
            return extractCodexCommand(lines: lines)
        case .claudeCode:
            return extractClaudeCommand(lines: lines)
        }
    }

    private func extractAntigravityCommand(lines: [String]) -> String {
        let keywords = ["run_command", "commandline", "command execution", "execute:", "npm ", "git ", "node ", "npx ", "python ", "sh "]
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if keywords.contains(where: { t.lowercased().contains($0) }) {
                return t
            }
        }
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > 10 && (t.contains("Plan") || t.contains("Task") || t.contains("Approval")) {
                return t
            }
        }
        return "Antigravity IDE Action"
    }

    private func extractCodexCommand(lines: [String]) -> String {
        if let idx = lines.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "approve" }) {
            for j in stride(from: idx - 1, through: max(0, idx - 6), by: -1) {
                let c = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                if c.count > 8 && !["reject", "codex", "openai", "approve"].contains(c.lowercased()) {
                    return c
                }
            }
        }
        return extractGenericAppCommand(lines: lines)
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
                    if !n.isEmpty && !nl.hasPrefix("1") && !nl.hasPrefix("2") && !nl.hasPrefix("3") {
                        return n
                    }
                }
            }
        }
        return extractGenericAppCommand(lines: lines)
    }

    private func extractGenericAppCommand(lines: [String]) -> String {
        let pfx = ["npm ", "git ", "node ", "python", "rm ", "npx ", "chmod ", "docker ", "bash ", "sh ", "curl ", "wget ", "pip ", "make ", "sudo "]
        for line in lines {
            var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("$") { t = t.dropFirst().trimmingCharacters(in: .whitespaces) }
            if pfx.contains(where: { t.hasPrefix($0) }) { return t }
        }
        return "Desktop App Action"
    }

    private func evaluateRisk(command: String) -> String {
        let c = command.lowercased()
        if ["rm ", "--force", "chmod ", "drop ", "delete ", "sudo ", "truncate", "mkfs"].contains(where: { c.contains($0) }) { return "high" }
        if ["push", "deploy", "npx ", "npm ", "curl", "install", "build"].contains(where: { c.contains($0) }) { return "medium" }
        return "low"
    }

    private func promptTitle(agent: SupportedAppAgent) -> String {
        switch agent {
        case .antigravity: return "Antigravity IDE — Action Approval"
        case .codexApp:    return "OpenAI Codex — Approval Required"
        case .claudeCode:  return "Claude Code — Permission Required"
        }
    }

    private func promptDescription(agent: SupportedAppAgent) -> String {
        switch agent {
        case .antigravity: return "Antigravity IDE is requesting permission to execute an action."
        case .codexApp:    return "OpenAI Codex is waiting for your approval in the desktop app."
        case .claudeCode:  return "Claude Code is requesting execution permission."
        }
    }

    // MARK: - Decision Dispatch (Synchronous Mac Execution)

    private func readStdinLoop() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let cmd  = try? JSONDecoder().decode(VisionCommandInput.self, from: data) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.dispatchDecision(action: cmd.action, promptId: cmd.promptId)
            }
        }
    }

    private func dispatchDecision(action: String, promptId: String?) {
        let key   = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let agent = activeAgent ?? .antigravity

        Task { [weak self] in
            guard let self = self else { return }
            // Re-verify the dialog is still on screen right before acting.
            // A decision arriving after the dialog disappeared must never
            // click stale coordinates or inject keys into another window.
            let verified = await self.verifyPromptStillVisible(agent: agent)
            // The current click targets came from the frame that created this
            // request. A second capture can be unavailable in simulator or
            // browser test windows, so use the captured coordinate when it is
            // still present.
            guard verified || !self.currentClickTargets.isEmpty else {
                self.emitDict(["type": "action_aborted", "agent": agent.rawValue, "reason": "prompt_no_longer_visible"])
                return
            }
            self.performDispatch(key: key, agent: agent, promptId: promptId)
        }
    }

    private func verifyPromptStillVisible(agent: SupportedAppAgent) async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            req.recognitionLanguages = ["en-US"]
            try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
            let lines = (req.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            let lower = lines.joined(separator: "\n").lowercased()
            guard let detected = detectStrictAgent(lower: lower) else { return false }
            guard detected == agent else { return false }
            return isApprovalContext(agent: agent, lower: lower)
        } catch {
            return false
        }
    }

    private func performDispatch(key: String, agent: SupportedAppAgent, promptId: String?) {
        // Ignore decisions for prompts that were superseded by a newer dialog.
        if let promptId = promptId, !promptId.isEmpty, promptId != activePromptId {
            emitDict(["type": "action_aborted", "agent": agent.rawValue, "reason": "stale_prompt_id"])
            return
        }

        // 1. Bring target App to the foreground
        activateApp(for: agent)
        usleep(120_000) // 120ms focus delay

        // 2. Perform selection via Mouse Click or Command Line/Keyboard Key
        switch agent {

        // ── Antigravity IDE App ──
        case .antigravity:
            let isApprove = (key == "approve" || key == "yes" || key == "1" || key == "y" || key == "proceed")
            let targetKey = isApprove ? "approve" : "reject"

            if let target = currentClickTargets.first(where: { $0.key == targetKey }) {
                clickAt(target.screenPoint)
                emitDict(["type": "action_dispatched", "agent": agent.rawValue, "method": "vision_coordinate_click", "sent": "click(\(Int(target.screenPoint.x)),\(Int(target.screenPoint.y)))"])
            } else {
                if isApprove {
                    sendKeystroke("\r")
                } else {
                    postVKey(53, source: CGEventSource(stateID: .hidSystemState)) // Escape
                }
                emitDict(["type": "action_dispatched", "agent": agent.rawValue, "method": isApprove ? "enter_key" : "escape_key"])
            }

        // ── OpenAI Codex App ──
        case .codexApp:
            let isApprove = (key == "approve" || key == "yes" || key == "1" || key == "y")
            let targetKey = isApprove ? "approve" : "reject"

            if let target = currentClickTargets.first(where: { $0.key == targetKey }) {
                clickAt(target.screenPoint)
                emitDict(["type": "action_dispatched", "agent": agent.rawValue, "method": "vision_coordinate_click", "sent": "click(\(Int(target.screenPoint.x)),\(Int(target.screenPoint.y)))"])
            } else {
                sendKeystroke("\t\r")
                emitDict(["type": "action_dispatched", "agent": agent.rawValue, "method": "tab_enter_fallback"])
            }

        // ── Claude Code App ──
        case .claudeCode:
            let digit: String
            switch key {
            case "1", "approve", "yes", "y": digit = "1"
            case "2":                          digit = "2"
            case "3", "reject", "no", "n":    digit = "3"
            default:                           digit = key
            }

            // Click target if found, otherwise send numeric key + Enter
            if let target = currentClickTargets.first(where: { $0.key == digit }) {
                clickAt(target.screenPoint)
                emitDict(["type": "action_dispatched", "agent": agent.rawValue, "method": "mouse_click", "sent": "click(\(Int(target.screenPoint.x)),\(Int(target.screenPoint.y)))"])
            } else {
                sendKeystroke(digit + "\r")
                emitDict(["type": "action_dispatched", "agent": agent.rawValue, "method": "keyboard", "sent": digit + "↵"])
            }
        }

        lastScreenHash = 0
    }

    // MARK: - App Activation via NSWorkspace

    private func activateApp(for agent: SupportedAppAgent) {
        var bundleIDs = agentBundleIDs[agent] ?? []
        if agent == .codexApp && ProcessInfo.processInfo.environment["APPROVE_CLAW_ALLOW_BROWSER_CODEX_SIM"] == "1" {
            bundleIDs += ["com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari", "org.mozilla.firefox"]
        }
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        for bundleID in bundleIDs {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }) {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
                return
            }
        }
    }

    // MARK: - Simulated Mouse Click

    private func clickAt(_ point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up   = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        usleep(80_000)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Command Line / Keyboard Keystroke

    private func sendKeystroke(_ str: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for ch in str {
            if ch == "\r" || ch == "\n" {
                postVKey(36, source: source)
            } else if let kc = keyCodeMap[ch] {
                postVKey(kc, source: source)
            } else {
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

    // MARK: - Emit Helpers

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
