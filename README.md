<div align="center">

# 🐾 approve-claw v2.0 `[Universal Vision Engine]`

**Desktop App Screen Vision Remote Permission Approval Bridge for macOS AI Agents**

[![Status](https://img.shields.io/badge/status-v2.0--desktop--vision-brightgreen.svg)](https://github.com/tian0t/approve-claw)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/tian0t/approve-claw)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20watchOS-lightgrey.svg)](https://github.com/tian0t/approve-claw)
[![Apple Vision OCR](https://img.shields.io/badge/Engine-Apple%20Vision%20OCR-purple.svg)](https://developer.apple.com/documentation/vision)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18.0.0-339933.svg)](https://nodejs.org/)

*When your desktop AI agent requests execution permission on screen, review and approve it directly from your iPhone or Apple Watch.*

> **Supported Desktop App Agents**: Antigravity IDE ✅ &nbsp;|&nbsp; OpenAI Codex ✅ &nbsp;|&nbsp; Claude Code ✅

[Overview](#-overview) • [Workflow](#-complete-11-closed-loop-workflow) • [Supported Agents](#-supported-desktop-app-agents) • [Architecture](#-system-architecture) • [Installation](#-installation)

</div>

---

## 📌 Overview

**approve-claw v2.0** is an offline, hardware-accelerated remote permission approval system designed specifically for macOS desktop AI coding agents. 

Powered by **Apple ScreenCaptureKit** and the **Apple Vision OCR Engine (`vision_observer.swift`)**, `approve-claw` dynamically monitors your Mac screen for agent confirmation dialogs, extracts all selectable options and button coordinates in real time, mirrors them 1:1 onto your **iPhone** and **Apple Watch**, and synchronizes your mobile decision back to the Mac to execute via simulated mouse clicks or keystrokes.

---

## 🔄 Complete 1:1 Closed-Loop Workflow

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  1. 电脑端屏幕出现选项                                                                 │
│     Antigravity / Codex / Claude Code 桌面 App 弹出需要人工确认的命令或操作选择         │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  2. Apple Vision OCR 原生引擎毫秒级扫描与映射                                          │
│     捕获屏幕 ➔ 动态提取 Agent 身份、执行命令、所有可见选项（文本标签 + 屏幕精确像素坐标）│
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  3. 本地 WebSocket 实时推送 ➔ 手机 & 手表同步弹出                                      │
│     • 📱 iPhone 弹出审批卡片并推送锁屏通知（完整渲染所有动态选项按钮）                  │
│     • ⌚ Apple Watch 触发触觉震动，腕上同步呈现所有选项                                │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  4. 用户在 iPhone 或 Apple Watch 上点击任意一个选项                                    │
│     例如点击："Proceed & Allow Execution"、"Approve" 或 "1. Yes, allow once"          │
└─────────────────────────────────────────┬──────────────────────────────────────────────┘
                                          │
                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  5. 决策信号实时回传 Mac 电脑闭环执行                                                  │
│     ① NSWorkspace 自动激活目标 App 窗口（确保获得系统焦点）                            │
│     ② 电脑端精准执行：                                                                 │
│        • 🖱️ 模拟鼠标：CGEvent 鼠标直接点击该选项在屏幕上的精确坐标                      │
│        • ⌨️ 命令行/按键：自动注入对应数字键/回车键 (Keystroke)                         │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Supported Desktop App Agents

All supported agents are macOS desktop applications:

| 桌面 App Agent | 屏幕识别特征与选项 | 手机 / 手表端映射 | 电脑端闭环执行机制 |
| :--- | :--- | :--- | :--- |
| 🚀 **Antigravity IDE** | 计划/执行审批模态框 (`Proceed`, `Allow`, `Planning Mode`, `Execute`) | `Proceed & Allow`<br>`Cancel & Deny` | 自动激活 Antigravity 窗口 ➔ 鼠标精准点击目标按钮坐标（回车/Esc 兜底） |
| 🌐 **OpenAI Codex** | Web/桌面端审批卡片 (`Approve`, `Reject`, `Ask for approval`) | `Approve`<br>`Reject` | 自动激活 Codex 窗口 ➔ 鼠标精准点击 `Approve`/`Reject` 坐标 |
| 🤖 **Claude Code** | 交互式选择菜单 (`1. Yes, allow once`, `2. Yes, allow...`, `3. No`) | `1. Yes, allow once`<br>`2. Yes, allow for this session`<br>`3. No` | 自动激活 Claude 窗口 ➔ 选项点击 / 注入数字编号 + 回车确认 |

---

## ✨ Key Features

### ⌚ Native Apple Watch App (watchOS 10+)
- Independent watchOS application built with SwiftUI liquid glass aesthetics.
- Real-time synchronization with iPhone via `WatchConnectivity`.
- Single-line fluid option buttons designed for fast wrist taps and haptic notifications.

### 📱 iPhone App & Lock Screen Notifications
- Live status card showing Agent name, command code block, risk indicator, and all dynamic option buttons.
- `UNUserNotificationCenter` push notifications with quick actions.
- Full activity history log with exact option labels (e.g. `1. Yes, allow once`, `Approved`, `Proceed & Allow`).

### 👁️ Native Swift Vision OCR Engine
- Built with `ScreenCaptureKit` + Apple `Vision` framework (`VNRecognizeTextRequest`).
- Pure native Swift implementation (`bin/vision_observer`) without third-party OCR dependencies.
- Hardware-accelerated local scanning with smart cooldown and deduplication.

### 🖱️ Intelligent GUI Click & Keystroke Dispatcher
- Window focus management via `NSWorkspace` for instant app switching.
- Precise `CGEvent` mouse cursor clicking based on OCR bounding boxes.
- Full Retina / HiDPI logical coordinate calibration.

---

## 🏗️ System Architecture

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
│   │  • VNRecognizeTextRequest (Hardware Accelerated OCR)                          │   │
│   │  • Strict App Filter: Antigravity / OpenAI Codex / Claude Code                │   │
│   │  • 1:1 Dynamic Option & Bounding Box Coordinate Extractor                     │   │
│   │  • NSWorkspace Window Focusing + CGEvent Mouse Click / Keystroke Dispatcher   │   │
│   └───────────────────────────────────────┬───────────────────────────────────────┘   │
│                                           │ stdin / stdout JSON Stream                │
│                                           ▼                                           │
│   ┌───────────────────────────────────────────────────────────────────────────────┐   │
│   │                       approve-claw Node.js Daemon                             │   │
│   │  • vision_bridge.js (Subprocess Supervisor & Event Deduplication)             │   │
│   │  • request_lifecycle.js (State Machine, Per-Agent Queue, Timeout Manager)    │   │
│   │  • websocket.js (Local Encrypted WebSocket Gateway, Port 8080)                │   │
│   └───────────────────────────────────────┬───────────────────────────────────────┘   │
└───────────────────────────────────────────┼───────────────────────────────────────────┘
                                            │ Local Wi-Fi WebSocket (ws://)
                                            ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                 Apple Mobile Devices                                  │
│                                                                                       │
│   ┌──────────────────────────────────────┐     WatchConnectivity   ┌──────────────┐   │
│   │              iPhone App              │ ◄─────────────────────► │ Apple Watch  │   │
│   │  • Dynamic Single-Line Option List   │                         │ • Wrist Tap  │   │
│   │  • Lock-Screen Action Notifications  │                         │ • Haptics    │   │
│   │  • Real-time Activity History Log    │                         │ • 1:1 Sync   │   │
│   └──────────────────────────────────────┘                         └──────────────┘   │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Repository Structure

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

## 🚀 Installation & Getting Started

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
> 1. **Screen Recording**: Allow your Terminal / app running `approve-claw` in **System Settings → Privacy & Security → Screen Recording**.
> 2. **Accessibility**: Allow in **System Settings → Privacy & Security → Accessibility** to permit `CGEvent` mouse clicks and keystrokes.

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
2. Select your iPhone as the build target and press **`⌘ + R`** to run.
3. In the iPhone app, input your Mac's LAN IP address and 6-digit PIN code to complete pairing.
4. Your paired Apple Watch will automatically sync and be ready to receive live approval requests!

---

## 🔒 Security & Privacy

- **100% Offline & Local**: All OCR processing runs locally via Apple Neural Engine / Vision framework. All WebSocket communication remains strictly within your local Wi-Fi network.
- **PIN-Protected Handshake**: Pairing requires a 6-digit one-time code generating persistent cryptographic session tokens.
- **No Cloud Dependencies**: Zero external API keys or cloud relay required.

---

## 📄 License

MIT License © 2026 [tian0t](https://github.com/tian0t)
