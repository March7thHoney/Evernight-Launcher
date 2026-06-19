# Evernight Launcher

**English** | [简体中文](README.zh-CN.md)

A native macOS launcher for **Honkai: Star Rail**, built with Swift & SwiftUI. It runs the Windows client through the [Wine](https://www.winehq.org/) compatibility layer with [DXMT](https://github.com/3Shain/dxmt) (Direct3D 11 → Metal translation), and connects it to a private server.

> Forked from [Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher) and trimmed down to focus on a single game — Honkai: Star Rail — and its private servers.

- 💬 **Discord:** https://discord.gg/CyreneEchoes
- **This project:** https://github.com/March7thHoney/Evernight-Launcher
- **Upstream (forked from):** https://github.com/Furiri443/Kafka-Launcher

---

## Requirements

| Component | Requirement |
| :--- | :--- |
| **macOS** | macOS 14 Sonoma or later |
| **Architecture** | Apple Silicon (arm64) |
| **Xcode** | Xcode 15 or later (to build from source) |
| **Wine / DXMT / Jadeite** | Downloaded & managed automatically by the app |

---

## Supported Games

| Game | Status |
| :--- | :---: |
| Honkai: Star Rail | ✅ |

Genshin Impact and Zenless Zone Zero (present in the upstream launcher) are intentionally removed — this launcher is Honkai: Star Rail only.

---

## Private Servers

The launcher starts the official Honkai: Star Rail client under Wine and redirects its dispatch
traffic to a private server through a local MITM proxy. The proxy's CA certificate is imported into
the Wine prefix so the client's HTTPS dispatch validates; the game then connects to the gateway the
dispatch returns. Enable it in **Honkai: Star Rail → Settings → Network**:

| Mode | What it does |
| :--- | :--- |
| **Play on March7thHoney** | Redirects dispatch to a March7thHoney server running locally (`127.0.0.1:21000`). Start the server yourself first, then launch the game. |

The launch button shows *Launch March7thHoney* when enabled.

---

## Features

### Native macOS Experience
Built entirely in Swift & SwiftUI with zero Electron or Node.js runtime overhead. Uses the modern `@Observable` macro for reactive state management and smooth SwiftUI updates.

### Wine Management
Automatically downloads and manages Wine installations, including optimized community builds (e.g., **3Shain v9.9-dxmt** tuned for the Metal API). Handles Media Foundation DLL installation to fix in-game cutscene playback.

### DXMT (DirectX 11 → Metal)
Version-aware DLL placement for optimal D3D11 to Metal translation:
- DXMT ≥ 0.74.0 → installed directly into Wine's library directory.
- DXMT < 0.74.0 → installed into `system32/` with native override.

### Binary Version Detection
Reads Unity binary data files (e.g., `globalgamemanagers`) directly to detect the installed game version — more accurate and resilient than text log or config file parsing.

### 4-Phase Launch Sequence

```
Phase 0 — Clear any stale wineserver (avoids an esync/msync mismatch crash)

Phase 1 — Pre-Launch Setup
  Start the redirect proxy → Set Wine properties
  → Apply Resolution & HDR Registry → Configure Proxy
  → Import the proxy CA + macOS Certificates → Wait for WineServer to idle

Phase 2 — Patching
  Place DXMT DLLs → Inject nvngx.dll → Download Jadeite → Backup Crash Reporters

Phase 3 — Game Execution
  Generate config.bat → Set Environment Variables
  → Launch via Wine/Jadeite → Monitor process until exit

Phase 4 — Post-Launch Cleanup
  Revert Registry → Restore backup files
  → Revert DXMT DLLs → Terminate proxy → Clean up config.bat
```

**Pre-Launch Setup** — Configures Wine properties (Retina Mode, Left Command → Control key mapping). Generates `.reg` files for proxy settings and imports both the redirect-proxy CA and macOS Keychain root certificates into the Wine certificate store for reliable HTTPS dispatch.

**Patching** — Places DXMT translation libraries, injects `nvngx.dll` for NVIDIA GPU emulation, and backs up game crash reporter executables to prevent Wine conflicts.

**Game Execution** — Sets key environment variables including `WINEMSYNC`/`WINEESYNC` for high-performance threading and `DXMT_CONFIG` to spoof an NVIDIA GPU vendor/device ID for Star Rail (`10de`/`2684`), plus the HTTP/HTTPS proxy that performs the dispatch redirect.

**Post-Launch Cleanup** — Restores all patched files from `.bak` backups, reverts registry changes, terminates the proxy, and removes temporary scripts.

### Honkai: Star Rail Specifics
- **Jadeite wrapper** (v4.1.0) is used to launch the client.
- **NVIDIA GPU spoof** via DXMT for correct rendering.
- **WebView fix** applied for the in-game browser.

### xdelta3 Binary Patching
Applies binary patches for Wine compatibility using `xdelta3`. All patches are automatically reverted after each session to preserve the original game data.

### Independent from Kafka-Launcher
Uses its own data directory (`~/.evernight-launcher`) and bundle identifier (`com.march7thhoney.evernight-launcher`), so it can be installed and run alongside the original Kafka-Launcher without sharing Wine prefixes, game setup, or settings. The upstream auto-updater is disabled, since this is a customized fork.

---

## Project Structure

```
Evernight-Launcher/
├── Models/
│   ├── GameConfig.swift          # Per-game config + private-server mode (March7thHoney)
│   ├── GameInfo.swift            # Game metadata
│   ├── GameState.swift           # State machine (notInstalled, ready, running, updating…)
│   └── GameType.swift            # Game enum + `displayed` list (Honkai: Star Rail only)
├── Services/
│   ├── GameManager.swift         # Central orchestrator: install, update, proxy & launch lifecycle
│   ├── WineManager.swift         # Wine installation, wineprefix, MediaFoundation DLLs
│   ├── DXMTManager.swift         # DXMT download & version-aware DLL placement
│   ├── RegistryManager.swift     # Wine registry file generation (UTF-16LE + BOM), CA import
│   ├── PatchManager.swift        # xdelta3 binary patch apply & restore
│   ├── JadeiteManager.swift      # Jadeite wrapper management
│   ├── GameServerAPI.swift       # Update manifests
│   └── GameVersionDetector.swift # Unity binary-based version detection
├── Utilities/
│   ├── ProcessRunner.swift       # Async shell process execution
│   └── Extensions.swift          # Swift utility extensions
└── Views/                        # SwiftUI views (MainView, GameDetailView, Settings…)
```

---

## Credits

- **[Kafka-Launcher](https://github.com/Furiri443/Kafka-Launcher)** — the upstream launcher this project is forked from
- **[Wine](https://www.winehq.org/)** — Windows compatibility layer
- **[DXMT](https://github.com/3Shain/dxmt)** — DirectX 11 to Metal translation by 3Shain
- **[Jadeite](https://github.com/an-anime-team/jadeite)** — Anti-cheat wrapper for Honkai: Star Rail
- **[xdelta3](http://xdelta.org/)** — Binary delta patching
- **[YAGL](https://github.com/yaagl/yet-another-anime-game-launcher)** — the launcher Kafka-Launcher is based on
- **[FireflyGo Proxy](https://github.com/AzenKain/FireflyGo_Proxy)** — local MITM redirect proxy by AzenKain

---

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by miHoYo / HoYoVerse. All game names and trademarks are the property of their respective owners. Use at your own risk.

---

## License

Licensed under the [Apache License 2.0](LICENSE).
