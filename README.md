<div align="center">

# 🐾 approve-claw `[WIP]`

**Real-Time Remote Permission Approval Bridge for macOS AI Coding Agents**

[![Status](https://img.shields.io/badge/status-work--in--progress-orange.svg)](https://github.com/tian0t/approve-claw)
[![Version](https://img.shields.io/badge/version-1.0.0--wip-blue.svg)](https://github.com/tian0t/approve-claw)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20watchOS-lightgrey.svg)](https://github.com/tian0t/approve-claw)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-FA7343.svg)](https://developer.apple.com/swift/)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18.0.0-339933.svg)](https://nodejs.org/)

*When your AI agent asks for permission, approve it from your wrist.*

> **Supported agents**: Antigravity IDE ✅ &nbsp;|&nbsp; Claude Code CLI 🚧 planned &nbsp;|&nbsp; Codex CLI 🚧 planned

[Overview](#-overview) • [Features](#-key-features) • [Architecture](#-system-architecture) • [Installation](#-installation) • [Status](#-status--roadmap)

</div>

---

## 📌 Overview

**approve-claw** is a real-time, cross-device permission approval bridge for autonomous macOS AI coding agents.

When these agents request to execute shell commands or access files outside their sandboxes, a permission dialog appears on your Mac — requiring you to be at your desk. `approve-claw` mirrors these dialogs directly to your **iPhone** and **Apple Watch**, letting you review the request and tap one of the exact permission choices (`1. Yes, allow this time`, `2. Always allow in conversation`, etc.) without touching your Mac.

| Agent | Status |
|-------|--------|
| Antigravity IDE | ✅ Supported |
| Claude Code CLI | 🚧 Planned |
| Codex CLI | 🚧 Planned |

---

## ✨ Key Features

### ⌚ Native Apple Watch App
- Independent watchOS 10+ app with a compact, single-line option layout purpose-built for small screens.
- Haptic alerts fire on arrival of new permission requests.

### 📱 iPhone App & Notifications
- Real-time permission cards showing command details, target file paths, and risk level.
- Lock-screen push notifications via `UNUserNotificationCenter` with quick `✅ Approve` / `❌ Reject` actions.

### 🤖 Antigravity IDE Brain Watcher ✅
- Monitors agent transcript logs under `~/.gemini/antigravity/brain/` in real time (polling every 400ms).
- Automatically prioritizes the most recently active project conversation (`mtimeMs` sorting).
- Filters out internal daemon activity to prevent noise on your devices.

### 🔀 Dynamic Option Mirroring
- Parses and mirrors the exact choice list shown on your Mac (e.g. all 5 options from an Antigravity IDE permission prompt) — not just a binary approve/reject.

### ⌨️ Keypress Injection
- Forwards your mobile decision back to the active IDE window via macOS `System Events` (`keystroke` + `Return`), closing the loop without any manual input on Mac.

---

## 🏗️ System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                           macOS Host                             │
│                                                                  │
│  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────┐  │
│  │ Antigravity IDE │  │ Claude Code CLI  │  │   Codex CLI    │  │
│  │   ✅ Supported  │  │   🚧 Planned     │  │  🚧 Planned    │  │
│  └────────┬────────┘  └────────┬─────────┘  └───────┬────────┘  │
│           │ Brain Transcripts  │ PTY Output          │ PTY       │
│           └──────────────────┬─┴─────────────────────┘           │
│                              ▼                                    │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                 approve-claw Mac Agent                  │    │
│   │  - Antigravity IDE Brain Transcript Watcher             │    │
│   │  - PTY Prompt Detector (Claude Code / Codex) [planned]  │    │
│   │  - WebSocket Server (LAN, Port 8080)                    │    │
│   │  - AppleScript Keypress Injection (System Events)       │    │
│   └─────────────────────────────┬───────────────────────────┘    │
└─────────────────────────────────┼────────────────────────────────┘
                                  │  Local WebSocket (ws://)
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Apple Mobile Devices                        │
│                                                                  │
│   ┌───────────────────┐    WatchConnectivity    ┌─────────────┐  │
│   │    iPhone App     │ ◄────────────────────► │ Apple Watch │  │
│   │  (iOS 17+ SwiftUI)│                         │ (watchOS 10+│  │
│   └───────────────────┘                         └─────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 📂 Repository Structure

```
approve-claw/
├── mac-agent/
│   ├── src/
│   │   ├── index.js                   # CLI entrypoint & daemon supervisor
│   │   ├── antigravity_ide_bridge.js  # Brain log watcher & active project filter
│   │   ├── detector.js                # Prompt regex parser & option extractor
│   │   └── websocket.js               # WebSocket server & device session manager
│   ├── test/                          # Unit test suites
│   └── package.json
├── ios/
│   ├── Shared/
│   │   ├── Models.swift               # Shared data models (ApprovalRequest, Option)
│   │   └── NotificationManager.swift  # Push notifications & quick actions
│   ├── WatchApprove/                  # iPhone app target
│   └── WatchApproveWatch/             # Apple Watch app target
├── project.yml                        # XcodeGen project configuration
└── README.md
```

---

## ⚠️ Status & Roadmap

> [!WARNING]
> **This project is a Work In Progress (WIP).**
>
> - 🟢 **Working**: Unit tests pass (`npm test`), Xcode builds succeed (`** BUILD SUCCEEDED **`), and the system works end-to-end in controlled test scenarios.
> - 🔴 **Known issues**: Under real-world workloads — particularly rapid sequential permission prompts, multi-file edits, or frequent project switching in Antigravity IDE — prompt delivery may be delayed or missed. State machine improvements are ongoing.

### Roadmap

**Core (Antigravity IDE)**
- [x] Multi-project conversation prioritization
- [x] Apple Watch native single-line dynamic option layout
- [x] Push notifications with Quick Actions
- [ ] Replace AppleScript `System Events` with Accessibility API `[planned]`
- [ ] Remote APNs push over cellular (no LAN required) `[planned]`
- [ ] Concurrent multi-agent request queue `[planned]`

**Agent Support**
- [x] Antigravity IDE
- [ ] Claude Code CLI `[planned]`
- [ ] Codex CLI `[planned]`

---

## 🚀 Installation

### Prerequisites

| Requirement | Version |
|-------------|---------|
| macOS | 13.0 (Ventura)+ |
| Node.js | 18.0+ |
| Xcode | 15.0+ |
| xcodegen | latest (`brew install xcodegen`) |
| iPhone | iOS 17.0+ |
| Apple Watch | watchOS 10.0+ |

> [!IMPORTANT]
> Enable **Accessibility** permissions for `System Events` under **System Settings → Privacy & Security → Accessibility** to allow keypress injection.

### 1. Start the Mac Agent

```bash
cd mac-agent
npm install
node src/index.js daemon
```

### 2. Build & Deploy the iOS App

```bash
xcodegen generate
```

Then open `WatchApprove.xcodeproj` in Xcode and press **`⌘ + R`** to build and run on your paired iPhone and Apple Watch.

---

## 🔒 Security & Privacy

- **Local-network only**: All communication happens over LAN/Wi-Fi. No data is ever sent to external servers.
- **PIN-based pairing**: Device pairing is protected by a 6-digit PIN handshake with persistent session tokens.

---

## 📄 License

MIT License © 2026 [tian0t](https://github.com/tian0t)
