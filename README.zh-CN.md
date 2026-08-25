# Evernight Launcher

[English](README.md) | **简体中文**

一个用 Swift & SwiftUI 编写的原生 macOS **崩坏：星穹铁道** 启动器。它负责下载、更新、校验并启动官方 Windows 客户端，通过 [Wine](https://www.winehq.org/) 兼容层与 [DXMT](https://github.com/3Shain/dxmt)（Direct3D 11 → Metal 转译）运行。

> Fork 自 [Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher)。

- 💬 **Discord：** https://discord.gg/CyreneEchoes
- **本项目：** https://github.com/March7thHoney/Evernight-Launcher
- **上游（fork 来源）：** https://github.com/Furiri443/Kafka-Launcher

---

## 环境要求

| 组件 | 要求 |
| :--- | :--- |
| **macOS** | macOS 14 Sonoma 或更高 |
| **架构** | Apple Silicon 与 Intel 均可 —— 发布 arm64、x86_64、Universal 三个包 |
| **Xcode** | Xcode 15 或更高（仅从源码编译时需要） |
| **Wine / DXMT / Jadeite** | 由 app 自动下载与管理 |

---

## 快速开始

1. 从 [Releases](https://github.com/March7thHoney/Evernight-Launcher/releases) 下载对应 CPU 架构的包，解压后拖进「应用程序」。
2. 打开 app，点击齿轮图标 → **Game Client Update**（游戏客户端更新）：
   - *已有客户端？* 关闭设置，用底部的 **Locate Game**（定位游戏）指向游戏目录。
   - *全新安装？* 选择 **Official Region**（官服区服，CN / OS），然后点 **Download Game**（下载游戏）。
3. 取消勾选底部的 **Play on March7thHoney**，即为官服直连模式。
4. 点击 **Launch** 启动。

---

## 功能特性

- **官方客户端管理** —— 国服、国际服双区支持（国服走 `hyp-api.mihoyo.com`，国际服走 `sg-hyp-api.hoyoverse.com`）：完整下载（分包 MD5 校验 + 磁盘余量检查）、增量更新，以及对照官方资源清单的 **Quick Verify**（快速校验）与 **Repair Files**（修复文件）。
- **预下载** —— 官方预下载一开放即可提前拉取下个版本的更新数据，走官方启动器现用的 sophon 分块接口。版本上线前不会应用任何文件，上线后点 **Update** 直接用已下好的数据安装、无需重新下载。支持断点续传与取消，进度精确到字节。
- **二进制版本检测** —— 直接读取 Unity `globalgamemanagers` 数据文件来识别已安装版本。
- **正式服 / Beta 双客户端档位** —— 安装目录、已安装版本与状态各自独立记录。Beta 档位通过本地补丁包（`.7z` / `.zip` / `.rar`）更新，同时支持 `ldiff`（分块清单）与 `hdiff`（文件级）两种补丁。
- **Wine 管理** —— 提供 8 个 Wine 构建可选，默认 **Wine 11.8 DXMT (signed)**。按需创建与重建 prefix，并安装修复游戏内过场动画的 Media Foundation DLL。
- **DXMT 0.80（DirectX 11 → Metal）** —— 按版本放置 DLL：≥ 0.74 装入 Wine 的 builtin 库目录，< 0.74 装入 `system32/` 并设置 native override。会话结束后所有改动文件自动还原。
- **启动方式** —— 通过 **Jadeite** 包装器（v4.1.0）启动客户端，并用 `DXMT_CONFIG` 伪装 NVIDIA GPU 以保证渲染正确。
- **图形与输入** —— Metal HUD、HDR、自定义分辨率、Retina 模式、左 ⌘ 映射为 Ctrl、补丁界面缩放（1.0–2.5），以及适合手柄游玩的「始终释放光标」选项。
- **文本语言** —— 可在英文、中文、日文、韩文之间切换游戏内文本语言。
- **高级选项** —— `WINEMSYNC` 高性能线程，以及针对安装在挂载网络卷上的客户端的实验性兼容支持。
- **启动器自动更新** —— 检查本仓库的最新 release，按 CPU 架构挑选对应资产，在 app 内下载并安装。
- **工具全部自带** —— `patch-cli`、`hpatchz`、`7zz` 随 app 一起打包，无需 Homebrew，也不依赖任何外部目录。

---

## 从源码编译

用 Xcode 打开 `Kafka-Launcher.xcodeproj` 直接编译 —— 工程、target 与 scheme 沿用上游名称，但产物是 `Evernight Launcher.app`。

补丁工具 `patch-cli` 用 Go 编写，完整源码已纳入 git，位于 [`PatchToolSource/`](PatchToolSource)。重建方式：

```sh
cd PatchToolSource && ./build.sh
```

需要 Go 工具链（≥ 1.26），脚本会把新的 universal 二进制输出到 `PatchTool/`。仓库自包含：无论编译 app 还是重建工具，都不依赖任何外部目录。

---

## 致谢

- **[Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher)** —— 本项目 fork 自的上游启动器
- **[YAGL](https://github.com/yaagl/yet-another-anime-game-launcher)** —— Kafka-Launcher 所基于的启动器
- **[Wine](https://www.winehq.org/)** —— Windows 兼容层
- **[DXMT](https://github.com/3Shain/dxmt)** —— 3Shain 的 DirectX 11 → Metal 转译
- **[Jadeite](https://codeberg.org/mkrsym1/jadeite)** —— 崩坏：星穹铁道的反作弊包装器
- **[FireflyGo Proxy](https://github.com/AzenKain/FireflyGo_Proxy)** —— AzenKain 的本地代理

---

## 免责声明

本项目与 miHoYo / HoYoVerse 无任何关联、未获其认可或赞助。所有游戏名称与商标归各自所有者所有。使用风险自负。

---

## 许可证

基于 [Apache License 2.0](LICENSE) 授权。
