<div align="center">

> **Project Status: Work In Progress (WIP)**
>
> A remote mobile approval companion for macOS desktop AI agents. Active ongoing development and continuous iteration. Fixing edge cases and polishing stability bit by bit.

# approve-claw v2.0 `[Universal Vision Engine]`

**Desktop App Screen Vision Remote Permission Approval Bridge for macOS AI Agents**

[![Status](https://img.shields.io/badge/status-v2.0--desktop--vision-brightgreen.svg)](https://github.com/tian0t/approve-claw)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/tian0t/approve-claw)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20watchOS-lightgrey.svg)](https://github.com/tian0t/approve-claw)
[![Apple Vision OCR](https://img.shields.io/badge/Engine-Apple%20Vision%20OCR-purple.svg)](https://developer.apple.com/documentation/vision)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18.0.0-339933.svg)](https://nodejs.org/)

*When your desktop AI agent requests execution permission on screen, review and approve it directly from your iPhone or Apple Watch.*

> **Supported Desktop App Agents**: Antigravity IDE &nbsp;|&nbsp; OpenAI Codex &nbsp;|&nbsp; Claude Code

[Overview](#overview) • [Workflow](#complete-11-closed-loop-workflow) • [Supported Agents](#supported-desktop-app-agents) • [Architecture](#system-architecture) • [Installation](#installation)

</div>

---

## Overview

**approve-claw v2.0** is an offline, hardware-accelerated remote permission approval system designed specifically for macOS desktop AI coding agents. 

Powered by **Apple ScreenCaptureKit** and the **Apple Vision OCR Engine (`vision_observer.swift`)**, `approve-claw` dynamically monitors your Mac screen for agent confirmation dialogs, extracts all selectable options and button coordinates in real time, mirrors them 1:1 onto your **iPhone** and **Apple Watch**, and synchronizes your mobile decision back to the Mac to execute via simulated mouse clicks or keystrokes.

---

## Complete 1:1 Closed-Loop Workflow

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  1. Prompt Appears on Mac Screen                                                      │
│     Antigravity / Codex / Claude Code desktop app displays an action approval dialog.  │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  2. Millisecond Screen Capture & Apple Vision OCR                                      │
│     Scans screen -> Extracts agent type, command, option labels, and pixel coordinates.│
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  3. Local WebSocket Broadcast -> iPhone & Apple Watch Sync                             │
│     - iPhone displays interactive approval card & lock-screen push notification.       │
│     - Apple Watch triggers haptic alert and displays 1:1 mirrored option buttons.      │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  4. User Selects an Option on iPhone or Apple Watch                                    │
│     E.g., tap "Proceed & Allow Execution", "Approve", or "1. Yes, allow once".        │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  5. Decision Transmitted Back to Mac for Closed-Loop Execution                         │
│     (1) NSWorkspace activates target desktop app window to gain system focus.          │
│     (2) Execution:                                                                     │
│         - Simulated Mouse: CGEvent clicks exact button coordinates on screen.          │
│         - Keystroke Injection: Dispatches numeric key / Return into active window.     │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Supported Desktop App Agents

All supported agents are macOS desktop applications:

| Desktop App Agent | Screen Recognition Context | Mobile / Watch Option Mapping | Mac Closed-Loop Execution |
| :--- | :--- | :--- | :--- |
| **Antigravity IDE** | Implementation plan / execution modals (`Proceed`, `Allow`, `Planning Mode`, `Execute`) | `Proceed & Allow`<br>`Cancel & Deny` | Focuses Antigravity window -> Clicks button coordinates (Enter/Esc fallback) |
| **OpenAI Codex** | Web & Desktop approval cards (`Approve`, `Reject`, `Ask for approval`) | `Approve`<br>`Reject` | Focuses Codex window -> Clicks `Approve`/`Reject` coordinates |
| **Claude Code** | Interactive selection menus (`1. Yes, allow once`, `2. Yes, allow...`, `3. No`) | `1. Yes, allow once`<br>`2. Yes, allow for this session`<br>`3. No` | Focuses Claude window -> Clicks option / Injects numeric key + Return |

---

## Key Features

### Native Apple Watch App (watchOS 10+)
- Independent watchOS application built with SwiftUI liquid glass aesthetics.
- Real-time synchronization with iPhone via `WatchConnectivity`.
- Single-line fluid option buttons designed for fast wrist taps and haptic notifications.

### iPhone App & Lock Screen Notifications
- Live status card showing Agent name, command code block, risk indicator, and all dynamic option buttons.
- `UNUserNotificationCenter` push notifications with quick interactive actions.
- Full activity history log with exact option labels (e.g. `1. Yes, allow once`, `Approved`, `Proceed & Allow`).

### Native Swift Vision OCR Engine
- Built with `ScreenCaptureKit` + Apple `Vision` framework (`VNRecognizeTextRequest`).
- Pure native Swift implementation (`bin/vision_observer`) without third-party OCR dependencies.
- Hardware-accelerated local scanning with smart cooldown and deduplication.

### Intelligent GUI Click & Keystroke Dispatcher
- Window focus management via `NSWorkspace` for instant app switching.
- Precise `CGEvent` mouse cursor clicking based on OCR bounding boxes.
- Full Retina / HiDPI logical coordinate calibration.

---

## System Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                     macOS Host                                        │
│                                                                                       │
│   ┌────────────────────────┐  ┌────────────────────────┐  ┌───────────────────────┐   │
│   │   Antigravity IDE App  │  │    OpenAI Codex App    │  │    Claude Code App    │   │
│   └───────────┬────────────┘  └───────────┬────────────┘  └───────────┬───────────┘   │
│               │                           │                           │               │
│               └───────────────────────────┼───────────────────────────┘               │
│                                           │ ScreenCaptureKit Frame Stream             │
│                                           ▼                                           │
│   ┌───────────────────────────────────────────────────────────────────────────────┐   │
│   │              vision_observer (Native Swift Binary Engine)                     │   │
│   │  - VNRecognizeTextRequest (Hardware Accelerated OCR)                          │   │
│   │  - Strict App Filter: Antigravity / OpenAI Codex / Claude Code                │   │
│   │  - 1:1 Dynamic Option & Bounding Box Coordinate Extractor                     │   │
│   │  - NSWorkspace Window Focusing + CGEvent Mouse Click / Keystroke Dispatcher   │   │
│   └───────────────────────────────────────┬───────────────────────────────────────┘   │
│                                           │ stdin / stdout JSON Stream                │
│                                           ▼                                           │
│   ┌───────────────────────────────────────────────────────────────────────────────┐   │
│   │                       approve-claw Node.js Daemon                             │   │
│   │  - vision_bridge.js (Subprocess Supervisor & Event Deduplication)             │   │
│   │  - request_lifecycle.js (State Machine, Per-Agent Queue, Timeout Manager)    │   │
│   │  - websocket.js (Local Encrypted WebSocket Gateway, Port 8080)                │   │
│   └───────────────────────────────────────┬───────────────────────────────────────┘   │
└───────────────────────────────────────────┼───────────────────────────────────────────┘
                                            │ Local Wi-Fi WebSocket (ws://)
                                            ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                 Apple Mobile Devices                                  │
│                                                                                       │
│   ┌──────────────────────────────────────┐     WatchConnectivity   ┌──────────────┐   │
│   │              iPhone App              │ <---------------------> │ Apple Watch  │   │
│   │  - Dynamic Single-Line Option List   │                         │ - Wrist Tap  │   │
│   │  - Lock-Screen Action Notifications  │                         │ - Haptics    │   │
│   │  - Real-time Activity History Log    │                         │ - 1:1 Sync   │   │
│   └──────────────────────────────────────┘                         └──────────────┘   │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
approve-claw/
├── mac-agent/
│   ├── src/
│   │   ├── index.js               # CLI daemon entrypoint & supervisor
│   │   ├── vision_observer.swift  # Native Apple Vision OCR & coordinate dispatcher
│   │   ├── vision_bridge.js       # Bridge linking Swift OCR process to WebSocket
│   │   ├── websocket.js           # WebSocket server & client session manager
│   │   ├── request_lifecycle.js   # Request state serialization & timeout manager
│   │   └── crypto.js              # PIN handshake & token authentication
│   ├── bin/
│   │   └── vision_observer        # Compiled native Swift binary
│   └── package.json
├── ios/
│   ├── Shared/
│   │   ├── Models.swift           # Shared data models (ApprovalRequest, DynamicOption)
│   │   └── NotificationManager.swift # Push notifications & interactive actions
│   ├── WatchApprove/              # iPhone SwiftUI application
│   └── WatchApproveWatch/         # Apple Watch watchOS application
├── project.yml                    # XcodeGen project configuration
└── README.md
```

---

## Installation & Getting Started

### Prerequisites

| Requirement | Supported Version |
| :--- | :--- |
| **macOS** | macOS 13.0 (Ventura) or newer |
| **Node.js** | Node.js 18.0+ |
| **Xcode** | Xcode 15.0+ |
| **XcodeGen** | `brew install xcodegen` |
| **iOS / watchOS** | iOS 17.0+ / watchOS 10.0+ |

> [!IMPORTANT]
> **macOS Permissions Setup**:
> 1. **Screen Recording**: Allow your Terminal / app running `approve-claw` in **System Settings -> Privacy & Security -> Screen Recording**.
> 2. **Accessibility**: Allow in **System Settings -> Privacy & Security -> Accessibility** to permit `CGEvent` mouse clicks and keystrokes.

---

### Step 1: Start the Mac Bridge Daemon

```bash
# 1. Clone repository
git clone https://github.com/tian0t/approve-claw.git
cd approve-claw/mac-agent

# 2. Install dependencies & compile Swift Vision engine
npm install
npm run build:vision

# 3. Launch daemon
npm start
```

When started, the terminal will display the LAN IP address and a 6-digit pairing PIN code.

---

### Step 2: Build & Install the iOS / Apple Watch App

```bash
cd ../ios
xcodegen generate
```

1. Open `WatchApprove.xcodeproj` in Xcode.
2. Select your iPhone as the build target and press `Cmd + R` to run.
3. In the iPhone app, input your Mac's LAN IP address and 6-digit PIN code to complete pairing.
4. Your paired Apple Watch will automatically sync and be ready to receive live approval requests!

---

## Security & Privacy

- **100% Offline & Local**: All OCR processing runs locally via Apple Neural Engine / Vision framework. All WebSocket communication remains strictly within your local Wi-Fi network.
- **PIN-Protected Handshake**: Pairing requires a 6-digit one-time code generating persistent cryptographic session tokens.
- **No Cloud Dependencies**: Zero external API keys or cloud relay required.

---

## License

MIT License (c) 2026 [tian0t](https://github.com/tian0t)
