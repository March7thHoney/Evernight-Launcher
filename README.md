# Evernight Launcher

**English** | [简体中文](README.zh-CN.md)

A native macOS launcher for **Honkai: Star Rail**, built with Swift & SwiftUI. It downloads, updates, verifies and launches the official Windows client, running it through the [Wine](https://www.winehq.org/) compatibility layer with [DXMT](https://github.com/3Shain/dxmt) (Direct3D 11 → Metal translation).

> Forked from [Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher).

- 💬 **Discord:** https://discord.gg/CyreneEchoes
- **This project:** https://github.com/March7thHoney/Evernight-Launcher
- **Upstream (forked from):** https://github.com/Furiri443/Kafka-Launcher

---

## Requirements

| Component | Requirement |
| :--- | :--- |
| **macOS** | macOS 14 Sonoma or later |
| **Architecture** | Apple Silicon or Intel — arm64, x86_64 and Universal builds are published |
| **Xcode** | Xcode 15 or later (only needed to build from source) |
| **Wine / DXMT / Jadeite** | Downloaded & managed automatically by the app |

---

## Quick Start

1. Grab the build for your CPU from [Releases](https://github.com/March7thHoney/Evernight-Launcher/releases), unzip it and drag it into **Applications**.
2. Open the app and click the gear icon → **Game Client Update**:
   - *Already have the client?* Close settings and use **Locate Game** in the bottom bar to point at the game folder.
   - *Fresh install?* Pick your **Official Region** (CN / OS), then **Download Game**.
3. Uncheck **Play on March7thHoney** in the bottom bar to connect directly to the official servers.
4. Click **Launch**.

---

## Features

- **Official client management** — Both regions supported (CN via `hyp-api.mihoyo.com`, OS via `sg-hyp-api.hoyoverse.com`): full download with MD5-verified packages and a free-space check, incremental updates, plus **Quick Verify** and **Repair Files** against the official resource list. The live version comes from the sophon branch tag, which is what the official launcher now tracks; incremental updates prefer the sophon chunk patch and fall back to the legacy package patch.
- **Pre-download** — Fetches the next version's update data as soon as the official pre-download window opens, using the sophon chunk API the official launcher now uses. Nothing is applied until the version goes live; **Update** then installs from the staged data without downloading again. Resumable and cancellable, with byte-level progress.
- **Binary version detection** — Reads the Unity `globalgamemanagers` data file directly to identify the installed version.
- **Independent Official / Beta profiles** — Install directory, installed version and state are tracked separately per profile. The Beta profile updates from a local patch archive (`.7z` / `.zip` / `.rar`), supporting both `ldiff` (chunked manifest) and `hdiff` (file-level) patches. An interrupted update can simply be re-run, and locally modified files the patch no longer recognises are left untouched and reported instead of aborting the update.
- **Wine management** — Eight Wine builds to choose from, defaulting to **Wine 11.8 DXMT (signed)**. Creates and recreates the prefix on demand, and installs the Media Foundation DLLs that fix in-game cutscene playback.
- **DXMT 0.80 (DirectX 11 → Metal)** — Version-aware DLL placement: ≥ 0.74 goes into Wine's builtin library directory, < 0.74 into `system32/` with a native override. Every patched file is reverted when the session ends.
- **Launch** — The client is started through the **Jadeite** wrapper (v4.1.0), with an NVIDIA GPU spoof via `DXMT_CONFIG` for correct rendering.
- **Graphics & input** — Metal HUD, HDR, custom resolution, Retina mode, Left ⌘ as Ctrl, patch UI scale (1.0–2.5), and an always-release-cursor option for gamepad play.
- **Text language** — Switch the in-game text language between English, Chinese, Japanese and Korean.
- **Advanced** — `WINEMSYNC` high-performance threading, and experimental compatibility for a client installed on a mounted network volume.
- **Launcher auto-update** — Checks this repository's latest release, picks the asset matching your CPU architecture, and downloads & installs it in-app.
- **Everything bundled** — `patch-cli`, `hpatchz` and `7zz` ship inside the app, so no Homebrew or external directory is required.

---

## Building from Source

Open `Kafka-Launcher.xcodeproj` in Xcode and build — the project, target and scheme keep the upstream name, but the product is `Evernight Launcher.app`.

The patch tool `patch-cli` is written in Go and its full source is tracked in [`PatchToolSource/`](PatchToolSource). To rebuild it:

```sh
cd PatchToolSource && ./build.sh
```

That requires the Go toolchain (≥ 1.26) and stages a fresh universal binary into `PatchTool/`. The repository is self-contained: neither the app nor the tool depends on any external directory.

---

## Credits

- **[Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher)** — the upstream launcher this project is forked from
- **[YAGL](https://github.com/yaagl/yet-another-anime-game-launcher)** — the launcher Kafka-Launcher is based on
- **[Wine](https://www.winehq.org/)** — Windows compatibility layer
- **[DXMT](https://github.com/3Shain/dxmt)** — DirectX 11 to Metal translation by 3Shain
- **[Jadeite](https://codeberg.org/mkrsym1/jadeite)** — anti-cheat wrapper for Honkai: Star Rail
- **[FireflyGo Proxy](https://github.com/AzenKain/FireflyGo_Proxy)** — local proxy by AzenKain

---

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by miHoYo / HoYoVerse. All game names and trademarks are the property of their respective owners. Use at your own risk.

---

## License

Licensed under the [Apache License 2.0](LICENSE).
