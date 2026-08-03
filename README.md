# approve-claw `[WIP]`

> **[WIP] Work In Progress**
> 
> *This project is currently under active development and refinement.*

---

## 📌 Overview

**approve-claw** is a remote security approval and real-time notification system designed for macOS AI Agents (such as Antigravity IDE, Claude Code, Codex, etc.). Operating via a local WebSocket daemon, it bridges Mac agent tool sandbox permission requests directly to your **iPhone** and **Apple Watch**, allowing you to review, approve, or reject dynamic multi-choice permissions straight from your wrist or mobile device.

---

## ⚠️ Current Development Status & Known Issues

> [!WARNING]
> **Known Issues & Bugs**:
> - 🟢 **Desktop Simulation & Local Testing**: Fully verified and passing in desktop simulation environments, CLI unit tests (`npm test`), and local WebSocket protocol tests.
> - 🔴 **Real-World Task Execution**: Under complex real-world execution scenarios (such as Antigravity IDE multi-file edits, rapid sequential syntax checks, and multi-conversation state switches), synchronization latency or prompt delivery edge cases may occur, preventing consistent real-time confirmations. Further debugging, optimization, and state machine refactoring are required.

---

## 🏗️ System Architecture

1. **Mac Agent (Node.js Daemon)**
   - Monitors system background transcripts and active WebSocket connections.
   - Dynamically parses AI Agent permission requests and extracts single-line option choices (`optionsList`).
   - Uses macOS AppleScript (`System Events`) to physically forward mobile decisions (e.g., `1. Yes, allow this time`) back to the target IDE window.

2. **iOS & watchOS App (SwiftUI & WatchConnectivity)**
   - **iPhone App**: Built with native SwiftUI, offering `UNUserNotificationCenter` quick actions, Dynamic UI cards, and real-time status sync.
   - **Apple Watch Companion**: Independent watchOS application featuring clean single-line option row buttons, compact layouts, and haptic vibration alerts.

---

## 🔧 Build & Setup

### 1. Mac Agent Setup
```bash
cd mac-agent
npm install
node src/index.js daemon
```

### 2. iOS & watchOS Xcode Build
```bash
# Generate Xcode project configuration
xcodegen generate

# Build iOS Application
xcodebuild -project WatchApprove.xcodeproj -target WatchApprove -destination 'generic/platform=iOS' build

# Build watchOS Application
xcodebuild -project WatchApprove.xcodeproj -target WatchApproveWatch -destination 'generic/platform=watchOS' build
```

---

## 📄 License

MIT License
