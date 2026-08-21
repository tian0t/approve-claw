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

> **Supported Desktop App Agents**: Antigravity IDE &nbsp;|&nbsp; OpenAI Codex &nbsp;|&nbsp; Claude Code `[WIP]`

[Overview](#overview) • [Workflow](#complete-11-closed-loop-workflow) • [Supported Agents](#supported-desktop-app-agents) • [Architecture](#system-architecture) • [Installation](#installation)

</div>

---

## Overview

**approve-claw v2.0** is an offline, hardware-accelerated remote permission approval system designed specifically for macOS desktop AI coding agents. 

Powered by **macOS Accessibility (AXUIElement)**, **Apple ScreenCaptureKit**, and the **Apple Vision OCR Engine (`vision_observer.swift`)**, `approve-claw` monitors the native Codex/Antigravity desktop UI, mirrors approval requests to your **iPhone** and **Apple Watch**, and sends the decision back to the Mac. The Mac uses a live Accessibility button action first; if the app does not expose the button through Accessibility, it falls back to a Vision-captured screen coordinate click.

### Native Codex execution strategy

The normal Codex path is the native macOS ChatGPT/Codex application UI (`com.openai.chat` / `com.openai.codex`):

1. AXUIElement detects the approval card and maps its live buttons.
2. The approval request is synchronized to iPhone and Apple Watch.
3. A tap on `Approve` or `Reject` is sent back to the Mac.
4. The Mac tries `AXUIElementPerformAction` on the live button.
5. If AX cannot press the button, Vision OCR reuses the latest frontmost-window coordinates and posts a mouse click.
6. The mobile devices receive `confirmation_completed` after the Mac dispatcher reports that the desktop action was sent. The Codex card should still be visually checked during first-time setup.

Browser pages are not part of the normal workflow. The browser harness is opt-in and exists only for local OCR testing with `APPROVE_CLAW_ALLOW_BROWSER_CODEX_SIM=1`.

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
│  2. Native UI Detection                                                                  │
│     AXUIElement reads live buttons first; Vision OCR captures the frontmost window      │
│     and extracts option labels / coordinates when Accessibility cannot expose them.     │
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
│     (1) Prefer AXUIElementPerformAction on the live approval button.                   │
│     (2) Fallback: NSWorkspace focuses the target app and CGEvent clicks Vision coords.│
│     (3) The result is synchronized only after the desktop action succeeds.             │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Supported Desktop App Agents

All supported agents are macOS desktop applications:

| Desktop App Agent | Screen Recognition Context | Mobile / Watch Option Mapping | Mac Closed-Loop Execution |
| :--- | :--- | :--- | :--- |
| **Antigravity IDE** | Implementation plan / execution modals (`Proceed`, `Allow`, `Planning Mode`, `Execute`) | `Proceed & Allow`<br>`Cancel & Deny` | Focuses Antigravity window -> Clicks button coordinates (Enter/Esc fallback) |
| **OpenAI Codex** | Native ChatGPT/Codex desktop approval cards (`Approve`, `Reject`) | `Approve`<br>`Reject` | AXUIElement button press -> Vision coordinate click fallback |
| **Claude Code** `[WIP]` | Interactive selection menus (`1. Yes, allow once`, `2. Yes, allow...`, `3. No`) | `1. Yes, allow once`<br>`2. Yes, allow for this session`<br>`3. No` | Focuses Claude window -> Clicks option / Injects numeric key + Return |

> [!NOTE]
> **Primary focus**: OpenAI Codex (ChatGPT desktop app) and Antigravity IDE are the actively developed agents. **Claude Code support is WIP / experimental** and not the current development priority.

> **Codex desktop app only:** the normal workflow targets the native ChatGPT/Codex macOS application UI (`com.openai.chat` / `com.openai.codex`) and uses Vision-captured screen coordinates. Browser pages are not required. The local browser harness is optional and only enabled with `APPROVE_CLAW_ALLOW_BROWSER_CODEX_SIM=1` for OCR testing.

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

### Native macOS Accessibility Engine
- `ax_observer.swift` traverses the frontmost native app's Accessibility tree.
- Codex uses AX as the primary execution path instead of browser automation.
- A failed AX press is handed to the Vision bridge automatically.

> **Codex UI compatibility:** some Codex approval cards are rendered in a surface that does not expose `Approve` / `Reject` as AX buttons. In that case the runtime uses the latest Vision frame, then falls back to `Tab + Enter` when OCR cannot produce a reliable button coordinate. If the card remains visible, grant Accessibility and Screen Recording to the terminal that runs the daemon, restart it, and verify the focused Codex window before testing again.

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
│   │       ax_observer + vision_observer (Native Swift Engines)                    │   │
│   │  - AXUIElement live-button detection and semantic press (primary)              │   │
│   │  - VNRecognizeTextRequest (Hardware Accelerated OCR)                          │   │
│   │  - Strict native-app filter: Antigravity / OpenAI Codex / Claude Code          │   │
│   │  - 1:1 Dynamic Option & Bounding Box Coordinate Extractor                     │   │
│   │  - Vision coordinate click fallback + keystroke dispatcher                    │   │
│   └───────────────────────────────────────┬───────────────────────────────────────┘   │
│                                           │ stdin / stdout JSON Stream                │
│                                           ▼                                           │
│   ┌───────────────────────────────────────────────────────────────────────────────┐   │
│   │                       approve-claw Node.js Daemon                             │   │
│   │  - vision_bridge.js (Subprocess Supervisor & Event Deduplication)             │   │
│   │  - request_lifecycle.js (State Machine, Per-Agent Queue, Timeout Manager)    │   │
│   │  - websocket.js (Local Token-Authenticated WebSocket Gateway, Port 8080)     │   │
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
│   │   ├── ax_observer.swift      # Native AX tree observer & semantic button press
│   │   ├── ax_bridge.js           # AX bridge, completion tracking & Vision fallback
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
> 2. **Accessibility**: Allow your Terminal / app running `approve-claw` in **System Settings -> Privacy & Security -> Accessibility**. This enables AXUIElement button presses; it also permits the Vision fallback's `CGEvent` mouse click.

---

### Step 1: Start the Mac Bridge Daemon

```bash
# 1. Clone repository
git clone https://github.com/tian0t/approve-claw.git
cd approve-claw/mac-agent

# 2. Install dependencies
npm install

# 3. Launch daemon (automatically compiles Vision + Accessibility observers)
npm start
```

When started, the terminal will display the LAN IP address and a 6-digit pairing PIN code.
Keep this terminal running while using the iPhone or Apple Watch. The Mac and iPhone must be on the same Wi-Fi network.

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

> **Xcode build note:** select the `WatchApprove` scheme and a real iPhone (or the generic iOS device destination) before building. Do not use an iOS Simulator destination for the embedded watch target; Xcode will build the watch companion for watchOS automatically.

### First-run checklist

1. On the Mac, allow **Screen Recording** and **Accessibility** for the terminal app that runs `npm start`.
2. Start `npm start` and copy the displayed LAN IP and PIN.
3. Open WatchApprove on the iPhone, enter the IP/PIN, and wait for `Connected`.
4. Keep WatchApprove open or recently active during personal use; iOS may suspend local WebSocket connections when the app has been backgrounded for a long time.
5. Trigger a real approval prompt from the supported desktop agent and approve from the iPhone or Watch.

### Verification commands

```bash
cd mac-agent
npm run build:native
npm test
node test/e2e_realistic_sim.js
```

The end-to-end simulation verifies native Codex AX priority, Vision fallback routing, duplicate suppression, stale-request handling, and the mobile decision lifecycle. On a real Mac, confirm that the Codex card closes after the first approval because some app surfaces accept keyboard focus differently.

---

## Security & Privacy

- **100% Offline & Local**: All OCR processing runs locally via Apple Neural Engine / Vision framework. All WebSocket communication remains strictly within your local Wi-Fi network.
- **PIN-Protected Handshake**: Pairing requires a 6-digit one-time code and issues a persistent random access token stored with 0600 permissions.
- **No Cloud Dependencies**: Zero external API keys or cloud relay required.

---

## License

MIT License (c) 2026 [tian0t](https://github.com/tian0t)
