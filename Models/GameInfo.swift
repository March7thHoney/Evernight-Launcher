import Foundation

enum OfficialGameRegion: String, Codable, CaseIterable, Identifiable {
    case mainlandChina
    case global

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainlandChina: return "Mainland China"
        case .global: return "Global"
        }
    }

    var bizId: String {
        switch self {
        case .mainlandChina: return "hkrpg_cn"
        case .global: return "hkrpg_global"
        }
    }

    var packageURL: URL {
        switch self {
        case .mainlandChina:
            return URL(string: "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1&game_ids%5B%5D=64kMb5iAWu&language=zh-cn")!
        case .global:
            return URL(string: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8&game_ids%5B%5D=4ziysqXOQ8")!
        }
    }
}

// MARK: - Game Info (Server configuration + HoyoConnect data)

struct GameInfo: Identifiable {
    let type: GameType
    let serverConfig: ServerConfig
    var launcherContent: LauncherContent?

    var id: String { type.rawValue }

    // Server settings structure
    struct ServerConfig {
        let updateURL: String
        let advURL: String
        let channelId: Int
        let subchannelId: Int
        let cps: String
    }

    // HoyoConnect Game Background assets
    struct LauncherContent {
        var backgroundURL: URL?
        var backgroundVideoURL: URL?
        var logoURL: URL?
        var iconURL: URL?
        var themeURL: URL?
    }
}

// MARK: - API Response Models

struct HypConnectResponse<T: Decodable>: Decodable {
    let retcode: Int
    let message: String
    let data: T
}

struct GamePackagesData: Decodable {
    let game_packages: [GamePackageManifest]
}

struct GamePackageManifest: Decodable {
    let game: GameId
    let main: PackageInfo
    let pre_download: PackageInfo?

    struct PackageInfo: Decodable {
        let major: PackageVersion?
        let patches: [PackageVersion]?
    }

    struct PackageVersion: Decodable {
        let version: String
        let res_list_url: String?
        let game_pkgs: [PackageFile]
        let audio_pkgs: [AudioPackage]
    }

    struct PackageFile: Decodable {
        let url: String
        let size: String
        let md5: String
        let decompressed_size: String?

        var byteCount: Int64 { Int64(size) ?? 0 }
        var decompressedByteCount: Int64 { Int64(decompressed_size ?? "") ?? 0 }
    }

    struct AudioPackage: Decodable {
        let language: String
        let url: String
        let size: String
        let md5: String
        let decompressed_size: String?

        var byteCount: Int64 { Int64(size) ?? 0 }
        var decompressedByteCount: Int64 { Int64(decompressed_size ?? "") ?? 0 }
    }
}

struct GameId: Decodable {
    let biz: String
    let id: String
}

struct AllGameBasicInfoData: Decodable {
    let game_info_list: [GameBasicInfo]
}

struct GameBasicInfo: Decodable {
    let game: GameId
    let backgrounds: [GameBackground]
}

struct GameBackground: Decodable {
    let id: String
    let background: BackgroundImage
    let icon: BackgroundIcon?
    let video: BackgroundVideo?
    let theme: BackgroundTheme?

    struct BackgroundImage: Decodable {
        let url: String
        let link: String?
    }

    struct BackgroundIcon: Decodable {
        let url: String
        let hover_url: String?
        let link: String?
    }

    struct BackgroundVideo: Decodable {
        let url: String?
        let size: Int?
    }

    struct BackgroundTheme: Decodable {
        let url: String?
        let link: String?
    }
}

// MARK: - Predefined Server Configs

extension GameInfo {
    static let defaultGames: [GameInfo] = [
        GameInfo(
            type: .genshinImpact,
            serverConfig: ServerConfig(
                updateURL: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8&game_ids[]=gopR6Cufr3",
                advURL: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=VYTpXlbWo8&game_id=gopR6Cufr3",
                channelId: 1,
                subchannelId: 1,
                cps: "mihoyo"
            )
        ),
        GameInfo(
            type: .honkaiStarRail,
            serverConfig: ServerConfig(
                updateURL: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8&game_ids[]=4ziysqXOQ8",
                advURL: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=VYTpXlbWo8&game_id=4ziysqXOQ8",
                channelId: 1,
                subchannelId: 1,
                cps: "mihoyo"
            )
        ),
        GameInfo(
            type: .zenlessZoneZero,
            serverConfig: ServerConfig(
                updateURL: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8&game_ids[]=U5hbdsT9W7",
                advURL: "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=VYTpXlbWo8&game_id=U5hbdsT9W7",
                channelId: 1,
                subchannelId: 1,
                cps: "mihoyo"
            )
        ),
    ]
}
