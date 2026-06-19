# Evernight Launcher

[English](README.md) | **简体中文**

一个用 Swift & SwiftUI 编写的原生 macOS **崩坏：星穹铁道** 启动器。它通过 [Wine](https://www.winehq.org/) 兼容层与 [DXMT](https://github.com/3Shain/dxmt)（Direct3D 11 → Metal 转译）运行 Windows 客户端，并将其连接到私服。

> Fork 自 [Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher)，精简为只专注于一款游戏——崩坏：星穹铁道——及其私服。

- 💬 **Discord：** https://discord.gg/castoriceps
- **本项目：** https://github.com/March7thHoney/Evernight-Launcher
- **上游（fork 来源）：** https://github.com/Furiri443/Kafka-Launcher

---

## 环境要求

| 组件 | 要求 |
| :--- | :--- |
| **macOS** | macOS 14 Sonoma 或更高 |
| **架构** | Apple Silicon (arm64) |
| **Xcode** | Xcode 15 或更高（从源码编译时） |
| **Wine / DXMT / Jadeite** | 由 app 自动下载与管理 |

---

## 支持的游戏

| 游戏 | 状态 |
| :--- | :---: |
| 崩坏：星穹铁道 | ✅ |

原神和绝区零（上游启动器中存在）已被刻意移除——本启动器只服务于崩坏：星穹铁道。

---

## 私服

启动器在 Wine 下启动官方崩坏：星穹铁道客户端，并通过本地 MITM 代理把它的 dispatch 流量重定向到私服。代理的 CA 证书会被导入 Wine prefix，使客户端的 HTTPS dispatch 校验通过；随后游戏连接到 dispatch 返回的网关。在 **崩坏：星穹铁道 → 设置 → Network** 中启用：

| 模式 | 作用 |
| :--- | :--- |
| **Play on March7thHoney** | 把 dispatch 重定向到本地运行的 March7thHoney 服务端（`127.0.0.1:21000`）。请先自行启动服务端，再启动游戏。 |

启用后底部启动按钮显示 *Launch March7thHoney*。

> 登录使用你真实的国际服账号凭据，向官方 shield 端点校验（该端点不经代理）；只有进入游戏后的会话由私服提供。

---

## 功能特性

### 原生 macOS 体验
完全用 Swift & SwiftUI 构建，没有 Electron 或 Node.js 运行时开销。使用现代的 `@Observable` 宏做响应式状态管理，SwiftUI 更新流畅。

### Wine 管理
自动下载并管理 Wine（包括为 Metal API 调优的社区构建，如 **3Shain v9.9-dxmt**）。处理 Media Foundation DLL 安装以修复游戏内过场动画播放。

### DXMT（DirectX 11 → Metal）
按版本智能放置 DLL，以获得最佳的 D3D11 → Metal 转译：
- DXMT ≥ 0.74.0 → 直接装入 Wine 的库目录。
- DXMT < 0.74.0 → 装入 `system32/` 并设置 native override。

### 二进制版本检测
直接读取 Unity 二进制数据文件（如 `globalgamemanagers`）来检测已安装的游戏版本——比解析文本日志或配置文件更准确、更稳健。

### 四阶段启动流程

```
Phase 0 — 清理残留 wineserver（避免 esync/msync 模式不匹配导致的崩溃）

Phase 1 — 启动前准备
  启动重定向代理 → 设置 Wine 属性
  → 应用分辨率与 HDR 注册表 → 配置代理
  → 导入代理 CA + macOS 证书 → 等待 WineServer 空闲

Phase 2 — 打补丁
  放置 DXMT DLL → 注入 nvngx.dll → 下载 Jadeite → 备份崩溃上报程序

Phase 3 — 启动游戏
  生成 config.bat → 设置环境变量
  → 通过 Wine/Jadeite 启动 → 监控进程直到退出

Phase 4 — 启动后清理
  还原注册表 → 恢复备份文件
  → 还原 DXMT DLL → 终止代理 → 清理 config.bat
```

**启动前准备** —— 配置 Wine 属性（Retina 模式、左 Command → Control 键映射）。生成代理设置的 `.reg` 文件，并把重定向代理的 CA 与 macOS 钥匙串根证书导入 Wine 证书库，保证 HTTPS dispatch 可靠。

**打补丁** —— 放置 DXMT 转译库，注入 `nvngx.dll` 做 NVIDIA GPU 模拟，并备份游戏崩溃上报程序以避免 Wine 冲突。

**启动游戏** —— 设置关键环境变量，包括用于高性能线程的 `WINEMSYNC`/`WINEESYNC`、为星铁伪造 NVIDIA GPU 厂商/设备 ID 的 `DXMT_CONFIG`（`10de`/`2684`），以及执行 dispatch 重定向的 HTTP/HTTPS 代理。

**启动后清理** —— 从 `.bak` 备份还原所有被修改的文件，还原注册表改动，终止代理，并删除临时脚本。

### 崩坏：星穹铁道专属
- 使用 **Jadeite 包装器**（v4.1.0）启动客户端。
- 通过 DXMT 做 **NVIDIA GPU 伪装** 以正确渲染。
- 应用 **WebView 修复**（游戏内浏览器）。

### xdelta3 二进制补丁
用 `xdelta3` 为 Wine 兼容性打二进制补丁。每次会话结束后自动还原所有补丁，以保持原始游戏数据不变。

### 与 Kafka-Launcher 相互独立
使用独立的数据目录（`~/.evernight-launcher`）和包标识（`com.march7thhoney.evernight-launcher`），因此可以与原版 Kafka-Launcher 并存运行，不共享 Wine prefix、游戏配置或设置。上游的自动更新已禁用（因为这是定制 fork）。

---

## 项目结构

```
Evernight-Launcher/
├── Models/
│   ├── GameConfig.swift          # 每游戏配置 + 私服模式（March7thHoney）
│   ├── GameInfo.swift            # 游戏元数据
│   ├── GameState.swift           # 状态机（notInstalled、ready、running、updating…）
│   └── GameType.swift            # 游戏枚举 + `displayed` 列表（仅崩坏：星穹铁道）
├── Services/
│   ├── GameManager.swift         # 中枢编排：安装、更新、代理与启动生命周期
│   ├── WineManager.swift         # Wine 安装、wineprefix、MediaFoundation DLL
│   ├── DXMTManager.swift         # DXMT 下载与按版本放置 DLL
│   ├── RegistryManager.swift     # Wine 注册表文件生成（UTF-16LE + BOM）、CA 导入
│   ├── PatchManager.swift        # xdelta3 二进制补丁的应用与还原
│   ├── JadeiteManager.swift      # Jadeite 包装器管理
│   ├── GameServerAPI.swift       # 更新清单
│   └── GameVersionDetector.swift # 基于 Unity 二进制的版本检测
├── Utilities/
│   ├── ProcessRunner.swift       # 异步 shell 进程执行
│   └── Extensions.swift          # Swift 工具扩展
└── Views/                        # SwiftUI 视图（MainView、GameDetailView、Settings…）
```

---

## 致谢

- **[Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher)** —— 本项目 fork 自的上游启动器
- **[Wine](https://www.winehq.org/)** —— Windows 兼容层
- **[DXMT](https://github.com/3Shain/dxmt)** —— 3Shain 的 DirectX 11 → Metal 转译
- **[Jadeite](https://github.com/an-anime-team/jadeite)** —— 崩坏：星穹铁道的反作弊包装器
- **[xdelta3](http://xdelta.org/)** —— 二进制增量补丁
- **[YAGL](https://github.com/yaagl/yet-another-anime-game-launcher)** —— Kafka-Launcher 所基于的启动器

---

## 免责声明

本项目与 miHoYo / HoYoVerse 无任何关联、未获其认可或赞助。所有游戏名称与商标归各自所有者所有。使用风险自负。

---

## 许可证

基于 [Apache License 2.0](LICENSE) 授权。
