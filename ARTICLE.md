# Claude Traffic Light：给你的 Claude Code 装一盏红绿灯 🚦

> 开源 macOS 小工具，让你的多会话 Claude Code 开发体验飞跃升级。

---

## 痛点：你也有过这样的时刻吗？

用 Claude Code 做开发的时候，一个需求拆成几个会话并行推进是常态——一个写前端、一个改后端、一个做代码审查。但问题来了：

- 🤔 **「那边改完了没有？」**——切过去一看才发现已经等了你 5 分钟
- 😫 **「啊怎么报错了？」**——报错会话被埋在窗口堆里，等你发现已经浪费了十几分钟
- 😵 **「我要 Permission 确认的那个窗口呢？」**——翻半天找不到被挡住的终端
- 😴 **「怎么不动了？」**——API 限流卡住了，你还在傻等

Claude Code 的能力越强，你就越需要一个「上帝视角」来管理多个会话。

于是我做了 **Claude Traffic Light**——一个轻量级 macOS 菜单栏工具，用经典的红绿灯语义，让你一眼掌握所有 Claude Code 会话的运行状态。

---

## 🚦 红绿灯的直觉设计

我们天生就理解红绿灯的含义：
- 🔴 **红灯** = 出错、需要干预
- 🟡 **黄灯** = 等待确认、被阻塞
- 🟢 **绿灯** = 正在工作中

Claude Traffic Light 用**三盏呼吸灯**为每个会话建模。状态切换时菜单栏图标闪烁 + 系统通知推送，不让任何一个重要时刻溜走。

---

## 🖼️ 先看效果

### 全景演示

> 从启动 -> 多会话监控 -> 折叠 -> 通知 -> 切换，一气呵成。

![全景演示](https://raw.githubusercontent.com/xiaxiao5946/ClaudeTrafficLight/main/hello.gif)

### 菜单栏面板

三标签筛选（全部 / 活跃 / 已固定），右键复制会话 ID，Bell 图标一键开关通知。

![菜单栏面板](https://raw.githubusercontent.com/xiaxiao5946/ClaudeTrafficLight/main/menu_bar.png)

### 毛玻璃悬浮窗

HUD 风格半透明卡片，自动适应内容高度，双行标题（Agent 自动总结 + 用户首次提问预览）。

![悬浮窗卡片](https://raw.githubusercontent.com/xiaxiao5946/ClaudeTrafficLight/main/fold_ui.png)

### 折叠呼吸灯

拖到屏幕边缘自动吸附为竖排红绿灯条，三盏灯带着柔光呼吸动画。拖走自动展开。

<p align="center">
  <img src="https://raw.githubusercontent.com/xiaxiao5946/ClaudeTrafficLight/main/yellow_light.gif" width="320" alt="折叠呼吸灯">
</p>

### macOS 原生通知

状态变化时弹 macOS 原生通知（无需授权，零权限设计）。

![系统通知](https://raw.githubusercontent.com/xiaxiao5946/ClaudeTrafficLight/main/notification.png)

---

## 🎯 核心功能一览

| 功能 | 说明 |
|------|------|
| **实时状态监控** | 2 秒轮询，解析 Claude 会话 JSON + JSONL 时间戳，识别 thinking / working / blocked / idle / stopped |
| **强提醒** | 菜单栏图标闪烁 + 系统通知，状态变化即时推送 |
| **会话固定** | Pin 住重要会话，完成后保留不消失 |
| **毛玻璃悬浮窗** | HUD 风格半透明窗口 + 圆角毛玻璃背景 |
| **侧边吸附折叠** | 拖到屏幕边缘收折为红绿灯条，拖走自动展开 |
| **呼吸灯动画** | 活跃中的红绿灯柔光呼吸效果，双层发光层次 |
| **三标签筛选** | 全部 / 活跃 / 已固定，右键复制会话 ID |
| **通知开关** | 一键关闭/开启通知 |
| **双行标题** | 优先使用 Agent 自动总结标题，第二行展示用户首次提问 |
| **零权限** | NSUserNotification 实现，无需系统通知授权 |
| **纯本机** | 不联网、不上传、不收集任何数据 |

---

## 🏗️ 技术架构

```
Sources/ClaudeTrafficLight/
├── main.swift              # 入口、AppDelegate、悬浮窗（~550 行）
├── SessionMonitor.swift    # 会话发现、状态解析、Pin 管理
├── Models.swift            # SessionInfo / SessionStatus 数据模型
├── TrafficLightIcon.swift  # 红绿灯图标绘制
├── PopoverView.swift       # 菜单栏 Popover 面板
├── SessionRow.swift        # 会话列表行视图
└── SessionDetailView.swift # 会话详情卡片
```

**状态检测链路：**

```
~/.claude/sessions/*.json (pid + status field)
     ↓
kill(pid, 0) → 进程是否存活
     ↓
~/.claude/projects/<cwd>/*.jsonl (最后一行时间戳 < 30s)
     ↓
解析最后一条 event 类型:
  assistant + tool_use    → 🛠️ working
  assistant + recent      → 👁️ thinking
  system + permission     → ⏸️ blocked
  其他                    → ✅ idle
```

### 技术亮点

- **SwiftUI + AppKit 混合架构**：`NSStatusItem` + `NSPopover` 实现菜单栏；`NSWindow` + `NSHostingView` 实现悬浮窗
- **JSONL 尾行时间戳分析**：不依赖 Claude 内部 API，直接读取会话文件，兼容所有启动场景（终端 / IDE / Cockpit）
- **吸附展开时机优化**：在 `didMoveNotification` 中只记录位置，在 `checkSnapGlobal()` 定时器中延迟判断，防止拖拽中途闪烁
- **毛玻璃背景**：`NSVisualEffectView` 桥接到 SwiftUI，HUD material + 黑色半透明叠加

---

## 📦 安装 & 使用

```bash
# 1. 克隆仓库
git clone https://github.com/xiaxiao5946/ClaudeTrafficLight.git
cd ClaudeTrafficLight

# 2. 构建（无需 Xcode，纯命令行）
bash build.sh

# 3. 运行
open build/ClaudeTrafficLight.app
```

构建产物可直接拖入 `Applications` 文件夹。

> **系统要求**：macOS 13.0+，Apple Silicon（arm64）

---

## 🎮 操作速查

| 操作 | 效果 |
|------|------|
| 点击菜单栏 🚦 图标 | 打开/关闭 Popover 面板 |
| 右键会话行 | 复制会话 ID / Pin/Unpin |
| 拖拽悬浮窗到屏幕边缘 | 自动吸附折叠为红绿灯条 |
| 拖拽悬浮窗离开边缘 | 自动展开为卡片视图 |
| 双击折叠的红绿灯条 | 展开悬浮窗口 |
| 鼠标移开（展开 & 靠边） | 1.5s 后自动折叠 |
| 底部 Pin 图标 | 切换窗口置顶 |
| 底部 Bell 图标 | 开关系统通知 |

---

## 🔧 开发故事

整个项目从 idea 到当前版本，**完全用 Claude Code 对话开发**，数百行 Swift 代码没有手写一行。

三个让我印象深刻的设计决策：

**1. 零权限通知**
macOS 的通知授权弹窗会打断用户心流。使用 `NSUserNotification`（已废弃但 macOS 14 仍可用）实现了无授权弹窗通知——用户运行即用，零摩擦。

**2. JSONL 尾行时间戳分析**
Claude 没有暴露实时状态 API。通过读取 `~/.claude/sessions/*.json` 获取 PID（进程存活检测），然后解析对应的 `.jsonl` 文件最后一行的时间戳和事件类型来推断当前状态。兼容终端、VS Code、Cockpit 等所有启动方式。

**3. 拖拽中途不展开**
早期版本在拖拽过程中检测到远离边缘就立即展开——体验很差。改为「记录位置 → 松手后 1 秒延迟判断」的防抖策略，操作手感大幅提升。

---

## 📄 License & 链接

- **源码**：[github.com/xiaxiao5946/ClaudeTrafficLight](https://github.com/xiaxiao5946/ClaudeTrafficLight)
- **License**：MIT
- **Star 支持**：好用的话给个 ⭐️，欢迎提 Issue / PR！

---

*如果你的 macOS 桌面上也跑着好几个 Claude Code 会话——试试 Traffic Light，它会成为你的第二双眼睛。*
