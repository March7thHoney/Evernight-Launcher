import Foundation

// MARK: - Game Config (Config per game — full feature set)

struct GameConfig: Codable, Equatable {
    var gameType: GameType
    var installDirectory: String?
    var textLanguage: String = "en"
    var installedVersion: String?
    var officialRegion: OfficialGameRegion = .mainlandChina

    // Wine settings
    var useGlobalWineSettings: Bool = true
    var wineSourceMode: WineSourceMode = .github
    var customWinePath: String = ""
    var wineDistribution: String = WineManager.defaultDistribution.id // Default is Stable
    var retinaMode: Bool = true         // retinaMode support
    var leftCommandIsCtrl: Bool = true  // map Left Command to Control

    // Graphics settings
    var enableDXMT: Bool = true
    var installedDXMTVersion: String?
    var metalHUD: Bool = false
    var enableHDR: Bool = false

    // Resolution settings
    var customResolution: Bool = false
    var resolutionWidth: Int = 1920
    var resolutionHeight: Int = 1080

    // Private Server Settings
    var useMarch7thHoney: Bool = true
    var march7thHoneyAddress: String = "127.0.0.1:21000"
    var march7thServerPreset: March7thServerPreset = .local
    var customProxyPath: String = ""

    // Patch settings
    var useSteamPatch: Bool = false     // Steam emulation DLLs
    var enableReShade: Bool = false
    var workaround3: Bool = false       // workaround3 tag disable

    // DXMT environment
    var winemsync: Bool = true          // WINEMSYNC=1
    var alwaysReleaseCursor: Bool = false

    // Pre-download flag
    var predownloadedAll: Bool = false

    // March7thHoney server choice; the dropdown sets a preset, custom stores a full URL in march7thHoneyAddress.
    enum March7thServerPreset: String, Codable, CaseIterable, Identifiable {
        case hoyotoon, local, custom
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .hoyotoon: return "hoyotoon (Online)"
            case .local: return "Local Server"
            case .custom: return "Custom URL"
            }
        }
    }

    // The full target URL (scheme matters: https → real TLS) the proxy forwards March7thHoney traffic to.
    var march7thHoneyTargetURL: String {
        switch march7thServerPreset {
        case .hoyotoon: return "https://march7th.hoyotoon.com"
        case .local: return "http://127.0.0.1:21000"
        case .custom:
            let v = march7thHoneyAddress.trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? "http://127.0.0.1:21000" : v
        }
    }

    var installURL: URL? {
        guard let dir = installDirectory else { return nil }
        return URL(fileURLWithPath: dir)
    }

    // Any mode that needs the redirect proxy started before launch.
    var requiresRedirectProxy: Bool { useMarch7thHoney }

    // The dispatch upstream the proxy redirects to (full URL for March7thHoney so firefly keeps the scheme).
    var proxyRedirectHost: String {
        if useMarch7thHoney { return march7thHoneyTargetURL }
        return "127.0.0.1:21000"
    }

    // MARK: - Codable & Initializers
    
    enum CodingKeys: String, CodingKey {
        case gameType, installDirectory, textLanguage, installedVersion, officialRegion
        case useGlobalWineSettings, wineSourceMode, customWinePath, wineDistribution, retinaMode, leftCommandIsCtrl
        case enableDXMT, installedDXMTVersion, metalHUD, enableHDR
        case customResolution, resolutionWidth, resolutionHeight
        case useMarch7thHoney, march7thHoneyAddress, march7thServerPreset, customProxyPath
        case useSteamPatch, enableReShade, workaround3
        case winemsync, alwaysReleaseCursor
        case predownloadedAll
    }

    init(gameType: GameType) {
        self.gameType = gameType
        self.installDirectory = nil
        self.textLanguage = "en"
        self.installedVersion = nil
        self.officialRegion = .mainlandChina
        self.useGlobalWineSettings = true
        self.wineSourceMode = .github
        self.customWinePath = ""
        self.wineDistribution = WineManager.defaultDistribution.id
        self.retinaMode = true
        self.leftCommandIsCtrl = true
        self.enableDXMT = true
        self.installedDXMTVersion = nil
        self.metalHUD = false
        self.enableHDR = false
        self.customResolution = false
        self.resolutionWidth = 1920
        self.resolutionHeight = 1080
        self.useMarch7thHoney = true
        self.march7thHoneyAddress = "127.0.0.1:21000"
        self.march7thServerPreset = .local
        self.customProxyPath = ""
        self.useSteamPatch = false
        self.enableReShade = false
        self.workaround3 = false
        self.winemsync = true
        self.alwaysReleaseCursor = false
        self.predownloadedAll = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.gameType = try container.decode(GameType.self, forKey: .gameType)
        self.installDirectory = try container.decodeIfPresent(String.self, forKey: .installDirectory)
        self.textLanguage = try container.decodeIfPresent(String.self, forKey: .textLanguage) ?? "en"
        self.installedVersion = try container.decodeIfPresent(String.self, forKey: .installedVersion)
        self.officialRegion = try container.decodeIfPresent(OfficialGameRegion.self, forKey: .officialRegion) ?? .mainlandChina
        
        self.useGlobalWineSettings = try container.decodeIfPresent(Bool.self, forKey: .useGlobalWineSettings) ?? true
        self.wineSourceMode = try container.decodeIfPresent(WineSourceMode.self, forKey: .wineSourceMode) ?? .github
        self.customWinePath = try container.decodeIfPresent(String.self, forKey: .customWinePath) ?? ""
        self.wineDistribution = try container.decodeIfPresent(String.self, forKey: .wineDistribution) ?? WineManager.defaultDistribution.id
        self.retinaMode = try container.decodeIfPresent(Bool.self, forKey: .retinaMode) ?? true
        self.leftCommandIsCtrl = try container.decodeIfPresent(Bool.self, forKey: .leftCommandIsCtrl) ?? true
        
        self.enableDXMT = try container.decodeIfPresent(Bool.self, forKey: .enableDXMT) ?? true
        self.installedDXMTVersion = try container.decodeIfPresent(String.self, forKey: .installedDXMTVersion)
        self.metalHUD = try container.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        self.enableHDR = try container.decodeIfPresent(Bool.self, forKey: .enableHDR) ?? false
        
        self.customResolution = try container.decodeIfPresent(Bool.self, forKey: .customResolution) ?? false
        self.resolutionWidth = try container.decodeIfPresent(Int.self, forKey: .resolutionWidth) ?? 1920
        self.resolutionHeight = try container.decodeIfPresent(Int.self, forKey: .resolutionHeight) ?? 1080

        self.useMarch7thHoney = try container.decodeIfPresent(Bool.self, forKey: .useMarch7thHoney) ?? true
        self.march7thHoneyAddress = try container.decodeIfPresent(String.self, forKey: .march7thHoneyAddress) ?? "127.0.0.1:21000"
        self.march7thServerPreset = try container.decodeIfPresent(March7thServerPreset.self, forKey: .march7thServerPreset) ?? .local
        self.customProxyPath = try container.decodeIfPresent(String.self, forKey: .customProxyPath) ?? ""
        
        self.useSteamPatch = try container.decodeIfPresent(Bool.self, forKey: .useSteamPatch) ?? false
        self.enableReShade = try container.decodeIfPresent(Bool.self, forKey: .enableReShade) ?? false
        self.workaround3 = try container.decodeIfPresent(Bool.self, forKey: .workaround3) ?? false
        self.winemsync = try container.decodeIfPresent(Bool.self, forKey: .winemsync) ?? true
        self.alwaysReleaseCursor = try container.decodeIfPresent(Bool.self, forKey: .alwaysReleaseCursor) ?? false
        self.predownloadedAll = try container.decodeIfPresent(Bool.self, forKey: .predownloadedAll) ?? false
    }
}

// MARK: - Wine Source Mode

enum WineSourceMode: String, Codable, CaseIterable {
    case github = "github"   // Download / managed by the launcher
    case custom = "custom"   // User-supplied Wine folder

    var displayName: String {
        switch self {
        case .github: return "Download from GitHub"
        case .custom: return "Custom Folder"
        }
    }

    var icon: String {
        switch self {
        case .github: return "arrow.down.circle"
        case .custom: return "folder"
        }
    }
}

// MARK: - Launcher Settings

struct LauncherSettings: Codable {
    var selectedGame: GameType = .honkaiStarRail
    var gameConfigs: [GameType: GameConfig] = [:]
    var language: String = "en"

    // Wine global settings
    var selectedWineDistribution: String = WineManager.defaultDistribution.id
    var wineSourceMode: WineSourceMode = .github
    var customWinePath: String = ""     // Path to Wine folder when mode == .custom
    var enableMountedVolumeCompatibility: Bool = false

    func config(for game: GameType) -> GameConfig {
        gameConfigs[game] ?? GameConfig(gameType: game)
    }

    mutating func updateConfig(for game: GameType, _ update: (inout GameConfig) -> Void) {
        if gameConfigs[game] == nil {
            gameConfigs[game] = GameConfig(gameType: game)
        }
        update(&gameConfigs[game]!)
    }

    // MARK: - Codable Custom Setup
    
    enum CodingKeys: String, CodingKey {
        case selectedGame
        case gameConfigs
        case language
        case selectedWineDistribution
        case wineSourceMode
        case customWinePath
        case enableMountedVolumeCompatibility
    }

    init() {
        self.selectedGame = .honkaiStarRail
        self.gameConfigs = [:]
        self.language = "en"
        self.selectedWineDistribution = WineManager.defaultDistribution.id
        self.wineSourceMode = .github
        self.customWinePath = ""
        self.enableMountedVolumeCompatibility = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedGame = try container.decodeIfPresent(GameType.self, forKey: .selectedGame) ?? .honkaiStarRail
        self.gameConfigs = try container.decodeIfPresent([GameType: GameConfig].self, forKey: .gameConfigs) ?? [:]
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        self.selectedWineDistribution = try container.decodeIfPresent(String.self, forKey: .selectedWineDistribution) ?? WineManager.defaultDistribution.id
        self.wineSourceMode = try container.decodeIfPresent(WineSourceMode.self, forKey: .wineSourceMode) ?? .github
        self.customWinePath = try container.decodeIfPresent(String.self, forKey: .customWinePath) ?? ""
        self.enableMountedVolumeCompatibility = try container.decodeIfPresent(Bool.self, forKey: .enableMountedVolumeCompatibility) ?? false
    }

    // MARK: - Persistence

    private static let storageKey = "kafka_launcher_settings"

    static func load() -> LauncherSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var settings = try? JSONDecoder().decode(LauncherSettings.self, from: data) else {
            return LauncherSettings()
        }
        // Migrate old Wine distribution IDs
        if !WineManager.distributions.contains(where: { $0.id == settings.selectedWineDistribution }) {
            settings.selectedWineDistribution = WineManager.defaultDistribution.id
            settings.save()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
