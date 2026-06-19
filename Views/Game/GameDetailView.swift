import SwiftUI

// MARK: - Game Detail View

struct GameDetailView: View {
    @Bindable var gameManager: GameManager
    @State private var showGameSettings = false

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
        .sheet(isPresented: $showGameSettings) {
            GameSettingsSheet(gameManager: gameManager, gameType: type)
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

            // Open local FireflyGo folder (only when FireflyGo mode is enabled)
            if gameManager.settings.config(for: type).useFireflyPS {
                Button {
                    let path = gameManager.proxyDirectoryPath
                    // Ensure the folder exists so Finder can open it
                    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .help("Open FireflyGo Folder")
            }

            // Settings button
            if state == .ready || state == .notInstalled {
                Button {
                    showGameSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
            }

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
            if config.useFireflyPS { return "Launch FireflyGo" }
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

struct GameSettingsSheet: View {
    @Bindable var gameManager: GameManager
    let gameType: GameType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header - always visible
            HStack {
                Text("\(gameType.displayName) Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.2))

            Divider()

            // Scrollable custom form content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsGroup("Installation") {
                        HStack {
                            Text("Install Directory")
                            Spacer()
                            Text(gameManager.settings.config(for: gameType).installDirectory ?? "Not set")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 180, alignment: .trailing)
                        }
                        Button("Change Installer Directory...") {
                            Task {
                                if let url = await gameManager.selectInstallDirectory(for: gameType) {
                                    gameManager.settings.updateConfig(for: gameType) { config in
                                        config.installDirectory = url.path
                                    }
                                    gameManager.settings.save()
                                    await gameManager.checkAllGameStates()
                                }
                            }
                        }
                        
                        if gameManager.currentState == .ready {
                            Divider().opacity(0.5)
                            Button("Check Integrity") {
                                Task { await gameManager.checkIntegrity(for: gameType) }
                            }
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

                    settingsGroup("Audio") {
                        Picker("Voice Language", selection: configBinding(\.voiceLanguage)) {
                            ForEach(GameConfig.VoiceLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                    }

                    settingsGroup("Network") {
                        Toggle("Enable Proxy", isOn: configBinding(\.proxyEnabled))
                        if gameManager.settings.config(for: gameType).proxyEnabled {
                            TextField("Proxy Host", text: configBinding(\.proxyHost))
                        }
                        
                        Divider().opacity(0.3)

                        Toggle("Play on March7thHoney (Local Server)", isOn: Binding(
                            get: { gameManager.settings.config(for: gameType).useMarch7thHoney },
                            set: { newValue in
                                gameManager.settings.updateConfig(for: gameType) { config in
                                    config.useMarch7thHoney = newValue
                                    if newValue {
                                        config.useFireflyPS = false
                                        config.usePrivateServer = false
                                    }
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

                        Divider().opacity(0.3)

                        Toggle("Run FireflyPS (Local Proxy Helper)", isOn: Binding(
                            get: { gameManager.settings.config(for: gameType).useFireflyPS },
                            set: { newValue in
                                gameManager.settings.updateConfig(for: gameType) { config in
                                    config.useFireflyPS = newValue
                                    if newValue {
                                        config.usePrivateServer = false
                                        config.useMarch7thHoney = false
                                    }
                                }
                                gameManager.settings.save()
                            }
                        ))
                        
                        Toggle("Play on Private Server (Direct Connection)", isOn: Binding(
                            get: { gameManager.settings.config(for: gameType).usePrivateServer },
                            set: { newValue in
                                gameManager.settings.updateConfig(for: gameType) { config in
                                    config.usePrivateServer = newValue
                                    if newValue {
                                        config.useFireflyPS = false
                                        config.useMarch7thHoney = false
                                    }
                                }
                                gameManager.settings.save()
                            }
                        ))
                            .disabled(gameManager.settings.config(for: gameType).useFireflyPS)
                            .opacity(gameManager.settings.config(for: gameType).useFireflyPS ? 0.5 : 1.0)
                        
                        if gameManager.settings.config(for: gameType).useFireflyPS {
                            TextField("Private Server Address", text: .constant("127.0.0.1:21000"))
                                .disabled(true)
                                .foregroundStyle(.secondary)
                        } else if gameManager.settings.config(for: gameType).usePrivateServer {
                            TextField("Private Server Address", text: configBinding(\.privateServerAddress))
                        }
                        
                        if gameManager.settings.config(for: gameType).useFireflyPS {
                            TextField("Accept Run Code", text: configBinding(\.privateServerAcceptRun))
                            
                            HStack {
                                Button {
                                    let path = gameManager.proxyDirectoryPath
                                    // Ensure directory exists so Finder can open it
                                    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                } label: {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                                .controlSize(.small)
                                .buttonStyle(.bordered)
                                
                                Button {
                                    Task {
                                        do {
                                            try await gameManager.downloadProxyArchive()
                                        } catch {
                                            print("Failed to download proxy: \(error)")
                                        }
                                    }
                                } label: {
                                    Label("Download/Update Proxy", systemImage: "arrow.down.circle")
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                            }
                            
                            Text("Note: The proxy server is downloaded and run automatically on game launch. Click 'Show in Finder' to reveal the folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider().opacity(0.3)
                        
                        Toggle("Block Network (Anti-Cheat)", isOn: configBinding(\.blockNetwork))
                    }

                    settingsGroup("Advanced") {
                        Toggle("WINEMSYNC", isOn: configBinding(\.winemsync))
                        Toggle("Steam Emulation", isOn: configBinding(\.useSteamPatch))
                        Toggle("ReShade", isOn: configBinding(\.enableReShade))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 600)
        .liquidGlassCard(cornerRadius: 16)
        .presentationBackground(.clear)
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
