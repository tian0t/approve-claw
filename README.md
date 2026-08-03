<div align="center">

# 🐾 approve-claw `[WIP]`

**Enterprise-Grade Remote Security Approval System for macOS AI Coding Agents**

[![Status](https://img.shields.io/badge/status-work--in--progress-orange.svg)](https://github.com/tian0t/approve-claw)
[![Version](https://img.shields.io/badge/version-1.0.0--wip-blue.svg)](https://github.com/tian0t/approve-claw)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20watchOS-lightgrey.svg)](https://github.com/tian0t/approve-claw)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-FA7343.svg)](https://developer.apple.com/swift/)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18.0.0-339933.svg)](https://nodejs.org/)

*Bridge macOS Autonomous AI Agents (Antigravity IDE, Claude Code CLI, Codex) directly to your iPhone and Apple Watch.*

[Overview](#-overview) • [Features](#-key-features) • [Architecture](#-system-architecture--data-flow) • [Installation](#-installation--getting-started) • [Status & Roadmap](#-current-status--technical-roadmap)

</div>

---

## 📌 Overview

**approve-claw** is a real-time, cross-device security authorization bridge designed for autonomous macOS AI coding assistants. 

When modern AI agents attempt to execute terminal commands, run external scripts, or modify files outside their sandboxes, `approve-claw` intercepts these permission challenges in real time. Instead of locking you to your Mac display, `approve-claw` mirrors dynamic multi-choice permission cards to your **iPhone** and **Apple Watch**. Review contextual details and issue precise approvals (`1. Yes, allow this time`, `2. Always allow in conversation`, etc.) straight from your wrist or mobile device.

---

## ✨ Key Features

### ⌚ Native Apple Watch Companion (`watchOS`)
- **Independent SwiftUI Watch App**: Lightweight, native interface engineered specifically for watchOS 10+.
- **Optimized UI Components (`WatchOptionButtonRow`)**: Custom single-line action rows with explicit type inference to guarantee sub-millisecond compilation and rendering.
- **Haptic Feedback Alerts**: Distinct haptic vibration signatures triggered upon incoming high-priority permission prompts.

### 📱 iPhone Companion & Push Notifications (`iOS`)
- **Interactive UI Cards**: Real-time WebSocket card rendering displaying command titles, risk levels, and targeted file paths.
- **Lock-Screen Quick Actions**: Fully integrated with Apple's `UNUserNotificationCenter` for instant approval (`✅ Approve`) or denial (`❌ Reject`) from lock screen banners.

### 🤖 Intelligent Antigravity IDE Brain Watcher
- **Real-Time Log Parsing**: Continuously monitors agent transcript trajectories under `~/.gemini/antigravity/brain/`.
- **Active-Project Prioritization**: Dynamically ranks active projects by file modification timestamp (`mtimeMs`), ensuring zero-latency response for your currently active workspace.
- **Self-Meta Exclusion Filter**: Built-in whitelist filtering to prevent internal daemon configuration commands from leaking to mobile devices.

### ⌨️ Physical Keypress Injection Engine
- **AppleScript System Events Bridge**: Translates remote mobile decisions into physical keyboard signals (`1`-`5` + `Return`), delivering seamless automation back to the active target IDE window (`Google Antigravity`).

---

## 🏗️ System Architecture & Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              macOS Host                                 │
│                                                                         │
│   ┌────────────────────────┐             ┌──────────────────────────┐   │
│   │  Antigravity IDE       │             │  Claude Code / Codex CLI │   │
│   └───────────┬────────────┘             └────────────┬─────────────┘   │
│               │ Brain Transcripts (.jsonl)            │ PTY Output      │
│               ▼                                       ▼                 │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                 approve-claw Mac Agent Daemon                   │   │
│   │  - Log Transcript Watcher & Regex Prompt Detector               │   │
│   │  - Secure Local WebSocket Server (Port 8080)                    │   │
│   │  - macOS AppleScript Keypress Injection Engine                  │   │
│   └────────────────────────────────┬────────────────────────────────┘   │
└────────────────────────────────────┼────────────────────────────────────┘
                                     │ Local WebSocket (ws://)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Apple Mobile Ecosystem                          │
│                                                                         │
│   ┌────────────────────────┐   WatchConnectivity   ┌────────────────┐   │
│   │      iPhone App        │ ◄───────────────────► │   Apple Watch  │   │
│   │   (iOS 17+ SwiftUI)    │    (WCSession Sync)   │  (watchOS 10+) │   │
│   └────────────────────────┘                       └────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Repository Structure

```
approve-claw/
├── mac-agent/                        # macOS Daemon & Parser Engine
│   ├── src/
│   │   ├── index.js                  # CLI Entrypoint & Daemon Supervisor
│   │   ├── antigravity_ide_bridge.js # Brain transcript log watcher & filter
│   │   ├── detector.js               # RegExp prompt parser & option extractor
│   │   └── websocket.js              # WebSocket server & device session manager
│   ├── test/                         # Unit & integration test suites
│   └── package.json                  # Node.js package manifest (v1.0.0-wip)
├── ios/                              # Apple Native Codebase (SwiftUI)
│   ├── Shared/                       # Cross-Target Shared Utilities
│   │   ├── Models.swift              # Data structures (ApprovalRequest, Option)
│   │   └── NotificationManager.swift # Push notification & category actions
│   ├── WatchApprove/                 # iPhone iOS Target
│   │   ├── ContentView.swift         # Dynamic UI card stack
│   │   └── WebSocketManager.swift    # Client socket protocol implementation
│   └── WatchApproveWatch/            # Apple Watch watchOS Target
│       ├── ContentView.swift         # watchOS UI & WatchOptionButtonRow
│       └── WatchConnectivityManager.swift # WatchConnectivity sync engine
├── scripts/                          # Icon utilities & Swift build helpers
├── project.yml                       # XcodeGen project configuration
└── README.md                         # Project documentation
```

---

## ⚠️ Current Status & Technical Roadmap

> [!WARNING]
> **Development Status: Work In Progress (WIP)**
>
> - 🟢 **Desktop Simulation & Protocol Validation**: Fully verified and passing across CLI unit tests (`npm test`), PTY terminal wrappers, and Xcode watchOS target compilation (`** BUILD SUCCEEDED **`).
> - 🔴 **Real-World Execution Edge Cases**: In complex real-world multi-file scenarios (e.g., Antigravity IDE rapid sequential file edits, multi-file syntax checks, or rapid conversation switching), synchronization latency or prompt delivery edge cases may occur. Ongoing refactoring is focused on enhancing state-machine resilience.

### Technical Roadmap

- [x] Multi-project active conversation prioritization (`mtimeMs` sorting).
- [x] Apple Watch native single-line dynamic option button layout.
- [x] Lock-screen push notifications & Quick Actions.
- [ ] Dedicated macOS Accessibility API integration (replacing System Events fallback).
- [ ] APNs (Apple Push Notification service) remote cellular push support.
- [ ] Multi-agent concurrent request queue optimization.

---

## 🚀 Installation & Getting Started

### Prerequisites

- **macOS**: macOS 13.0 (Ventura) or later (Accessibility permissions required for System Events).
- **Node.js**: Node.js v18.0.0 or higher.
- **Xcode Tools**: Xcode 15.0+ and `xcodegen` (`brew install xcodegen`).
- **Apple Devices**: iPhone running iOS 17.0+ and Apple Watch running watchOS 10.0+.

### 1. Launch the Mac Agent Daemon

```bash
cd mac-agent
npm install

# Start the daemon in supervisor mode
node src/index.js daemon
```

### 2. Generate and Build Apple Native App

```bash
# Generate WatchApprove.xcodeproj via XcodeGen
xcodegen generate

# Validate watchOS target build
xcodebuild -project WatchApprove.xcodeproj \
  -target WatchApproveWatch \
  -destination 'generic/platform=watchOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Open `WatchApprove.xcodeproj` in Xcode and press **`⌘ + R`** to deploy to your paired iPhone and Apple Watch!

---

## 🔒 Security & Privacy

- **Local-First Architecture**: `approve-claw` operates entirely within your local network (LAN / Wi-Fi). No prompt data, code snippets, or system logs are ever transmitted to third-party cloud servers.
- **Token & PIN Verification**: Initial device pairing is secured via a 6-digit PIN handshake and persistent device tokens.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.

<div align="center">

*Created with ❤️ by [tian0t](https://github.com/tian0t)*

</div>
