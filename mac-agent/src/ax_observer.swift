import Foundation
import AppKit
import ApplicationServices

struct AXButtonInfo: Codable {
    let index: Int
    let label: String
    let isPrimary: Bool
    let isDestructive: Bool
}

struct AXPromptPayload: Codable {
    let type: String
    let id: String
    let appName: String
    let windowTitle: String
    let description: String
    let command: String
    let risk: String
    let buttons: [AXButtonInfo]
}

struct AXCommandInput: Codable {
    let action: String
    let promptId: String?
    let buttonIndex: Int?
    let label: String?
}

class AXObserverEngine {
    private var lastPromptHash: String = ""
    private var buttonElementMap: [Int: AXUIElement] = [:]
    private var currentPromptId: String = ""

    func startLoop() {
        // Output JSON lines to stdout
        FileHandle.standardOutput.write("{\"type\":\"ax_ready\"}\n".data(using: .utf8)!)

        // Thread for reading stdin commands
        DispatchQueue.global(qos: .userInitiated).async {
            self.readStdinLoop()
        }

        // Timer for polling frontmost window UI accessibility tree (250ms interval)
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            self.scanFrontmostWindow()
        }

        RunLoop.main.run()
    }

    private func scanFrontmostWindow() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = activeApp.processIdentifier
        let appName = activeApp.localizedName ?? "AI Agent App"

        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowObj: CFTypeRef?
        let windowRes = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowObj)

        guard windowRes == .success, let window = focusedWindowObj else {
            var windowsObj: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsObj) == .success,
               let windows = windowsObj as? [AXUIElement], let firstWin = windows.first {
                inspectWindow(firstWin, appName: appName)
            }
            return
        }

        inspectWindow(window as! AXUIElement, appName: appName)
    }

    private func inspectWindow(_ window: AXUIElement, appName: String) {
        var windowTitleObj: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &windowTitleObj)
        let windowTitle = (windowTitleObj as? String) ?? appName

        var textCollected: [String] = []
        var buttonsFound: [(element: AXUIElement, label: String)] = []

        traverseUIElement(window, textCollected: &textCollected, buttonsFound: &buttonsFound, depth: 0)

        let fullText = textCollected.joined(separator: "\n")
        
        // Detect confirmation prompt keywords
        let isPrompt = isConfirmationPrompt(fullText: fullText, buttons: buttonsFound.map { $0.label })
        if !isPrompt {
            return
        }

        let promptHash = "\(appName):\(windowTitle):\(buttonsFound.map { $0.label }.joined(separator: "|")):\(fullText.prefix(100))"
        if promptHash == lastPromptHash {
            return
        }

        lastPromptHash = promptHash
        currentPromptId = "ax_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999))"
        buttonElementMap.removeAll()

        var buttonInfos: [AXButtonInfo] = []
        for (idx, b) in buttonsFound.enumerated() {
            let keyIndex = idx + 1
            buttonElementMap[keyIndex] = b.element
            let isDestructive = b.label.lowercased().contains("no") || b.label.lowercased().contains("deny") || b.label.lowercased().contains("cancel") || b.label.contains("拒绝") || b.label.contains("5")
            let isPrimary = keyIndex == 1 || b.label.lowercased().contains("yes") || b.label.lowercased().contains("allow") || b.label.contains("允许")
            
            buttonInfos.append(AXButtonInfo(
                index: keyIndex,
                label: "\(keyIndex). \(b.label)",
                isPrimary: isPrimary,
                isDestructive: isDestructive
            ))
        }

        if buttonInfos.isEmpty {
            buttonInfos = [
                AXButtonInfo(index: 1, label: "1. Yes, Allow", isPrimary: true, isDestructive: false),
                AXButtonInfo(index: 2, label: "2. No, Deny", isPrimary: false, isDestructive: true)
            ]
        }

        let (extractedCmd, extractedDesc) = parseCommandAndDescription(textCollected: textCollected, appName: appName)

        let payload = AXPromptPayload(
            type: "ax_prompt_detected",
            id: currentPromptId,
            appName: appName,
            windowTitle: windowTitle,
            description: extractedDesc,
            command: extractedCmd,
            risk: assessRisk(extractedCmd),
            buttons: buttonInfos
        )

        if let jsonData = try? JSONEncoder().encode(payload),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            FileHandle.standardOutput.write("\(jsonStr)\n".data(using: .utf8)!)
        }
    }

    private func traverseUIElement(_ element: AXUIElement, textCollected: inout [String], buttonsFound: inout [(element: AXUIElement, label: String)], depth: Int) {
        if depth > 15 { return }

        var roleObj: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleObj)
        let role = (roleObj as? String) ?? ""

        var titleObj: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleObj)
        let title = (titleObj as? String) ?? ""

        var valueObj: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueObj)
        let value = (valueObj as? String) ?? ""

        var descObj: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descObj)
        let desc = (descObj as? String) ?? ""

        if role == kAXButtonRole as String || role == "AXButton" {
            let label = !title.isEmpty ? title : (!desc.isEmpty ? desc : (!value.isEmpty ? value : "Button"))
            if !label.isEmpty && label.count < 60 {
                buttonsFound.append((element: element, label: label))
            }
        } else {
            let text = !title.isEmpty ? title : (!value.isEmpty ? value : desc)
            if !text.isEmpty && text.count > 2 && text.count < 500 {
                textCollected.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        var childrenObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenObj) == .success,
           let children = childrenObj as? [AXUIElement] {
            for child in children {
                traverseUIElement(child, textCollected: &textCollected, buttonsFound: &buttonsFound, depth: depth + 1)
            }
        }
    }

    private func isConfirmationPrompt(fullText: String, buttons: [String]) -> Bool {
        let text = fullText.lowercased()
        let promptKeywords = ["allow", "confirm", "approve", "execute", "wants to run", "permission required", "允许", "确认", "是否允许", "是否运行", "yes, allow"]
        
        let hasPromptKeyword = promptKeywords.contains { text.contains($0) }
        let hasButtonKeyword = buttons.contains { b in
            let lower = b.lowercased()
            return lower.contains("allow") || lower.contains("yes") || lower.contains("ok") || lower.contains("confirm") || lower.contains("允许") || lower.contains("确认")
        }

        return hasPromptKeyword || hasButtonKeyword
    }

    private func parseCommandAndDescription(textCollected: [String], appName: String) -> (command: String, description: String) {
        var command = "Tool Execution"
        var description = "\(appName) Security Confirmation"

        for line in textCollected {
            if line.contains("wants to run") || line.contains("Confirm the command") || line.contains("Allow") || line.contains("允许") {
                description = line
            }
            if line.hasPrefix("npm ") || line.hasPrefix("git ") || line.hasPrefix("node ") || line.hasPrefix("python") || line.hasPrefix("rm ") || line.hasPrefix("sudo ") || line.hasPrefix("chmod ") {
                command = line
            }
        }

        if command == "Tool Execution" && !textCollected.isEmpty {
            command = textCollected.last ?? "Unknown Command"
        }

        return (command, description)
    }

    private func assessRisk(_ cmd: String) -> String {
        let lower = cmd.lowercased()
        if lower.contains("rm ") || lower.contains("sudo ") || lower.contains("force") || lower.contains("chmod ") || lower.contains("delete") {
            return "high"
        }
        if lower.contains("npm ") || lower.contains("git status") || lower.contains("python") || lower.contains("node ") {
            return "low"
        }
        return "medium"
    }

    private func readStdinLoop() {
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let cmd = try? JSONDecoder().decode(AXCommandInput.self, from: data) else {
                continue
            }

            if cmd.action == "press", let idx = cmd.buttonIndex, let targetButton = buttonElementMap[idx] {
                let res = AXUIElementPerformAction(targetButton, kAXPressAction as CFString)
                let statusStr = (res == .success) ? "success" : "failed"
                FileHandle.standardOutput.write("{\"type\":\"ax_action_result\",\"result\":\"\(statusStr)\",\"buttonIndex\":\(idx)}\n".data(using: .utf8)!)
            }
        }
    }
}

// Check Accessibility trusted status on launch
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(options)
if !trusted {
    FileHandle.standardOutput.write("{\"type\":\"ax_permission_required\",\"message\":\"Please grant Accessibility permissions in System Settings -> Privacy & Security -> Accessibility\"}\n".data(using: .utf8)!)
}

let engine = AXObserverEngine()
engine.startLoop()
