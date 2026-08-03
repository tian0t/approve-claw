# approve-claw [WIP]

> **[WIP] Work In Progress / 未完成项目**
> 
> 本项目处于持续开发与修复阶段。

---

## 📌 项目简介 (Overview)

`approve-claw` 是一款为 Mac 端 AI Agent (如 Antigravity IDE, Claude Code, Codex 等) 设计的远程安全审批与实时通知系统。它通过 WebSocket 服务将 Mac 端的工具运行、文件读写等沙盒放行请求实时推送至用户的 **iPhone** 与 **Apple Watch**，支持在移动设备与智能手表上轻点完成多选项放行与拒绝。

---

## ⚠️ 已知问题与待修复 Bug (Known Issues & Bugs)

> [!WARNING]
> **当前版本开发状态说明**：
> - 🟢 **电脑端测试**：在电脑端本地测试及模拟器交互中均能顺利通过测试。
> - 🔴 **实际任务执行**：在实际真实任务复杂执行场景下（如 Antigravity IDE 进行多文件关联修改、连续语法检查等），仍会存在问题，无法稳定完成确认，需要进一步修复与优化。

---

## 🏗️ 系统架构 (Architecture)

1. **Mac Agent (Node.js Daemon)**
   - 监听系统后台日志与 WebSocket 状态。
   - 实时提取 AI Agent 弹出的放行请求与多选项（Dynamic Options）。
   - 通过 macOS AppleScript (System Events) 将移动端决议（如 `1. Yes, allow this time`）物理模拟键盘输入写回 IDE。

2. **iOS & watchOS App (SwiftUI & WatchConnectivity)**
   - iPhone 原生 Swift 应用，支持 UNUserNotificationCenter 快捷操作与 Dynamic UI 卡片。
   - Apple Watch (watchOS) 原生独立 companion 应用，支持单行放行按钮与实时 Haptic 震动提醒。

---

## 🔧 开发与编译 (Build & Setup)

### Mac Agent
```bash
cd mac-agent
npm install
node src/index.js daemon
```

### iOS / watchOS App
```bash
# 生成 Xcode 工程文件
xcodegen generate

# 编译 iOS & watchOS Target
xcodebuild -project WatchApprove.xcodeproj -target WatchApprove -destination 'generic/platform=iOS' build
xcodebuild -project WatchApprove.xcodeproj -target WatchApproveWatch -destination 'generic/platform=watchOS' build
```

---

## 📄 License

MIT License
