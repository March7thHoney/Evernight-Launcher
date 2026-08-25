import Foundation

// MARK: - Game Server API

actor GameServerAPI {
    static let shared = GameServerAPI()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    // Fetch launcher backgrounds/content
    func fetchGameBackground(for gameInfo: GameInfo) async throws -> GameInfo.LauncherContent {
        guard let url = URL(string: gameInfo.serverConfig.advURL) else {
            throw APIError.invalidResponse
        }
        let (data, _) = try await session.data(from: url)

        let response = try JSONDecoder().decode(
            HypConnectResponse<AllGameBasicInfoData>.self,
            from: data
        )

        guard let game = response.data.game_info_list.first(where: { $0.game.biz == gameInfo.type.bizId }),
              let bg = game.backgrounds.first else {
            throw APIError.gameNotFound(gameInfo.type.bizId)
        }

        return GameInfo.LauncherContent(
            backgroundURL: URL(string: bg.background.url),
            backgroundVideoURL: bg.video?.url.flatMap { URL(string: $0) },
            logoURL: nil,
            iconURL: bg.icon.flatMap { URL(string: $0.url) },
            themeURL: bg.theme?.url.flatMap { URL(string: $0) }
        )
    }

    // Fetch latest version info
    func fetchLatestVersion(for gameInfo: GameInfo) async throws -> GamePackageManifest {
        guard let url = URL(string: gameInfo.serverConfig.updateURL) else {
            throw APIError.invalidResponse
        }
        let (data, _) = try await session.data(from: url)

        let response = try JSONDecoder().decode(
            HypConnectResponse<GamePackagesData>.self,
            from: data
        )

        guard let game = response.data.game_packages.first(where: { $0.game.biz == gameInfo.type.bizId }) else {
            throw APIError.gameNotFound(gameInfo.type.bizId)
        }
        return game
    }

    func fetchStarRailManifest(region: OfficialGameRegion) async throws -> GamePackageManifest {
        let (data, response) = try await session.data(from: region.packageURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let result = try JSONDecoder().decode(HypConnectResponse<GamePackagesData>.self, from: data)
        guard result.retcode == 0,
              let game = result.data.game_packages.first(where: { $0.game.biz == region.bizId }) else {
            throw APIError.gameNotFound(region.bizId)
        }
        return game
    }

    // Sophon branch descriptor; carries the credentials the chunk API needs.
    func fetchStarRailBranch(region: OfficialGameRegion) async throws -> GameBranch {
        let (data, response) = try await session.data(from: region.branchURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let result = try JSONDecoder().decode(HypConnectResponse<GameBranchesData>.self, from: data)
        guard result.retcode == 0,
              let branch = result.data.game_branches.first(where: { $0.game.biz == region.bizId }) else {
            throw APIError.gameNotFound(region.bizId)
        }
        return branch
    }

    // getPatchBuild only answers POST with a JSON body; a GET returns HTTP 405.
    func fetchSophonPatchBuild(
        region: OfficialGameRegion,
        branch: GameBranch.BranchInfo
    ) async throws -> SophonPatchBuild {
        var components = "\(region.sophonBaseURL)/getPatchBuild"
        components += "?branch=\(branch.branch)&password=\(branch.password)"
        components += "&package_id=\(branch.package_id)&tag=\(branch.tag)"
        guard let url = URL(string: components) else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let result = try JSONDecoder().decode(HypConnectResponse<SophonPatchBuild>.self, from: data)
        guard result.retcode == 0 else { throw APIError.invalidResponse }
        return result.data
    }

    enum APIError: LocalizedError {
        case gameNotFound(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .gameNotFound(let biz): return "Game not found: \(biz)"
            case .invalidResponse: return "Invalid server response"
            }
        }
    }
}
