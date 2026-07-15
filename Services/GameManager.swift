import SwiftUI

// MARK: - Game Manager (full implementation of game launch pipeline)

@Observable
class GameManager {
    var games: [GameType: GameInfo]
    var gameStates: [GameType: GameState] = [:]
    var settings: LauncherSettings
    var selectedGame: GameType
    var errorMessage: String?
    var showErrorAlert: Bool = false

    let downloadManager = DownloadManager()
    let wineManager = WineManager()
    let gameClientUpdateManager = GameClientUpdateManager()
    let api = GameServerAPI.shared
    private var activeProxyProcess: Process?

    init() {
        let settings = LauncherSettings.load()
        self.settings = settings
        // Only HSR is exposed; clamp any previously-persisted selection (e.g. Genshin) to a displayed game.
        self.selectedGame = GameType.displayed.contains(settings.selectedGame)
            ? settings.selectedGame
            : (GameType.displayed.first ?? .honkaiStarRail)

        var gamesMap: [GameType: GameInfo] = [:]
        var statesMap: [GameType: GameState] = [:]
        for info in GameInfo.defaultGames {
            gamesMap[info.type] = info
            statesMap[info.type] = .notInstalled
        }
        self.games = gamesMap
        self.gameStates = statesMap

        Task { await checkAllGameStates() }
        Task { await fetchAllBackgrounds() }
        Task { await checkWineStatus() }
        // Auto-check this fork's own GitHub releases on launch; prompts if a newer version exists
        Task { _ = await AppUpdater.shared.checkForUpdates(prompt: true) }
    }

    var currentGame: GameInfo {
        games[selectedGame] ?? GameInfo.defaultGames[0]
    }

    var currentState: GameState {
        gameStates[selectedGame] ?? .notInstalled
    }

    // MARK: - State Management

    func selectGame(_ type: GameType) {
        selectedGame = type
        settings.selectedGame = type
        settings.save()
    }

    @MainActor
    func reportError(_ message: String, for type: GameType) {
        gameStates[type] = .error(message: message)
        self.errorMessage = message
        self.showErrorAlert = true
    }

    // MARK: - Wine Status Check

    func checkWineStatus() async {
        // Sync settings → WineManager before checking
        applyWineSettings()

        let status = wineManager.checkWineAvailability()
        // Only auto-download when using GitHub mode and wine is missing
        if !status.isReady && settings.wineSourceMode == .github {
            print("Wine not ready: \(status.displayName). Auto-downloading...")
            let selectedId = settings.selectedWineDistribution
            let distro = WineManager.distributions.first { $0.id == selectedId }
            await installWine(distribution: distro)
        }
    }

    /// Apply current Wine settings from LauncherSettings → WineManager
    func applyWineSettings(for gameType: GameType? = nil) {
        let targetType = gameType ?? selectedGame
        let config = settings.config(for: targetType)
        
        let mode = config.useGlobalWineSettings ? settings.wineSourceMode : config.wineSourceMode
        let path = config.useGlobalWineSettings ? settings.customWinePath : config.customWinePath
        
        switch mode {
        case .custom:
            wineManager.customWinePath = path
        case .github:
            wineManager.customWinePath = ""
        }
    }

    // MARK: - Private Server Proxy Helpers
    
    private func findFreePort() -> Int {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        if socket == -1 { return 8080 }
        defer { close(socket) }
        
        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult == -1 { return 8080 }
        
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsocknameResult = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socket, $0, &len)
            }
        }
        if getsocknameResult == -1 { return 8080 }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
    
    #if arch(arm64)
    private let isArm = true
    #else
    private let isArm = false
    #endif

    var proxyDirectoryPath: String {
        let folder = isArm ? "prebuild_mac_arm" : "prebuild_mac_x86"
        return WineManager.basePath + "/" + folder
    }

    func ensureProxyBinaryAvailable() async throws -> String {
        let fm = FileManager.default
        let folderPath = proxyDirectoryPath

        // Ensure folder directory exists
        try fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

        let proxyPath = folderPath + "/firefly-go-proxy"

        // The redirect proxy is bundled in the app (offline, self-contained — no download).
        let bundledName = isArm ? "firefly-go-proxy-macos-arm64" : "firefly-go-proxy-macos-amd64"
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent(bundledName).path,
              fm.fileExists(atPath: bundled) else {
            throw NSError(domain: "ProxyManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Bundled proxy \(bundledName) not found in app."])
        }
        // Refresh whenever the deployed copy differs (a launcher update can ship a new proxy of identical size, so compare bytes not just existence).
        if !fm.contentsEqual(atPath: bundled, andPath: proxyPath) {
            try? fm.removeItem(atPath: proxyPath)
            try fm.copyItem(atPath: bundled, toPath: proxyPath)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: proxyPath)
            adhocSignBinary(proxyPath)
        }

        // Set permissions again
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: proxyPath)

        return proxyPath
    }

    // Clear quarantine and ad-hoc re-sign a native binary copied out of the app bundle so macOS runs it.
    private func adhocSignBinary(_ path: String) {
        for (tool, args) in [("/usr/bin/xattr", ["-dr", "com.apple.quarantine", path]),
                             ("/usr/bin/codesign", ["--force", "--sign", "-", path])] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    // MARK: - Install Wine

    func installWine(distribution: WineDistribution? = nil) async {
        do {
            try await wineManager.installWine(distribution: distribution) { progress in
                print("Wine install: \(progress.description)")
            }

            // Auto-download DXMT after Wine is ready
            print("DXMT: Checking availability...")
            try await DXMTManager.ensureDXMTAvailable()
            print("DXMT: Ready")
        } catch {
            print("Wine installation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Check All Game States (with version detection from Unity binaries)

    func checkAllGameStates() async {
        let orderedTypes = [selectedGame] + GameType.displayed.filter { $0 != selectedGame }
        for type in orderedTypes {
            let config = settings.config(for: type)
            if let dir = config.installDirectory, isGamePresent(type, at: dir) {
                await MainActor.run {
                    gameStates[type] = .checkingForUpdates
                }

                // Detect installed version from Unity binary files
                var detectedVersion = config.installedVersion
                if detectedVersion == nil {
                    detectedVersion = GameVersionDetector.detectInstalledVersion(
                        gameType: type, installDir: dir
                    )
                    if let v = detectedVersion {
                        settings.updateConfig(for: type) { config in
                            config.installedVersion = v
                        }
                        settings.save()
                    }
                }

                // Always allow running the installed version; skip update checks.
                await MainActor.run {
                    gameStates[type] = .ready
                }
            } else {
                await MainActor.run {
                    gameStates[type] = .notInstalled
                }
            }
        }
    }

    private func isGamePresent(_ type: GameType, at dir: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir + "/" + type.executable) { return true }
        if fm.fileExists(atPath: dir + "/" + type.dataDir) { return true }
        return false
    }

    // MARK: - Locate Existing Game

    func locateGame(_ type: GameType) async {
        guard let url = await selectInstallDirectory(for: type) else { return }
        let dir = url.path

        if isGamePresent(type, at: dir) {
            // Detect version
            let version = GameVersionDetector.detectInstalledVersion(gameType: type, installDir: dir)

            await MainActor.run {
                settings.updateConfig(for: type) { config in
                    config.installDirectory = dir
                    config.installedVersion = version
                }
                settings.save()
            }
            await checkAllGameStates()
        } else {
            await MainActor.run {
                reportError("Game not found in selected directory", for: type)
            }
        }
    }

    func fetchAllBackgrounds() async {
        for type in GameType.allCases {
            guard var info = games[type] else { continue }
            do {
                let content = try await api.fetchGameBackground(for: info)
                info.launcherContent = content
                await MainActor.run {
                    games[type] = info
                }
            } catch {
                print("Failed to fetch background for \(type.displayName): \(error)")
            }
        }
    }

    // MARK: - Actions

    func performAction(for type: GameType) async {
        let state = gameStates[type] ?? .notInstalled
        switch state {
        case .notInstalled:
            await installGame(type)
        case .ready:
            await launchGame(type)
        case .needsUpdate:
            await updateGame(type)
        case .error:
            await checkAllGameStates()
            let newState = gameStates[type] ?? .notInstalled
            switch newState {
            case .notInstalled:
                await installGame(type)
            case .ready:
                await launchGame(type)
            case .needsUpdate:
                await updateGame(type)
            default:
                break
            }
        default:
            break
        }
    }

    func selectInstallDirectory(for type: GameType) async -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = "Select Installation Directory for \(type.displayName)"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return url
        }
    }

    // MARK: - Install Game

    func installGame(_ type: GameType) async {
        guard let installURL = await selectInstallDirectory(for: type) else { return }

        await MainActor.run {
            settings.updateConfig(for: type) { config in
                config.installDirectory = installURL.path
            }
            settings.save()
            gameStates[type] = .installing(progress: 0, status: "Preparing...")
        }

        do {
            // Ensure Wine is ready
            if !wineManager.status.isReady {
                await MainActor.run {
                    gameStates[type] = .installing(progress: 0, status: "Installing Wine...")
                }
                try await wineManager.installWine { [weak self] progress in
                    Task { @MainActor in
                        self?.gameStates[type] = .installing(
                            progress: Double(progress.downloadProgress) * 0.2,
                            status: progress.description
                        )
                    }
                }
            }

            let manifest = try await api.fetchLatestVersion(for: games[type]!)
            guard let major = manifest.main.major,
                  let pkg = major.game_pkgs.first,
                  let url = URL(string: pkg.url) else {
                await MainActor.run { reportError("No download available", for: type) }
                return
            }

            // Download and extract game
            downloadManager.downloadAndExtract(
                url: url,
                to: installURL.path,
                id: type.rawValue,
                gameType: type,
                onProgress: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.gameStates[type] = .installing(
                            progress: 0.2 + progress * 0.8,
                            status: status
                        )
                    }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in
                        switch result {
                        case .success:
                            self?.settings.updateConfig(for: type) { config in
                                config.installedVersion = major.version
                            }
                            self?.settings.save()
                            self?.gameStates[type] = .ready
                        case .failure(let error):
                            self?.reportError(error.localizedDescription, for: type)
                        }
                    }
                }
            )
        } catch {
            await MainActor.run {
                reportError(error.localizedDescription, for: type)
            }
        }
    }

    // MARK: - Update Game

    func updateGame(_ type: GameType) async {
        await MainActor.run {
            gameStates[type] = .updating(progress: 0, status: "Checking update...")
        }
        // For now, re-install (full Sophon diff-update would require the Python backend)
        await installGame(type)
    }

    // MARK: - Full 4-Phase Game Launch

    func launchGame(_ type: GameType) async {
        let config = settings.config(for: type)
        guard let installDir = config.installDirectory else {
            await MainActor.run { reportError("Game not installed", for: type) }
            return
        }

        await MainActor.run { gameStates[type] = .launching }

        var freePort = 8080
        var privateServerCertPath: String?
        var launchRegistryPath: String?
        var batchPath: String?
        var managedDriveMapping: ManagedWineDriveMapping?
        var wineGameDir = wineManager.toWinePath(installDir)
        
        let prefix = WineManager.defaultPrefixPath
        let launchLog = LaunchLogger(gameType: type)
        
        let wineSourceMode = config.useGlobalWineSettings ? settings.wineSourceMode : config.wineSourceMode
        let currentDistroId = config.useGlobalWineSettings ? settings.selectedWineDistribution : config.wineDistribution
        let currentDistro: WineDistribution?
        if wineSourceMode == .github {
            currentDistro = WineManager.distributions.first { $0.id == currentDistroId }
        } else {
            currentDistro = nil
        }
        let renderBackend = currentDistro?.renderBackend ?? (wineSourceMode == .custom ? "custom" : "dxmt")
        let useDXMT = config.enableDXMT && (renderBackend == "dxmt" || wineSourceMode == .custom)

        do {
            // Apply proper wine settings before launch
            applyWineSettings(for: type)
            
            launchLog.info("════════════════════════════════════════")
            launchLog.info("Launching \(type.displayName)")
            launchLog.info("Install dir: \(installDir)")
            launchLog.info("Wine binary: \(wineManager.getWineBinary())")
            launchLog.info("Wine mode: \(settings.config(for: type).useGlobalWineSettings ? "Global" : "Per-game custom")")
            launchLog.info("Wine source: \(wineSourceMode.rawValue) (distribution: \(currentDistroId))")
            launchLog.info("Wine prefix: \(prefix)")
            launchLog.info("Render backend: \(renderBackend) (DXMT enabled: \(useDXMT))")
            launchLog.info("════════════════════════════════════════")

            // Clear any stale wineserver from a previous session first, otherwise an
            // esync/msync mode mismatch crashes the Phase 1 registry import (reg import
            // fails with exit code 8 / SIGFPE).
            launchLog.info("[Phase 0] Clearing any stale wineserver...")
            await wineManager.killWineServer(prefix: prefix)
            wineManager.cleanupStaleManagedDriveMappings(prefix: prefix)

            let fileSystemType = wineManager.fileSystemType(at: installDir)
            let isNetworkVolume = wineManager.isNetworkVolume(fileSystemType: fileSystemType)
            launchLog.info("[Phase 0] Mounted-volume compatibility: enabled=\(settings.enableMountedVolumeCompatibility), filesystem=\(fileSystemType ?? "unknown"), network=\(isNetworkVolume)")
            if settings.enableMountedVolumeCompatibility && isNetworkVolume {
                let mapping = try wineManager.prepareManagedDriveMapping(for: installDir, prefix: prefix)
                managedDriveMapping = mapping
                wineGameDir = mapping.wineRootPath
                launchLog.info("[Phase 0] Managed Wine drive: \(mapping.wineRootPath) -> \(mapping.targetPath)")
            }
            launchLog.info("[Phase 0] Final Wine game path: \(wineGameDir)")

            // 0. Start the redirect proxy (March7thHoney) if enabled
            if config.requiresRedirectProxy {
                let proxyPath = try await ensureProxyBinaryAvailable()
                launchLog.info("[Phase 1] March7thHoney mode enabled. Preparing proxy...")

                // 0b. Launch Proxy
                freePort = findFreePort()
                let proxyProcess = Process()
                proxyProcess.executableURL = URL(fileURLWithPath: proxyPath)
                let redirectHost = config.proxyRedirectHost
                proxyProcess.arguments = ["-no-sys", "-p", String(freePort), "-r", redirectHost]
                proxyProcess.currentDirectoryURL = URL(fileURLWithPath: proxyDirectoryPath)
                // Capture firefly output to a log so launch failures (forwarding, TLS) are diagnosable.
                let fireflyLogPath = WineManager.logsPath + "/firefly.log"
                FileManager.default.createFile(atPath: fireflyLogPath, contents: nil)
                if let fh = FileHandle(forWritingAtPath: fireflyLogPath) {
                    proxyProcess.standardOutput = fh
                    proxyProcess.standardError = fh
                } else {
                    proxyProcess.standardOutput = FileHandle.nullDevice
                    proxyProcess.standardError = FileHandle.nullDevice
                }

                launchLog.info("[Phase 1] Starting proxy at port \(freePort) redirecting to \(redirectHost)...")
                try proxyProcess.run()
                self.activeProxyProcess = proxyProcess
                
                // Wait a bit for CA cert file generation by the proxy
                try await Task.sleep(nanoseconds: 1_000_000_000)
                
                let caCertPath = proxyDirectoryPath + "/firefly-go-proxy-ca.crt"
                guard FileManager.default.fileExists(atPath: caCertPath) else {
                    throw NSError(domain: "ProxyManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Failed to start proxy: CA cert file not found at \(caCertPath)."])
                }
                
                launchLog.info("[Phase 1] Firefly CA cert ready at \(caCertPath)")
                privateServerCertPath = caCertPath
            }

            // ═══════════════════════════════════════════
            // PHASE 1: Pre-Launch Setup (Registry)
            // ═══════════════════════════════════════════

            // Build one registry file so Wine imports launch settings once.
            var registryEntries: [RegistryManager.Entry] = []

            launchLog.info("[Phase 1] Preparing launch registry (retina=\(config.retinaMode), leftCmd=\(config.leftCommandIsCtrl))")
            registryEntries += RegistryManager.generateWinePropsRegistryEntries(
                retinaMode: config.retinaMode,
                leftCommandIsCtrl: config.leftCommandIsCtrl
            )

            registryEntries += RegistryManager.generateConsoleRegistryEntries()
            registryEntries += RegistryManager.generateAudioDriverRegistryEntries()

            if type == .honkaiStarRail && useDXMT {
                launchLog.info("[Phase 1] Adding NV extension registry for HSR...")
                registryEntries += RegistryManager.generateNVExtensionRegistryEntries()
            }

            if config.enableHDR {
                registryEntries += RegistryManager.generateHDRRegistryEntries(gameType: type, enable: true)
            }

            if config.customResolution {
                registryEntries += RegistryManager.generateResolutionRegistryEntries(
                    gameType: type,
                    width: config.resolutionWidth,
                    height: config.resolutionHeight,
                    fullscreen: false
                )
            }

            let isProxyEnabled = config.requiresRedirectProxy
            let targetProxyHost = "127.0.0.1:\(freePort)"
            launchLog.info("[Phase 1] Configuring proxy registry (enabled=\(isProxyEnabled), host=\(targetProxyHost))...")
            registryEntries += RegistryManager.generateProxyRegistryEntries(enable: isProxyEnabled, proxyHost: targetProxyHost)

            if let privateServerCertPath {
                guard let entries = RegistryManager.certificateRegistryEntries(at: privateServerCertPath) else {
                    throw NSError(domain: "ProxyManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse Firefly CA certificate at \(privateServerCertPath)."])
                }
                registryEntries += entries
            }

            if isProxyEnabled {
                launchLog.info("[Phase 1] Adding macOS Keychain certificates to launch registry...")
                if let entries = await RegistryManager.macCertificateRegistryEntries() {
                    registryEntries += entries
                }
            }

            launchLog.info("[Phase 1] Applying combined registry (\(registryEntries.count) keys)...")
            let registryData = RegistryManager.generateRegistryFile(entries: registryEntries)
            launchRegistryPath = try await RegistryManager.writeAndApply(
                data: registryData,
                fileName: "launch_\(type.rawValue).reg",
                wineManager: wineManager,
                prefix: prefix
            )
            launchLog.info("[Phase 1] Complete")

            // ═══════════════════════════════════════════
            // PHASE 2: Patching
            // ═══════════════════════════════════════════

            // 2a. Place DXMT DLLs (always place if enabled)
            if useDXMT {
                launchLog.info("[Phase 2] Placing DXMT DLLs (version: \(config.installedDXMTVersion ?? DXMTManager.currentDXMTVersion))...")
                try await DXMTManager.ensureDXMTAvailable()
                try DXMTManager.placeDXMTDLLs(
                    gameDir: installDir,
                    winePrefix: prefix,
                    installedVersion: config.installedDXMTVersion,
                    gameType: type
                )
                launchLog.info("[Phase 2] DXMT DLLs placed")
            }

            // 2b. Ensure jadeite is available for HSR
            if JadeiteManager.requiresJadeite(for: type) {
                launchLog.info("[Phase 2] Ensuring jadeite available...")
                try await JadeiteManager.ensureJadeiteAvailable()
                launchLog.info("[Phase 2] Jadeite ready at \(JadeiteManager.jadeiteExe)")
            }

            // 2b2. Ensure bundled HSR-Patch (HSRLauncher + CyreneHook) for March7thHoney login redirect
            if config.useMarch7thHoney && type == .honkaiStarRail {
                launchLog.info("[Phase 2] Ensuring HSR-Patch available...")
                try HSRPatchManager.ensureAvailable()
                launchLog.info("[Phase 2] HSR-Patch ready at \(HSRPatchManager.launcherExe)")
            }

            // 2c. Remove crash reporters and vulkan-1.dll
            let filesToRemove = Self.filesToRemove(for: type)
            for file in filesToRemove {
                let filePath = installDir + "/" + file
                let bakPath = filePath + ".bak"
                if FileManager.default.fileExists(atPath: filePath) {
                    if !FileManager.default.fileExists(atPath: bakPath) {
                        try? FileManager.default.moveItem(atPath: filePath, toPath: bakPath)
                        launchLog.info("[Phase 2] Removed: \(file)")
                    }
                }
            }

            // 2d. Place Steam emulation DLLs for Genshin
            // HSR and ZZZ do NOT use steam emulation
            if type == .genshinImpact && config.useSteamPatch {
                let system32 = prefix + "/drive_c/windows/system32"
                let syswow64 = prefix + "/drive_c/windows/syswow64"
                let sidecarDir = WineManager.sidecarPath + "/protonextras"
                let fm = FileManager.default

                if fm.fileExists(atPath: sidecarDir) {
                    let steamFiles: [(src: String, dst: String)] = [
                        ("steam64.exe", system32 + "/steam.exe"),
                        ("steam32.exe", syswow64 + "/steam.exe"),
                        ("lsteamclient64.dll", system32 + "/lsteamclient.dll"),
                        ("lsteamclient32.dll", syswow64 + "/lsteamclient.dll"),
                    ]
                    for (src, dst) in steamFiles {
                        let srcPath = sidecarDir + "/" + src
                        if fm.fileExists(atPath: srcPath) {
                            if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
                            try? fm.copyItem(atPath: srcPath, toPath: dst)
                            launchLog.info("[Phase 2] Placed steam DLL: \(src)")
                        }
                    }
                } else {
                    launchLog.info("[Phase 2] ⚠️ Steam sidecar not found at \(sidecarDir), skipping steam emulation")
                }
            }

            launchLog.info("[Phase 2] Complete")

            // ═══════════════════════════════════════════
            // PHASE 3: Game Execution
            // ═══════════════════════════════════════════

            // 3a. Generate config.bat
            // Write config.bat in the data directory, NOT in the game directory.
            // Writing into the game folder can trigger anti-cheat.
            let batchScript = generateLaunchBatch(
                wineGameDir: wineGameDir,
                executable: type.executable,
                type: type
            )
            batchPath = WineManager.basePath + "/config.bat"
            try batchScript.write(toFile: batchPath!, atomically: true, encoding: .utf8)

            launchLog.info("[Phase 3] Batch script written to \(batchPath!):")
            launchLog.info("--- config.bat ---")
            for line in batchScript.split(separator: "\n", omittingEmptySubsequences: false) {
                launchLog.info("  \(line)")
            }
            launchLog.info("--- end ---")

            // 3b. Build environment variables
            var env: [String: String] = [:]
            let baseDir = WineManager.basePath

            if managedDriveMapping != nil,
               type == .honkaiStarRail,
               isMainlandChinaHSRInstall(at: installDir) {
                env["LANG"] = "zh_CN.UTF-8"
                env["LC_ALL"] = "zh_CN.UTF-8"
                launchLog.info("[Phase 3] Using zh-CN process locale for mounted CN HSR")
            }

            // Metal HUD
            if config.metalHUD {
                env["MTL_HUD_ENABLED"] = "1"
            }

            // Disable Metal validation layer — Xcode enables MTLDebugDevice by default
            // which causes MTLStorageModeShared assertions on non-Apple GPUs.
            env["MTL_DEBUG_LAYER"] = "0"
            env["MTL_SHADER_VALIDATION"] = "0"

            // Env is determined by the effective Wine render backend.
            if useDXMT {
// DXMT mode
                env["WINEDLLOVERRIDES"] = ""
                env["DXMT_LOG_PATH"] = baseDir
                env["GST_PLUGIN_FEATURE_RANK"] = "atdec:MAX,avdec_h264:MAX"

                // Ensure dxmt.conf exists
                let confPath = baseDir + "/dxmt.conf"
                if !FileManager.default.fileExists(atPath: confPath) {
                    FileManager.default.createFile(atPath: confPath, contents: nil)
                }
                env["DXMT_CONFIG_FILE"] = confPath

                // Game-specific DXMT config
                if type == .honkaiStarRail {
                    env["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;dxgi.customVendorId=10de;dxgi.customDeviceId=2684"
                    env["DXMT_ENABLE_NVEXT"] = "1"
                } else if type == .genshinImpact {
                    env["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;"
                }
            } else {
                // Non-DXMT mode
                env["WINEESYNC"] = "1"
            }

            // WINEMSYNC is optional because stale non-msync wineserver processes can
            // make Wine abort before the game starts.
            if config.winemsync {
                env["WINEMSYNC"] = "1"
                env.removeValue(forKey: "WINEESYNC")
            } else if env["WINEESYNC"] == nil {
                env["WINEESYNC"] = "1"
            }

            // Proxy
            if config.requiresRedirectProxy {
                env["HTTP_PROXY"] = "127.0.0.1:\(freePort)"
                env["HTTPS_PROXY"] = "127.0.0.1:\(freePort)"
            }

            // March7thHoney: tell the injected patch which server to use (webview redirect) and route its in-process WinHTTP through firefly so any server (local or online) works.
            if config.useMarch7thHoney && type == .honkaiStarRail {
                env["CYRENE_WEB_TARGET"] = config.march7thHoneyTargetURL
                env["CYRENE_PROXY"] = "127.0.0.1:\(freePort)"
            }

            // GStreamer (if not already set)
            if env["GST_PLUGIN_FEATURE_RANK"] == nil {
                env["GST_PLUGIN_FEATURE_RANK"] = "atdec:MAX,avdec_h264:MAX"
            }

            // 3c. Setup logging
            let logsDir = WineManager.logsPath
            try FileManager.default.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
            let logFile = logsDir + "/\(type.rawValue)_\(Int(Date().timeIntervalSince1970)).log"

            // Log all env vars
            launchLog.info("[Phase 3] Environment variables:")
            for (key, value) in env.sorted(by: { $0.key < $1.key }) {
                launchLog.info("  \(key)=\(value)")
            }
            launchLog.info("[Phase 3] Wine log file: \(logFile)")
            launchLog.info("[Phase 3] Executing wine \(batchPath!)...")

            if env["WINEMSYNC"] != nil {
                launchLog.info("[Phase 3] Ensuring no stale wineserver before WINEMSYNC launch...")
                try? await wineManager.waitForWineServerOff(prefix: prefix)
            }

            // 3e. Execute via Wine (cmd /c config.bat)
            // If steamPatch is enabled for Genshin, use steam.exe as launcher
            let winBatchPath = wineManager.toWinePath(batchPath!)
            let winExePath = winePath(in: wineGameDir, relativePath: type.executable)
            let process: Process
            if config.useSteamPatch && type == .genshinImpact {
                // Launch via steam.exe
                process = try await wineManager.launchGame(
                    executable: "C:\\windows\\system32\\steam.exe",
                    arguments: [winExePath],
                    workingDirectory: installDir,
                    environment: env,
                    logFile: logFile,
                    prefix: prefix
                )
            } else {
                process = try await wineManager.launchGame(
                    executable: winBatchPath,
                    workingDirectory: installDir,
                    environment: env,
                    logFile: logFile,
                    prefix: prefix
                )
            }

            // Wait for game to exit — non-blocking, UI remains responsive
            let exitCode = try await ProcessRunner.run(process) { p in
                Task { @MainActor in self.gameStates[type] = .running }
                launchLog.info("[Phase 3] Game process started (PID: \(p.processIdentifier))")
            }
            
            launchLog.info("[Phase 3] Game exited with code: \(exitCode)")

            // Print last 50 lines of Wine log
            if let logData = FileManager.default.contents(atPath: logFile),
               let logContent = String(data: logData, encoding: .utf8) {
                let lines = logContent.split(separator: "\n", omittingEmptySubsequences: false)
                let tail = lines.suffix(50)
                launchLog.info("[Wine Log] Last \(tail.count) lines of \(logFile):")
                for line in tail {
                    launchLog.info("  \(line)")
                }
            }

            // Wait for wineserver off
            launchLog.info("[Phase 4] Waiting for wineserver off...")
            try? await wineManager.waitForWineServerOff(prefix: prefix)
            if let mapping = managedDriveMapping {
                wineManager.cleanupManagedDriveMapping(mapping)
                managedDriveMapping = nil
                launchLog.info("[Phase 4] Removed managed Wine drive \(mapping.wineRootPath)")
            }

            // ═══════════════════════════════════════════
            // PHASE 4: Post-Launch Cleanup
            // ═══════════════════════════════════════════

            // 4a. Remove temporary launch registry file
            if let path = launchRegistryPath {
                RegistryManager.revertRegistryFile(path: path)
                launchRegistryPath = nil
            }

            // 4b. Restore removed files (crash reporters, vulkan-1.dll)
            let filesToRestore = Self.filesToRemove(for: type)
            for file in filesToRestore {
                let filePath = installDir + "/" + file
                let bakPath = filePath + ".bak"
                if FileManager.default.fileExists(atPath: bakPath) {
                    if FileManager.default.fileExists(atPath: filePath) {
                        try? FileManager.default.removeItem(atPath: filePath)
                    }
                    try? FileManager.default.moveItem(atPath: bakPath, toPath: filePath)
                }
            }

            // 4c. Revert DXMT DLLs
            if useDXMT {
                try? DXMTManager.revertDXMTDLLs(
                    winePrefix: prefix,
                    installedVersion: config.installedDXMTVersion,
                    gameType: type
                )
            }

            // 4d. Clean up batch script
            if let path = batchPath {
                try? FileManager.default.removeItem(atPath: path)
                batchPath = nil
            }

            // 4e. Terminate proxy
            if activeProxyProcess != nil {
                launchLog.info("[Phase 4] Terminating proxy...")
                activeProxyProcess?.terminate()
                activeProxyProcess = nil
            }
            launchLog.info("[Phase 4] Cleanup complete")
            launchLog.info("════════════════════════════════════════")
            await MainActor.run { gameStates[type] = .ready }
        } catch {
            print("[LaunchGame] ❌ ERROR: \(error.localizedDescription)")

            if let mapping = managedDriveMapping {
                await wineManager.killWineServer(prefix: prefix)
                wineManager.cleanupManagedDriveMapping(mapping)
                managedDriveMapping = nil
            }
            
            // Clean up proxy process
            if activeProxyProcess != nil {
                activeProxyProcess?.terminate()
                activeProxyProcess = nil
            }

            if let path = launchRegistryPath {
                RegistryManager.revertRegistryFile(path: path)
            }
            
            // Clean up batch file
            if let path = batchPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            
            // Restore removed crash files
            let filesToRestore = Self.filesToRemove(for: type)
            for file in filesToRestore {
                let filePath = installDir + "/" + file
                let bakPath = filePath + ".bak"
                if FileManager.default.fileExists(atPath: bakPath) {
                    if FileManager.default.fileExists(atPath: filePath) {
                        try? FileManager.default.removeItem(atPath: filePath)
                    }
                    try? FileManager.default.moveItem(atPath: bakPath, toPath: filePath)
                }
            }
            
            // Revert DXMT DLLs
            if useDXMT {
                try? DXMTManager.revertDXMTDLLs(
                    winePrefix: prefix,
                    installedVersion: config.installedDXMTVersion,
                    gameType: type
                )
            }
            
            await MainActor.run {
                reportError(error.localizedDescription, for: type)
            }
        }
    }

    // MARK: - Batch Script Generation

    /// Generate batch script matching target format.
    /// Uses JS template literals which produce \n line endings — Wine's cmd.exe handles both.
    private func generateLaunchBatch(wineGameDir: String, executable: String, type: GameType) -> String {
        let winGameDir = wineGameDir
        let config = settings.config(for: type)

        if JadeiteManager.requiresJadeite(for: type) {
            if config.useMarch7thHoney {
                // March7thHoney: HSRLauncher launches the configured game suspended and injects game_payload.dll (mhypbase bypass under Wine) + CyreneHook.dll (rewrites login webview to private server) before resuming — early enough to catch the first login webview load.
                let winExePath = winePath(in: winGameDir, relativePath: executable)
                let winHSRLauncher = wineManager.toWinePath(WineManager.basePath + "/hsrpatch/HSRLauncher.exe")
                return "@echo off\ncd \"%~dp0\"\ncd /d \"\(winGameDir)\"\n\"\(winHSRLauncher)\" \"\(winExePath)\""
            }
            // HSR (other servers): use jadeite wrapper (no HoYoKProtect copy)
            let winJadeitePath = wineManager.toWinePath(JadeiteManager.jadeiteExe)
            let winExePath = winePath(in: winGameDir, relativePath: executable)
            return "@echo off\ncd \"%~dp0\"\ncd /d \"\(winGameDir)\"\n\"\(winJadeitePath)\" \"\(winExePath)\" -- -disable-gpu-skinning"
        } else if type == .zenlessZoneZero {
            // ZZZ: copy HoYoKProtect.sys + resolution as CLI args
            let protectSrc = winePath(in: winGameDir, relativePath: "HoYoKProtect.sys")
            var args = ""
            if config.customResolution {
                args = " -screen-width \(config.resolutionWidth) -screen-height \(config.resolutionHeight) -screen-fullscreen 0"
            }
            return "@echo off\ncd \"%~dp0\"\ncopy \"\(protectSrc)\" \"%WINDIR%\\system32\\\"\ncd /d \"\(winGameDir)\"\n\"\(winePath(in: winGameDir, relativePath: executable))\"\(args)"
        } else {
            // Genshin: copy HoYoKProtect.sys + cloud platform args
            let protectSrc = winePath(in: winGameDir, relativePath: "HoYoKProtect.sys")
            return "@echo off\ncd \"%~dp0\"\ncopy \"\(protectSrc)\" \"%WINDIR%\\system32\\\"\ncd /d \"\(winGameDir)\"\n\"\(winePath(in: winGameDir, relativePath: executable))\" -platform_type CLOUD_THIRD_PARTY_PC -is_cloud 1"
        }
    }

    private func winePath(in root: String, relativePath: String) -> String {
        root + "\\" + relativePath.replacingOccurrences(of: "/", with: "\\")
    }

    private func isMainlandChinaHSRInstall(at installDirectory: String) -> Bool {
        let configPath = installDirectory + "/config.ini"
        guard let data = FileManager.default.contents(atPath: configPath),
              let contents = String(data: data, encoding: .utf8) else { return false }
        return contents.range(of: "cps=hyp_mihoyo", options: .caseInsensitive) != nil
    }

    // MARK: - Files to Remove per game

    private static func filesToRemove(for type: GameType) -> [String] {
        switch type {
        case .genshinImpact:
            // Files to remove for Genshin
            return [
                "GenshinImpact_Data/upload_crash.exe",
                "GenshinImpact_Data/Plugins/crashreport.exe",
                "GenshinImpact_Data/Plugins/vulkan-1.dll",
            ]
        case .honkaiStarRail:
            // Files to remove for Honkai Star Rail
            return [
                "StarRail_Data/upload_crash.exe",
                "StarRail_Data/Plugins/crashreport.exe",
                "StarRail_Data/Plugins/vulkan-1.dll",
            ]
        case .zenlessZoneZero:
            // Files to remove for Zenless Zone Zero
            return [
                "ZenlessZoneZero_Data/upload_crash.exe",
                "ZenlessZoneZero_Data/Plugins/crashreport.exe",
                "ZenlessZoneZero_Data/Plugins/vulkan-1.dll",
            ]
        }
    }

    // MARK: - Fix Webview

    private func fixWebview(type: GameType, prefix: String) async throws {
        let key: String
        switch type {
        case .honkaiStarRail:
            key = "HKEY_CURRENT_USER\\Software\\Cognosphere\\Star Rail"
        case .zenlessZoneZero:
            key = "HKEY_CURRENT_USER\\Software\\miHoYo\\ZenlessZoneZero"
        default:
            return
        }

        // Build registry to delete webview render method keys
        var regLines = [
            "Windows Registry Editor Version 5.00",
            "",
            "[\(key)]",
            "\"MIHOYOSDK_WEBVIEW_RENDER_METHOD_h1573598267\"=-"
        ]

        // Query existing registry for HOYO_WEBVIEW_RENDER_METHOD_ABTEST_ keys
        let queryResult = try? await wineManager.exec(
            program: "reg",
            arguments: ["query", key],
            prefix: prefix,
            logFile: WineManager.basePath + "/fix_webview.log"
        )

        if queryResult == 0 {
            let logPath = WineManager.basePath + "/fix_webview.log"
            if let logData = FileManager.default.contents(atPath: logPath),
               let output = String(data: logData, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("HOYO_WEBVIEW_RENDER_METHOD_ABTEST_") {
                        let abtest = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
                        if !abtest.isEmpty {
                            regLines.append("\"\(abtest)\"=-")
                        }
                    }
                }
            }
            try? FileManager.default.removeItem(atPath: logPath)
        }

        // Write and import the reg file
        let regContent = regLines.joined(separator: "\r\n")
        let regPath = WineManager.basePath + "/fix_webview.reg"

        // Write as UTF-16LE (Windows registry format)
        if let data = regContent.data(using: .utf16LittleEndian) {
            // Add BOM
            var bom = Data([0xFF, 0xFE])
            bom.append(data)
            try bom.write(to: URL(fileURLWithPath: regPath))
        }

        _ = try? await wineManager.exec(
            program: "reg",
            arguments: ["import", wineManager.toWinePath(regPath)],
            prefix: prefix
        )

        try? FileManager.default.removeItem(atPath: regPath)
    }

    // MARK: - Predownload

    func predownloadUpdate(for type: GameType) async {
        guard let gameInfo = games[type] else { return }

        do {
            let manifest = try await api.fetchLatestVersion(for: gameInfo)
            guard let predownload = manifest.pre_download,
                  let major = predownload.major,
                  let pkg = major.game_pkgs.first,
                  let url = URL(string: pkg.url) else { return }

            let tempDir = WineManager.basePath + "/predownload/\(type.rawValue)"
            try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

            downloadManager.download(
                url: url,
                to: URL(fileURLWithPath: tempDir + "/" + url.lastPathComponent),
                id: "predownload_\(type.rawValue)",
                gameType: type,
                onProgress: { _ in },
                onComplete: { [weak self] result in
                    if case .success = result {
                        self?.settings.updateConfig(for: type) { config in
                            config.predownloadedAll = true
                        }
                        self?.settings.save()
                    }
                }
            )
        } catch {
            print("Predownload failed: \(error)")
        }
    }
}

// MARK: - WineInstallProgress Extension

extension WineInstallProgress {
    var downloadProgress: Double {
        switch self {
        case .downloading(let p): return p
        default: return 0
        }
    }
}

// MARK: - Launch Logger

private struct LaunchLogger {
    let gameType: GameType
    let startTime = Date()

    func info(_ message: String) {
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        print("[Launch/\(gameType.shortName) +\(elapsed)s] \(message)")
    }

    func warning(_ message: String) {
        info("[WARNING] \(message)")
    }

    func error(_ message: String) {
        info("[ERROR] \(message)")
    }
}
