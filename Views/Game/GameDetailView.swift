import SwiftUI
import UniformTypeIdentifiers

// MARK: - Game Detail View

struct GameDetailView: View {
    @Bindable var gameManager: GameManager
    let openSettings: () -> Void

    private var game: GameInfo { gameManager.currentGame }
    private var state: GameState { gameManager.currentState }
    private var type: GameType { gameManager.selectedGame }

    var body: some View {
        ZStack {
            backgroundLayer

            // Top: title on the left, social links on the right
            VStack {
                HStack(alignment: .top) {
                    gameHeader
                    Spacer()
                    socialLinks
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .padding(.top, 16)

            // Bottom bar
            VStack {
                Spacer()
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
    }

    private var backgroundLayer: some View {
        GeometryReader { proxy in
            let globalFrame = proxy.frame(in: .global)
            ZStack {
                LinearGradient(
                    colors: type.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if type == .honkaiStarRail {
                    Image("StarRailBackground")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else if let bgURL = game.launcherContent?.backgroundURL {
                    CachedAsyncImage(url: bgURL)
                        .transition(.opacity)
                }

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)
                }
            }
            .frame(
                width: max(globalFrame.maxX, proxy.size.width),
                height: max(globalFrame.maxY, proxy.size.height)
            )
            .offset(x: -max(globalFrame.minX, 0), y: -max(globalFrame.minY, 0))
            .animation(.easeInOut(duration: 0.4), value: gameManager.selectedGame)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var gameHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Evernight Launcher")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(game.type.isDarkBackground ? .white : .black)
                .shadow(color: game.type.isDarkBackground ? .black.opacity(0.5) : .white.opacity(0.3), radius: 6, y: 2)

            Text("Forked from Kafka Launcher")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle((game.type.isDarkBackground ? Color.white : Color.black).opacity(0.9))
                .shadow(color: game.type.isDarkBackground ? .black.opacity(0.45) : .white.opacity(0.3), radius: 4, y: 1)
        }
    }

    // MARK: - Social Links

    private var socialLinks: some View {
        HStack(spacing: 10) {
            socialButton(asset: "DiscordLogo",
                         url: "https://discord.gg/CyreneEchoes",
                         help: "Discord")
            socialButton(asset: "GitHubLogo",
                         url: "https://github.com/March7thHoney/Evernight-Launcher",
                         help: "GitHub · Evernight Launcher")
            socialButton(asset: "GitHubLogo",
                         url: "https://github.com/Furiri443/Kafka-Launcher",
                         help: "GitHub · Forked from Kafka Launcher")
        }
    }

    private func socialButton(asset: String, url: String, help: String) -> some View {
        Link(destination: URL(string: url)!) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            if let progress = state.progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.statusText ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))

                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(type.accentColor)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer()

            settingsButton

            // Locate existing game button (always visible so the game directory can be re-pointed anytime)
            Button {
                Task { await gameManager.locateGame(type) }
            } label: {
                Label("Locate Game", systemImage: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassButton(color: .white)

            // Launch button
            launchButton
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .liquidGlassCard(cornerRadius: 18)
    }

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 18, height: 18)
                .overlay(alignment: .topTrailing) {
                    if AppUpdater.shared.updateAvailable {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -3)
                            .shadow(color: .orange.opacity(0.6), radius: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .liquidGlassButton(color: .white)
        .help("Settings")
    }

    // MARK: - Launch Button

    private var launchButton: some View {
        Button {
            Task { await gameManager.performAction(for: type) }
        } label: {
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(launchButtonLabel, systemImage: launchButtonIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassButton(color: type.accentColor)
        .disabled(!state.isActionable)
        .opacity(state.isActionable ? 1.0 : 0.5)
    }

    private var launchButtonLabel: String {
        if state == .ready {
            let config = gameManager.settings.config(for: type)
            if config.useMarch7thHoney { return "Launch March7thHoney" }
        }
        return state.actionLabel
    }

    private var launchButtonIcon: String {
        switch state {
        case .notInstalled: return "arrow.down.to.line"
        case .ready: return "play.fill"
        case .needsUpdate: return "arrow.up.circle.fill"
        case .running: return "stop.fill"
        case .error: return "arrow.clockwise"
        default: return "ellipsis"
        }
    }
}

// MARK: - Game Settings Sheet

struct GameSettingsContent: View {
    @Bindable var gameManager: GameManager
    let gameType: GameType

    @State private var langStatus: String?
    @State private var langStatusIsError = false

    @State private var patchFileURL: URL?
    @State private var updateStatus: String?
    @State private var updateStatusIsError = false
    @State private var showRepairConfirmation = false
    @State private var showBetaOfficialUpdateWarning = false
    @State private var showProductionManualPatchWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
                    settingsGroup("Network") {
                        Toggle("Play on March7thHoney", isOn: Binding(
                            get: { gameManager.settings.config(for: gameType).useMarch7thHoney },
                            set: { newValue in
                                gameManager.settings.updateConfig(for: gameType) { config in
                                    config.useMarch7thHoney = newValue
                                }
                                gameManager.settings.save()
                            }
                        ))

                        if gameManager.settings.config(for: gameType).useMarch7thHoney {
                            Picker("Server", selection: configBinding(\.march7thServerPreset)) {
                                ForEach(GameConfig.March7thServerPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            switch gameManager.settings.config(for: gameType).march7thServerPreset {
                            case .custom:
                                TextField("Server URL (e.g. https://example.com)", text: configBinding(\.march7thHoneyAddress))
                            case .local:
                                Text("Start the server first: run ./Start.command in the March7thHoney folder, then launch the game.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            case .hoyotoon:
                                Text("Connects to the online hoyotoon server.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    settingsGroup("Text Language") {
                        Picker("Text Language", selection: configBinding(\.textLanguage)) {
                            ForEach(LanguagePatchManager.textLanguages) { lang in
                                Text(lang.displayName).tag(lang.code)
                            }
                        }

                        HStack {
                            Button("Apply") { applyTextLanguage() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(gameManager.settings.config(for: gameType).installDirectory == nil)
                            Spacer()
                            if let msg = langStatus {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(langStatusIsError ? .yellow : .green)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Text("Patches game files to change the in-game text language. Install the game first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    settingsGroup("Game Client Update") {
                        HStack {
                            Text("Install Directory")
                            Spacer()
                            Text(gameDirectory ?? "Not selected")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 280, alignment: .trailing)
                        }

                        Picker("Official Region", selection: configBinding(\.officialRegion)) {
                            ForEach(OfficialGameRegion.allCases) { region in
                                Text(region.displayName).tag(region)
                            }
                        }
                        .disabled(hasInstalledClient)

                        HStack {
                            Text("Installed Version")
                            Spacer()
                            Text(gameManager.officialClientManager.installedVersion ?? "Not installed")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Latest Official Version")
                            Spacer()
                            Text(gameManager.officialClientManager.latestVersion ?? "Not checked")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            if hasInstalledClient {
                                Button("Check for Updates") { checkOfficialUpdate() }
                                    .buttonStyle(.bordered)
                                    .disabled(gameManager.officialClientManager.isRunning)
                                Button("Update") { requestOfficialUpdate() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!gameManager.officialClientManager.updateAvailable
                                              || gameManager.officialClientManager.isRunning)
                            } else {
                                Button("Download Game") {
                                    Task { await gameManager.installGame(gameType) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(gameManager.officialClientManager.isRunning)
                            }
                            Spacer()
                        }

                        if hasInstalledClient {
                            HStack {
                                Button("Quick Verify") { verifyOfficialFiles() }
                                    .buttonStyle(.bordered)
                                    .disabled(gameManager.officialClientManager.isRunning)
                                Button("Repair Files") { showRepairConfirmation = true }
                                    .buttonStyle(.bordered)
                                    .disabled(gameManager.officialClientManager.integrityIssues.isEmpty
                                              || gameManager.officialClientManager.isRunning
                                              || isBetaInstalledClient)
                                Spacer()
                            }
                        }

                        if gameManager.officialClientManager.isRunning {
                            ProgressView(value: gameManager.officialClientManager.progress)
                                .progressViewStyle(.linear)
                            Text(gameManager.officialClientManager.stage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if !gameManager.officialClientManager.statusMessage.isEmpty {
                            Text(gameManager.officialClientManager.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Divider().opacity(0.5)
                        Text("Manual Patch")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Select Patch File…") { selectPatchFile() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(gameManager.gameClientUpdateManager.isRunning)
                            Spacer()
                            if let url = patchFileURL {
                                Text(url.lastPathComponent)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        HStack {
                            Button("Update") { requestManualPatchUpdate() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(gameManager.settings.config(for: gameType).installDirectory == nil
                                          || patchFileURL == nil
                                          || gameManager.gameClientUpdateManager.isRunning)
                            Spacer()
                            if let msg = updateStatus {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(updateStatusIsError ? .yellow : .green)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        if gameManager.gameClientUpdateManager.isRunning {
                            ProgressView(value: gameManager.gameClientUpdateManager.progress)
                                .progressViewStyle(.linear)
                            Text(gameManager.gameClientUpdateManager.stage.isEmpty ? "Working…" : gameManager.gameClientUpdateManager.stage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                    }

                    settingsGroup("Wine") {
                        Toggle("Use Global Wine Settings", isOn: configBinding(\.useGlobalWineSettings))

                        if !gameManager.settings.config(for: gameType).useGlobalWineSettings {
                            Picker("Wine Source", selection: configBinding(\.wineSourceMode)) {
                                ForEach(WineSourceMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            
                            if gameManager.settings.config(for: gameType).wineSourceMode == .github {
                                Picker("Wine Version", selection: configBinding(\.wineDistribution)) {
                                    ForEach(WineManager.distributions) { distro in
                                        Text(distro.displayName).tag(distro.id)
                                    }
                                }
                            } else {
                                HStack {
                                    Text(gameManager.settings.config(for: gameType).customWinePath.isEmpty ? "No folder selected" : gameManager.settings.config(for: gameType).customWinePath)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Select...") {
                                        Task { @MainActor in
                                            let panel = NSOpenPanel()
                                            panel.title = "Select Wine Directory"
                                            panel.canChooseDirectories = true
                                            panel.canChooseFiles = false
                                            panel.canCreateDirectories = false
                                            if panel.runModal() == .OK, let url = panel.url {
                                                gameManager.settings.updateConfig(for: gameType) { config in
                                                    config.customWinePath = url.path
                                                }
                                                gameManager.settings.save()
                                            }
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }

                        Divider().opacity(0.5)

                        HStack {
                            Text("Current Status")
                            Spacer()
                            Text(gameManager.wineManager.status.displayName)
                                .foregroundStyle(gameManager.wineManager.status.isReady ? .green : .secondary)
                                .font(.caption.weight(.medium))
                        }
                        
                        HStack {
                            if !gameManager.wineManager.status.isReady {
                                Button("Download & Install Wine for this game") {
                                    Task {
                                        // Apply properly before install
                                        gameManager.applyWineSettings(for: gameType)
                                        let isGlobal = gameManager.settings.config(for: gameType).useGlobalWineSettings
                                        let mode = isGlobal ? gameManager.settings.wineSourceMode : gameManager.settings.config(for: gameType).wineSourceMode
                                        
                                        if mode == .github {
                                            let selected = isGlobal ? gameManager.settings.selectedWineDistribution : gameManager.settings.config(for: gameType).wineDistribution
                                            let distro = WineManager.distributions.first { $0.id == selected }
                                            await gameManager.installWine(distribution: distro)
                                        }
                                    }
                                }
                            } else {
                                @Bindable var gameManager = gameManager
                                RecreatePrefixButton(gameManager: gameManager, gameType: gameType)
                            }
                            
                            Spacer()
                            
                             Button("Re-check") {
                                gameManager.applyWineSettings(for: gameType)
                                _ = gameManager.wineManager.checkWineAvailability()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Divider().opacity(0.5)

                        Toggle("Retina Mode", isOn: configBinding(\.retinaMode))
                        Toggle("Left ⌘ as Ctrl", isOn: configBinding(\.leftCommandIsCtrl))
                    }

                    settingsGroup("Graphics") {
                        Toggle("Enable DXMT", isOn: configBinding(\.enableDXMT))
                        Toggle("Metal HUD", isOn: configBinding(\.metalHUD))
                        Toggle("Enable HDR", isOn: configBinding(\.enableHDR))
                        Toggle("Custom Resolution", isOn: configBinding(\.customResolution))
                        if gameManager.settings.config(for: gameType).customResolution {
                            HStack {
                                TextField("Width", value: configBinding(\.resolutionWidth), format: .number)
                                    .frame(width: 80)
                                Text("×")
                                TextField("Height", value: configBinding(\.resolutionHeight), format: .number)
                                    .frame(width: 80)
                            }
                        }
                    }

                    settingsGroup("Advanced") {
                        Toggle("WINEMSYNC", isOn: configBinding(\.winemsync))
                        Toggle("Steam Emulation", isOn: configBinding(\.useSteamPatch))
                        Toggle("ReShade", isOn: configBinding(\.enableReShade))
                        Toggle("Always Release Cursor", isOn: configBinding(\.alwaysReleaseCursor))
                        Toggle("Windows Mounted-Volume Compatibility (Experimental)", isOn: mountedVolumeCompatibilityBinding)
                            .help("Uses a short Wine drive path only for games on SMB or other network volumes.")
                    }
        }
        .onAppear {
            syncTextLanguageFromGame()
            gameManager.officialClientManager.refreshInstalledInfo(directory: hasInstalledClient ? gameDirectory : nil)
        }
        .alert("Repair Official Files?", isPresented: $showRepairConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Repair") { repairOfficialFiles() }
        } message: {
            Text("Damaged files will be replaced with official copies. This may undo Text Language or other resource modifications.")
        }
        .alert("Update Beta Client from Official Source?", isPresented: $showBetaOfficialUpdateWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Update Anyway") { updateOfficialClient() }
        } message: {
            Text("Version \(installedClientVersion ?? "unknown") is a Beta client. Official production updates may be incompatible and damage this client.")
        }
        .alert("Apply Manual Patch to Production Client?", isPresented: $showProductionManualPatchWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Apply Anyway") { applyClientUpdate() }
        } message: {
            Text("Version \(installedClientVersion ?? "unknown") is a production client. A manually selected diff/hdiff archive may target a Beta or different version and damage this client.")
        }
    }

    private var gameDirectory: String? {
        gameManager.settings.config(for: gameType).installDirectory
    }

    private var hasInstalledClient: Bool {
        guard let gameDirectory else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: gameDirectory + "/StarRail.exe")
            && fm.fileExists(atPath: gameDirectory + "/StarRail_Data")
    }

    private var installedClientVersion: String? {
        gameManager.officialClientManager.installedVersion
            ?? gameManager.settings.config(for: gameType).installedVersion
    }

    private var isBetaInstalledClient: Bool {
        guard let version = installedClientVersion else { return false }
        return GameVersionDetector.isBetaVersion(version)
    }

    private func requestOfficialUpdate() {
        if let version = installedClientVersion, GameVersionDetector.isBetaVersion(version) {
            showBetaOfficialUpdateWarning = true
        } else {
            updateOfficialClient()
        }
    }

    private func requestManualPatchUpdate() {
        if let version = installedClientVersion, GameVersionDetector.isProductionVersion(version) {
            showProductionManualPatchWarning = true
        } else {
            applyClientUpdate()
        }
    }

    private func checkOfficialUpdate() {
        guard let directory = gameDirectory else { return }
        let region = gameManager.settings.config(for: gameType).officialRegion
        Task {
            do {
                try await gameManager.officialClientManager.checkForUpdates(directory: directory, region: region)
            } catch {
                gameManager.officialClientManager.statusMessage = error.localizedDescription
            }
        }
    }

    private func updateOfficialClient() {
        guard let directory = gameDirectory else { return }
        let region = gameManager.settings.config(for: gameType).officialRegion
        Task {
            do {
                let version = try await gameManager.officialClientManager.updateGame(directory: directory, region: region)
                gameManager.settings.updateConfig(for: gameType) { $0.installedVersion = version }
                gameManager.settings.save()
                await gameManager.checkAllGameStates()
            } catch {
                gameManager.officialClientManager.statusMessage = error.localizedDescription
            }
        }
    }

    private func verifyOfficialFiles() {
        guard let directory = gameDirectory else { return }
        let region = gameManager.settings.config(for: gameType).officialRegion
        Task {
            do {
                _ = try await gameManager.officialClientManager.verifyFiles(directory: directory, region: region)
            } catch {
                gameManager.officialClientManager.statusMessage = error.localizedDescription
            }
        }
    }

    private func repairOfficialFiles() {
        guard !isBetaInstalledClient else { return }
        guard let directory = gameDirectory else { return }
        let region = gameManager.settings.config(for: gameType).officialRegion
        Task {
            do {
                try await gameManager.officialClientManager.repairFiles(directory: directory, region: region)
            } catch {
                gameManager.officialClientManager.statusMessage = error.localizedDescription
            }
        }
    }

    // Best-effort: reflect the game's current text language in the picker.
    private func syncTextLanguageFromGame() {
        guard let dir = gameManager.settings.config(for: gameType).installDirectory,
              let current = try? LanguagePatchManager.getTextLanguage(installDirectory: dir),
              current != gameManager.settings.config(for: gameType).textLanguage else { return }
        gameManager.settings.updateConfig(for: gameType) { $0.textLanguage = current }
        gameManager.settings.save()
    }

    private func applyTextLanguage() {
        let config = gameManager.settings.config(for: gameType)
        guard let dir = config.installDirectory else {
            langStatus = "Install the game first."
            langStatusIsError = true
            return
        }
        do {
            try LanguagePatchManager.setTextLanguage(installDirectory: dir, code: config.textLanguage)
            langStatus = "Applied"
            langStatusIsError = false
        } catch {
            langStatus = error.localizedDescription
            langStatusIsError = true
        }
    }

    private func selectPatchFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Patch Archive"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.zip]
        if let t = UTType(filenameExtension: "7z") { types.append(t) }
        if let t = UTType(filenameExtension: "rar") { types.append(t) }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            patchFileURL = url
            updateStatus = nil
        }
    }

    private func applyClientUpdate() {
        guard let dir = gameManager.settings.config(for: gameType).installDirectory else {
            updateStatus = "Install the game first."
            updateStatusIsError = true
            return
        }
        guard let patch = patchFileURL else { return }
        updateStatus = nil
        Task {
            do {
                try await gameManager.gameClientUpdateManager.applyPatch(gameDir: dir, archivePath: patch.path)
                if let version = GameVersionDetector.detectInstalledVersion(gameType: gameType, installDir: dir) {
                    gameManager.settings.updateConfig(for: gameType) { $0.installedVersion = version }
                    gameManager.settings.save()
                }
                await gameManager.checkAllGameStates()
                await MainActor.run {
                    updateStatus = "Updated"
                    updateStatusIsError = false
                }
            } catch {
                await MainActor.run {
                    updateStatus = error.localizedDescription
                    updateStatusIsError = true
                }
            }
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // removed wineDistributionBinding

    private func configBinding<T>(_ keyPath: WritableKeyPath<GameConfig, T>) -> Binding<T> {
        Binding(
            get: { gameManager.settings.config(for: gameType)[keyPath: keyPath] },
            set: { newValue in
                gameManager.settings.updateConfig(for: gameType) { config in
                    config[keyPath: keyPath] = newValue
                }
                gameManager.settings.save()
            }
        )
    }

    private var mountedVolumeCompatibilityBinding: Binding<Bool> {
        Binding(
            get: { gameManager.settings.enableMountedVolumeCompatibility },
            set: {
                gameManager.settings.enableMountedVolumeCompatibility = $0
                gameManager.settings.save()
            }
        )
    }
}

// MARK: - Recreate Prefix Button

struct RecreatePrefixButton: View {
    let gameManager: GameManager
    let gameType: GameType
    
    @State private var isRecreating = false
    
    var body: some View {
        Button {
            isRecreating = true
            Task {
                gameManager.applyWineSettings(for: gameType)
                try? await gameManager.wineManager.recreateWinePrefix()
                await MainActor.run {
                    isRecreating = false
                }
            }
        } label: {
            if isRecreating {
                ProgressView().controlSize(.small)
            } else {
                Text("Recreate Wine Prefix")
            }
        }
        .disabled(isRecreating)
    }
}
