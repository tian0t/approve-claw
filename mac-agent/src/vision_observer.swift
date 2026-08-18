import Foundation
import CoreGraphics
import Vision
import AppKit
import ApplicationServices
import ScreenCaptureKit

enum PromptInteractionType: String, Codable {
    case yOrN = "YN_TYPE"
    case numberedMenu = "NUM_TYPE"
    case enterDefault = "ENTER_TYPE"
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

struct VisionOptionItem: Codable {
    let key: String
    let label: String
    let isPrimary: Bool
    let isDestructive: Bool
}

struct VisionCommandInput: Codable {
    let action: String
    let promptId: String?
}

class VisionObserverEngine {
    private var isScanning = false
    private var lastFrameHash: String = ""
    private var activePrompt: VisionPromptPayload?
    private var activePromptId: String = ""
    private var isApprovedRecently = false

    func start() {
        FileHandle.standardOutput.write("{\"type\":\"vision_ready\"}\n".data(using: .utf8)!)

        // Background thread for reading remote mobile commands from stdin
        DispatchQueue.global(qos: .userInitiated).async {
            self.readStdinLoop()
        }

        // Timer to capture and OCR screen frame every 600ms
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            Task {
                await self.captureAndProcessScreen()
            }
        }

        RunLoop.main.run()
    }

    private func captureAndProcessScreen() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 1920
            config.height = 1080
            config.showsCursor = false
            
            let displayImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            self.processImageWithVision(displayImage)
        } catch {
            // Fallback or screen permission not yet granted
        }
    }

    private func processImageWithVision(_ displayImage: CGImage) {
        let requestHandler = VNImageRequestHandler(cgImage: displayImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] (req, error) in
            guard let self = self, error == nil,
                  let observations = req.results as? [VNRecognizedTextObservation] else {
                return
            }

            let recognizedLines = observations.compactMap { $0.topCandidates(1).first?.string }
            self.analyzeScreenText(lines: recognizedLines)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "zh-Hans"]

        try? requestHandler.perform([request])
    }

    private func analyzeScreenText(lines: [String]) {
        let fullScreenText = lines.joined(separator: "\n")
        let lower = fullScreenText.lowercased()

        // 1. Check for standard confirmation prompt markers
        let hasPrompt = isPromptPresent(lowerText: lower)
        if !hasPrompt {
            if activePrompt != nil && isApprovedRecently {
                // Prompt cleared on screen
                activePrompt = nil
                isApprovedRecently = false
                lastFrameHash = ""
                FileHandle.standardOutput.write("{\"type\":\"prompt_cleared\"}\n".data(using: .utf8)!)
            }
            return
        }

        // Avoid re-processing if screen text hasn't changed
        let frameHash = String(fullScreenText.prefix(200).hashValue)
        if frameHash == lastFrameHash {
            return
        }
        lastFrameHash = frameHash

        // 2. Identify Agent Name
        let agentName = detectAgentName(lines: lines, lower: lower)

        // 3. Extract Command and Risk Level
        let (extractedCmd, promptType) = extractCommandAndType(lines: lines, lower: lower)
        let risk = evaluateRisk(command: extractedCmd)

        // 4. Generate Option List
        var options: [String] = []
        var optionsList: [VisionOptionItem] = []

        if promptType == .yOrN {
            options = ["approve", "reject"]
            optionsList = [
                VisionOptionItem(key: "approve", label: "Yes, Allow (y)", isPrimary: true, isDestructive: false),
                VisionOptionItem(key: "reject", label: "No, Reject (n)", isPrimary: false, isDestructive: true)
            ]
        } else if promptType == .numberedMenu {
            options = ["1", "2", "5"]
            optionsList = [
                VisionOptionItem(key: "1", label: "1. Yes, allow this time", isPrimary: true, isDestructive: false),
                VisionOptionItem(key: "2", label: "2. Yes, always allow in session", isPrimary: false, isDestructive: false),
                VisionOptionItem(key: "5", label: "5. No (Deny)", isPrimary: false, isDestructive: true)
            ]
        } else {
            options = ["approve", "reject"]
            optionsList = [
                VisionOptionItem(key: "approve", label: "Confirm (Enter)", isPrimary: true, isDestructive: false),
                VisionOptionItem(key: "reject", label: "Cancel", isPrimary: false, isDestructive: true)
            ]
        }

        activePromptId = "vis_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))"

        let payload = VisionPromptPayload(
            type: "vision_prompt_detected",
            id: activePromptId,
            agent: agentName,
            title: "\(agentName) Permission Required",
            command: extractedCmd,
            description: "Confirmation detected on screen",
            risk: risk,
            promptType: promptType,
            options: options,
            optionsList: optionsList
        )

        activePrompt = payload

        if let jsonData = try? JSONEncoder().encode(payload),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            FileHandle.standardOutput.write("\(jsonStr)\n".data(using: .utf8)!)
        }
    }

    private func isPromptPresent(lowerText: String) -> Bool {
        let markers = [
            "allow execution",
            "confirm the command",
            "wants to execute",
            "permission required",
            "allow this time",
            "confirm dangerous",
            "(y/n)",
            "(y/n/always)",
            "[y/n]",
            "1. yes",
            "1 yes, allow",
            "是否允许",
            "确认执行"
        ]

        return markers.contains { lowerText.contains($0) }
    }

    private func detectAgentName(lines: [String], lower: String) -> String {
        if lower.contains("antigravity") {
            return "Antigravity IDE"
        }
        if lower.contains("codex") {
            return "Codex CLI"
        }
        if lower.contains("claude") {
            return "Claude Code"
        }
        if lower.contains("aider") {
            return "Aider"
        }
        if lower.contains("cursor") {
            return "Cursor AI"
        }
        return "AI Agent"
    }

    private func extractCommandAndType(lines: [String], lower: String) -> (String, PromptInteractionType) {
        var command = "Tool Execution"
        var promptType = PromptInteractionType.yOrN

        if lower.contains("(y/n") || lower.contains("[y/n") || lower.contains("allow execution") {
            promptType = .yOrN
        } else if lower.contains("1. yes") || lower.contains("1 yes, allow") || lower.contains("select choice") || lower.contains("[1-5]") {
            promptType = .numberedMenu
        } else {
            promptType = .enterDefault
        }

        // Find probable command line
        for line in lines {
            let trim = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trim.hasPrefix("npm ") || trim.hasPrefix("git ") || trim.hasPrefix("node ") ||
               trim.hasPrefix("python") || trim.hasPrefix("rm ") || trim.hasPrefix("npx ") ||
               trim.hasPrefix("chmod ") || trim.hasPrefix("docker ") || trim.hasPrefix("bash ") ||
               trim.hasPrefix("sh ") {
                command = trim
                break
            }
        }

        if command == "Tool Execution" {
            for line in lines {
                if line.contains("Confirm the command") || line.contains("wants to execute") {
                    command = line
                    break
                }
            }
        }

        return (command, promptType)
    }

    private func evaluateRisk(command: String) -> String {
        let lower = command.lowercased()
        if lower.contains("rm ") || lower.contains("force") || lower.contains("chmod ") ||
           lower.contains("drop") || lower.contains("delete") || lower.contains("sudo") {
            return "high"
        }
        if lower.contains("npx ") || lower.contains("build") || lower.contains("curl") {
            return "medium"
        }
        return "low"
    }

    private func readStdinLoop() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let cmd = try? JSONDecoder().decode(VisionCommandInput.self, from: data) else {
                continue
            }

            self.dispatchKeystrokeForAction(action: cmd.action)
        }
    }

    private func dispatchKeystrokeForAction(action: String) {
        guard let prompt = activePrompt else {
            // Default fallback keystroke
            sendKeystrokeString("y\r")
            return
        }

        isApprovedRecently = true

        let isApprove = (action == "approve" || action == "1" || action == "yes")

        if prompt.promptType == .yOrN {
            let keyToSend = isApprove ? "y\r" : "n\r"
            sendKeystrokeString(keyToSend)
        } else if prompt.promptType == .numberedMenu {
            let keyToSend = isApprove ? "1\r" : "5\r"
            sendKeystrokeString(keyToSend)
        } else {
            let keyToSend = isApprove ? "\r" : "\u{1b}" // Escape on reject
            sendKeystrokeString(keyToSend)
        }

        FileHandle.standardOutput.write("{\"type\":\"keystroke_dispatched\",\"action\":\"\(action)\"}\n".data(using: .utf8)!)
    }

    private func sendKeystrokeString(_ str: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in str {
            if char == "\r" || char == "\n" {
                // Keycode 36 is Return / Enter
                postKeyCode(36, source: source)
            } else if char == "y" || char == "Y" {
                // Keycode 16 is 'Y'
                postKeyCode(16, source: source)
            } else if char == "n" || char == "N" {
                // Keycode 45 is 'N'
                postKeyCode(45, source: source)
            } else if char == "1" {
                // Keycode 18 is '1'
                postKeyCode(18, source: source)
            } else if char == "2" {
                // Keycode 19 is '2'
                postKeyCode(19, source: source)
            } else if char == "5" {
                // Keycode 23 is '5'
                postKeyCode(23, source: source)
            } else {
                // Post generic unicode char
                var utf16Chars = Array(String(char).utf16)
                if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                    eventDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
                    eventDown.post(tap: .cghidEventTap)
                }
                usleep(20000)
                if let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    eventUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
                    eventUp.post(tap: .cghidEventTap)
                }
                usleep(20000)
            }
        }
    }

    private func postKeyCode(_ keyCode: CGKeyCode, source: CGEventSource?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        usleep(30000)
        up.post(tap: .cghidEventTap)
        usleep(30000)
    }
}

let engine = VisionObserverEngine()
engine.start()
