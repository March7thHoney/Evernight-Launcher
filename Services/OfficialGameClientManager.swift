import Foundation
import Observation

@Observable
final class OfficialGameClientManager {
    typealias IntegrityIssue = OfficialIntegrityIssue

    var isRunning = false
    var stage = ""
    var progress = 0.0
    var statusMessage = ""
    var latestVersion: String?
    var installedVersion: String?
    var updateAvailable = false
    var integrityIssues: [IntegrityIssue] = []

    @ObservationIgnored private var latestManifest: GamePackageManifest?
    @ObservationIgnored private var resourceEntries: [OfficialResourceEntry] = []
    @ObservationIgnored private var resourceBaseURL: URL?

    private let api = GameServerAPI.shared
    private let patchManager: GameClientUpdateManager
    private let fm = FileManager.default

    init(patchManager: GameClientUpdateManager) {
        self.patchManager = patchManager
    }

    static func detectRegion(at directory: String) -> OfficialGameRegion? {
        OfficialClientVerification.detectRegion(at: directory)
    }

    func refreshInstalledInfo(directory: String?) {
        guard let directory else {
            installedVersion = nil
            return
        }
        installedVersion = GameVersionDetector.detectInstalledVersion(
            gameType: .honkaiStarRail,
            installDir: directory
        )
    }

    func checkForUpdates(directory: String, region: OfficialGameRegion) async throws {
        begin(stage: "Checking official version")
        defer { isRunning = false }

        refreshInstalledInfo(directory: directory)
        let manifest = try await api.fetchStarRailManifest(region: region)
        latestManifest = manifest
        latestVersion = manifest.main.major?.version
        updateAvailable = installedVersion != nil && latestVersion != nil && installedVersion != latestVersion

        if updateAvailable {
            let compatible = compatiblePatch(in: manifest, installedVersion: installedVersion)
            statusMessage = compatible == nil
                ? "Version \(installedVersion ?? "unknown") has no compatible incremental package."
                : "Version \(latestVersion ?? "unknown") is available."
        } else if installedVersion == nil {
            statusMessage = "No installed client found."
        } else {
            statusMessage = "The game is up to date."
        }
        progress = 1
    }

    func downloadGame(
        to directory: String,
        region: OfficialGameRegion,
        onProgress: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> String {
        begin(stage: "Fetching official download manifest")
        defer { isRunning = false }

        let manifest = try await api.fetchStarRailManifest(region: region)
        guard let major = manifest.main.major,
              let voice = major.audio_pkgs.first(where: { $0.language == "zh-cn" }) else {
            throw OfficialClientError.missingPackage
        }

        let packages = major.game_pkgs.map {
            DownloadItem(url: $0.url, size: $0.byteCount, md5: $0.md5)
        } + [DownloadItem(url: voice.url, size: voice.byteCount, md5: voice.md5)]
        let compressedSize = packages.reduce(0) { $0 + $1.size }
        try checkAvailableSpace(at: directory, required: compressedSize * 2)

        let staging = try stagingDirectory(in: directory, name: "install-\(region.rawValue)-\(major.version)")
        let files = try await download(packages, to: staging, onProgress: onProgress)

        guard let firstGamePart = files.first, let voiceArchive = files.last else {
            throw OfficialClientError.missingPackage
        }
        try patchManager.ensureToolsAvailable()
        try await extract(firstGamePart, to: directory, label: "Extracting game", onProgress: onProgress)
        try await extract(voiceArchive, to: directory, label: "Extracting Chinese voice", onProgress: onProgress)
        try? fm.removeItem(atPath: staging)

        latestManifest = manifest
        latestVersion = major.version
        installedVersion = GameVersionDetector.detectInstalledVersion(gameType: .honkaiStarRail, installDir: directory)
            ?? major.version
        updateAvailable = false
        finish("Download complete.", onProgress: onProgress)
        return installedVersion ?? major.version
    }

    func updateGame(directory: String, region: OfficialGameRegion) async throws -> String {
        begin(stage: "Checking incremental packages")
        defer { isRunning = false }

        refreshInstalledInfo(directory: directory)
        let manifest = try await api.fetchStarRailManifest(region: region)
        guard let major = manifest.main.major,
              let patch = compatiblePatch(in: manifest, installedVersion: installedVersion),
              let gamePackage = patch.game_pkgs.first else {
            throw OfficialClientError.noCompatiblePatch(installedVersion ?? "unknown")
        }

        var packages = [DownloadItem(url: gamePackage.url, size: gamePackage.byteCount, md5: gamePackage.md5)]
        for language in installedAudioLanguages(at: directory) {
            if let audio = patch.audio_pkgs.first(where: { $0.language == language }) {
                packages.append(DownloadItem(url: audio.url, size: audio.byteCount, md5: audio.md5))
            }
        }

        let staging = try stagingDirectory(in: directory, name: "update-\(installedVersion ?? "unknown")-\(major.version)")
        let files = try await download(packages, to: staging)
        for file in files {
            stage = "Applying \(file.lastPathComponent)"
            try await patchManager.applyPatch(gameDir: directory, archivePath: file.path)
        }
        try? fm.removeItem(atPath: staging)

        latestManifest = manifest
        latestVersion = major.version
        installedVersion = GameVersionDetector.detectInstalledVersion(gameType: .honkaiStarRail, installDir: directory)
            ?? major.version
        updateAvailable = installedVersion != latestVersion
        progress = 1
        statusMessage = "Updated to \(installedVersion ?? major.version)."
        return installedVersion ?? major.version
    }

    func verifyFiles(directory: String, region: OfficialGameRegion) async throws -> [IntegrityIssue] {
        begin(stage: "Loading official file list")
        defer { isRunning = false }

        let manifest = try await api.fetchStarRailManifest(region: region)
        guard let major = manifest.main.major,
              let value = major.res_list_url,
              let baseURL = URL(string: value) else {
            throw OfficialClientError.missingResourceList
        }
        let listURL = baseURL.appendingPathComponent("pkg_version")
        let (data, response) = try await URLSession.shared.data(from: listURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OfficialClientError.invalidResponse
        }
        let entries = try OfficialClientVerification.decodeResourceList(data)
        let selectedCount = OfficialClientVerification.selectedEntries(from: entries).count
        stage = "Checking \(selectedCount) essential files"
        progress = 0.05

        let issues = try await Task.detached(priority: .utility) { [weak self] in
            try OfficialClientVerification.scan(directory: directory, entries: entries) { current, total in
                DispatchQueue.main.async {
                    self?.progress = 0.05 + 0.95 * Double(current) / Double(max(total, 1))
                    self?.stage = "Checking essential files \(current) of \(total)"
                }
            }
        }.value

        latestManifest = manifest
        latestVersion = major.version
        resourceEntries = entries
        resourceBaseURL = baseURL
        integrityIssues = issues
        progress = 1
        statusMessage = issues.isEmpty
            ? "Quick verification passed for \(selectedCount) essential and representative files."
            : "Quick verification found \(issues.count) missing or damaged files."
        return issues
    }

    func repairFiles(directory: String, region: OfficialGameRegion) async throws {
        if resourceEntries.isEmpty || resourceBaseURL == nil || integrityIssues.isEmpty {
            _ = try await verifyFiles(directory: directory, region: region)
        }
        guard let baseURL = resourceBaseURL else { throw OfficialClientError.missingResourceList }
        let issues = integrityIssues
        guard !issues.isEmpty else { return }

        begin(stage: "Repairing official files")
        defer { isRunning = false }

        for (index, issue) in issues.enumerated() {
            stage = "Repairing \(issue.path)"
            progress = Double(index) / Double(issues.count)
            let target = URL(fileURLWithPath: directory).appendingPathComponent(issue.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = target.deletingLastPathComponent()
                .appendingPathComponent(".\(target.lastPathComponent).evernight-repair.part")
            let remote = issue.path.split(separator: "/").reduce(baseURL) {
                $0.appendingPathComponent(String($1))
            }
            try await downloadFile(
                DownloadItem(url: remote.absoluteString, size: issue.expectedSize, md5: issue.expectedMD5),
                to: temporary
            )
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: temporary)
            } else {
                try fm.moveItem(at: temporary, to: target)
            }
        }

        integrityIssues = []
        progress = 1
        statusMessage = "Repair complete. Run verification again to confirm."
    }

    func reinstallChineseVoice(directory: String, region: OfficialGameRegion) async throws {
        begin(stage: "Fetching Chinese voice package")
        defer { isRunning = false }

        let manifest = try await api.fetchStarRailManifest(region: region)
        guard let major = manifest.main.major,
              let voice = major.audio_pkgs.first(where: { $0.language == "zh-cn" }) else {
            throw OfficialClientError.missingPackage
        }
        let staging = try stagingDirectory(in: directory, name: "voice-zh-cn-\(major.version)")
        let files = try await download(
            [DownloadItem(url: voice.url, size: voice.byteCount, md5: voice.md5)],
            to: staging
        )
        guard let archive = files.first else { throw OfficialClientError.missingPackage }
        try patchManager.ensureToolsAvailable()
        try await extract(archive, to: directory, label: "Installing Chinese voice")
        try? fm.removeItem(atPath: staging)
        progress = 1
        statusMessage = "Chinese voice reinstalled."
    }

    private struct DownloadItem {
        let url: String
        let size: Int64
        let md5: String
    }

    private func begin(stage: String) {
        isRunning = true
        self.stage = stage
        progress = 0
        statusMessage = ""
    }

    private func finish(_ message: String, onProgress: (Double, String) -> Void) {
        progress = 1
        statusMessage = message
        onProgress(1, message)
    }

    private func compatiblePatch(
        in manifest: GamePackageManifest,
        installedVersion: String?
    ) -> GamePackageManifest.PackageVersion? {
        guard let installedVersion else { return nil }
        return manifest.main.patches?.first(where: { $0.version == installedVersion })
    }

    private func stagingDirectory(in directory: String, name: String) throws -> String {
        let path = directory + "/.evernight-downloads/" + name
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func download(
        _ items: [DownloadItem],
        to directory: String,
        onProgress: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> [URL] {
        var files: [URL] = []
        for (index, item) in items.enumerated() {
            guard let url = URL(string: item.url) else { throw OfficialClientError.invalidResponse }
            let destination = URL(fileURLWithPath: directory).appendingPathComponent(url.lastPathComponent)
            let message = "Downloading \(index + 1) of \(items.count): \(url.lastPathComponent)"
            stage = message
            progress = Double(index) / Double(max(items.count, 1))
            onProgress(progress, message)
            try await downloadFile(item, to: destination)
            files.append(destination)
        }
        return files
    }

    private func downloadFile(_ item: DownloadItem, to destination: URL) async throws {
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path),
           try fileSize(destination.path) == item.size,
           try OfficialClientVerification.md5(destination.path).caseInsensitiveCompare(item.md5) == .orderedSame {
            return
        }
        if (try? fileSize(destination.path)) ?? 0 > item.size {
            try? fm.removeItem(at: destination)
        }

        for attempt in 0..<2 {
            let code = try await ProcessRunner.run(
                "/usr/bin/curl",
                arguments: [
                    "--fail", "--location", "--retry", "3", "--continue-at", "-",
                    "--output", destination.path, item.url,
                ]
            )
            if code == 0,
               (try? fileSize(destination.path)) == item.size,
               (try? OfficialClientVerification.md5(destination.path).caseInsensitiveCompare(item.md5)) == .orderedSame {
                return
            }
            if attempt == 0 { try? fm.removeItem(at: destination) }
        }
        throw OfficialClientError.verificationFailed(destination.lastPathComponent)
    }

    private func extract(
        _ archive: URL,
        to directory: String,
        label: String,
        onProgress: (Double, String) -> Void = { _, _ in }
    ) async throws {
        stage = label
        progress = 0.95
        onProgress(progress, label)
        let code = try await ProcessRunner.run(
            patchManager.sevenZipPath,
            arguments: ["x", archive.path, "-o\(directory)", "-y"]
        )
        guard code == 0 else { throw OfficialClientError.extractionFailed(archive.lastPathComponent) }
    }

    private func checkAvailableSpace(at directory: String, required: Int64) throws {
        let url = URL(fileURLWithPath: directory)
        if let available = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           available < required {
            throw OfficialClientError.insufficientSpace(required: required, available: available)
        }
    }

    private func fileSize(_ path: String) throws -> Int64 {
        let value = try fm.attributesOfItem(atPath: path)[.size]
        if let number = value as? NSNumber { return number.int64Value }
        throw OfficialClientError.invalidResponse
    }

    private func installedAudioLanguages(at directory: String) -> [String] {
        let path = directory + "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/AudioLangRedord.txt"
        guard let data = fm.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let value = object["AudioLang"]?.lowercased() else { return ["zh-cn"] }
        if value.contains("english") { return ["en-us"] }
        if value.contains("japanese") { return ["ja-jp"] }
        if value.contains("korean") { return ["ko-kr"] }
        return ["zh-cn"]
    }

}

enum OfficialClientError: LocalizedError {
    case invalidResponse
    case missingPackage
    case missingResourceList
    case noCompatiblePatch(String)
    case verificationFailed(String)
    case extractionFailed(String)
    case insufficientSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The official server returned an invalid response."
        case .missingPackage: return "The official package list is incomplete."
        case .missingResourceList: return "The official file verification list is unavailable."
        case .noCompatiblePatch(let version): return "No incremental update is available for version \(version)."
        case .verificationFailed(let file): return "MD5 or size verification failed for \(file)."
        case .extractionFailed(let file): return "Failed to extract \(file)."
        case .insufficientSpace(let required, let available):
            return "Not enough disk space. Required \(Self.size(required)), available \(Self.size(available))."
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
