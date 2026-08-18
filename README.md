<div align="center">

> ⚠️ **Project Status**
>
> A mobile approval app for AI agents. Out of quota, full of unsolved issues, and totally exhausted. Fixing it bit by bit when energy permits. Ouch...

# 🐾 approve-claw v2.0 `[Universal Vision Engine]`

**Universal Screen Vision Remote Permission Approval Bridge for macOS AI Coding Agents**

[![Status](https://img.shields.io/badge/status-v2.0--universal--vision-brightgreen.svg)](https://github.com/tian0t/approve-claw)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/tian0t/approve-claw)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20watchOS-lightgrey.svg)](https://github.com/tian0t/approve-claw)
[![Apple Vision OCR](https://img.shields.io/badge/Engine-Apple%20Vision%20OCR-purple.svg)](https://developer.apple.com/documentation/vision)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18.0.0-339933.svg)](https://nodejs.org/)

*When your AI agent asks for permission on screen, approve it from your wrist.*

> **Universal Agent Support**: Antigravity IDE ✅ &nbsp;|&nbsp; Codex CLI ✅ &nbsp;|&nbsp; Claude Code ✅ &nbsp;|&nbsp; Aider / Cursor / Custom Agents ✅

[Overview](#-overview) • [Features](#-key-features) • [Architecture](#-system-architecture) • [Installation](#-installation)

</div>

---

## 📌 Overview

**approve-claw v2.0** completely refactors permission handling by introducing a **Universal Apple Vision OCR Screen Engine**. Instead of maintaining fragile regex parsers for each individual agent, approve-claw captures on-screen confirmation dialogs with hardware-accelerated offline Vision OCR, presents a unified approval card on your **iPhone** and **Apple Watch**, and dispatches the exact keystrokes (`y`, `1`, `Enter`, etc.) back to your Mac.

| Agent | Engine | Support Status |
|-------|--------|----------------|
| **Antigravity IDE** | Apple Vision OCR + Keystroke Dispatcher | ✅ Full Universal Support |
| **Codex CLI** | Apple Vision OCR + Keystroke Dispatcher | ✅ Full Universal Support |
| **Claude Code CLI** | Apple Vision OCR + Keystroke Dispatcher | ✅ Full Universal Support |
| **Aider / Cursor / Others** | Apple Vision OCR + Keystroke Dispatcher | ✅ Full Universal Support |

---

## ✨ Key Features

### ⌚ Native Apple Watch App
- Independent watchOS 10+ app with a compact, single-line option layout purpose-built for small screens.
- Haptic alerts fire on arrival of new permission requests.

### 📱 iPhone App & Notifications
- Real-time permission cards showing command details, target file paths, and risk level.
- Lock-screen push notifications via `UNUserNotificationCenter` with quick `✅ Approve` / `❌ Reject` actions.

### 🤖 Antigravity IDE Brain Watcher 🚧
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
│  ┌──────────────────┐  ┌─────────────────┐  ┌────────────────┐   │
│  │  Antigravity IDE │  │ Claude Code CLI │  │   Codex CLI    │   │
│  │  [WIP: partial]  │  │   [planned]     │  │   [planned]    │   │
│  └────────┬─────────┘  └───────┬─────────┘  └───────┬────────┘   │
│           │                    │                    │            │
│           │ Brain Transcripts  │ PTY Output    PTY  │            │
│           └────────────────────┴────────────────────┘            │
│                                │                                 │
│                                ▼                                 │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │                  approve-claw Mac Agent                  │   │
│   │  - Antigravity IDE Brain Transcript Watcher              │   │
│   │  - PTY Prompt Detector (Claude Code / Codex) [planned]   │   │
│   │  - WebSocket Server (LAN, Port 8080)                     │   │
│   │  - AppleScript Keypress Injection (System Events)        │   │
│   └──────────────────────────┬───────────────────────────────┘   │
└──────────────────────────────┼───────────────────────────────────┘
                               │  Local WebSocket (ws://)
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Apple Mobile Devices                       │
│                                                                  │
│   ┌────────────────────┐  WatchConnectivity  ┌───────────────┐   │
│   │     iPhone App     │ ◄─────────────────► │  Apple Watch  │   │
│   │  (iOS 17+ SwiftUI) │                     │  (watchOS 10+)│   │
│   └────────────────────┘                     └───────────────┘   │
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
- [~] Antigravity IDE — unit tests pass, real-world task execution unstable `[wip]`
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
