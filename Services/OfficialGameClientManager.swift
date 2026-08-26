import AppKit
import Foundation
import Observation

@Observable
final class OfficialGameClientManager {
    typealias IntegrityIssue = OfficialIntegrityIssue

    var isRunning = false
    var isDownloading = false
    var stage = ""
    var progress = 0.0
    var statusMessage = ""
    var latestVersion: String?
    var installedVersion: String?
    var updateAvailable = false
    var integrityIssues: [IntegrityIssue] = []

    var preDownloadVersion: String?
    var preDownloadAvailable = false
    var preDownloadReady = false
    var preDownloadStagedBytes: Int64 = 0
    var preDownloadTotalBytes: Int64 = 0

    var transferredBytes: Int64 = 0
    var transferTotalBytes: Int64 = 0
    var transferSpeed: Int64 = 0

    @ObservationIgnored private var latestManifest: GamePackageManifest?
    @ObservationIgnored private var resourceEntries: [OfficialResourceEntry] = []
    @ObservationIgnored private var resourceBaseURL: URL?
    @ObservationIgnored private var activeProcess: Process?
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var preDownloadIssue: String?
    @ObservationIgnored private var lastSampleTime = Date()
    @ObservationIgnored private var lastSampleBytes: Int64 = 0
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    private let api = GameServerAPI.shared
    private let patchManager: GameClientUpdateManager
    private let fm = FileManager.default

    init(patchManager: GameClientUpdateManager) {
        self.patchManager = patchManager
        // An orphaned curl keeps writing after the app quits, which corrupts the next resume.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activeProcess?.terminate()
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    var transferSummary: String {
        guard transferTotalBytes > 0 else { return "" }
        let done = Self.size(transferredBytes)
        let total = Self.size(transferTotalBytes)
        guard transferSpeed > 0 else { return "\(done) / \(total)" }
        return "\(done) / \(total) · \(Self.size(transferSpeed))/s"
    }

    var preDownloadSummary: String {
        guard preDownloadTotalBytes > 0, let preDownloadVersion else { return "" }
        let total = Self.size(preDownloadTotalBytes)
        if preDownloadReady { return "\(preDownloadVersion) ready · \(total)" }
        if preDownloadStagedBytes > 0 {
            return "\(Self.size(preDownloadStagedBytes)) of \(total) downloaded"
        }
        return "\(preDownloadVersion) available · \(total)"
    }

    var preDownloadActionLabel: String {
        preDownloadStagedBytes > 0
            ? "Resume Pre-download"
            : "Pre-download \(preDownloadVersion ?? "Update")"
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

    private var isUpdateAvailable: Bool {
        guard let installedVersion, let latestVersion else { return false }
        return GameVersionDetector.isNewer(latestVersion, than: installedVersion)
    }

    // getGamePackages stopped tracking major releases, so the sophon branch tag is authoritative.
    private func resolveLatest(
        region: OfficialGameRegion
    ) async throws -> (manifest: GamePackageManifest, branch: GameBranch?, tag: String?) {
        let manifest = try await api.fetchStarRailManifest(region: region)
        let branch = try? await api.fetchStarRailBranch(region: region)
        return (manifest, branch, branch?.main?.tag ?? manifest.main.major?.version)
    }

    // The sophon branch that can patch the installed build; pre-download wins while it is open.
    private func patchBranch(
        _ branch: GameBranch,
        installedVersion: String?,
        preDownloadOnly: Bool = false
    ) -> GameBranch.BranchInfo? {
        guard let installedVersion else { return nil }
        let candidates = preDownloadOnly ? [branch.pre_download] : [branch.pre_download, branch.main]
        return candidates.compactMap { $0 }.first {
            $0.tag != installedVersion && $0.diff_tags?.contains(installedVersion) == true
        }
    }

    func checkForUpdates(directory: String, region: OfficialGameRegion) async throws {
        begin(stage: "Checking official version")
        defer { finishRun() }

        refreshInstalledInfo(directory: directory)
        let latest = try await resolveLatest(region: region)
        latestManifest = latest.manifest
        latestVersion = latest.tag
        updateAvailable = isUpdateAvailable

        await refreshPreDownloadState(directory: directory, region: region, branch: latest.branch)

        if updateAvailable {
            let target = latestVersion ?? ""
            let staged = usablePreDownload(directory: directory, region: region, target: target)
            let sophon = latest.branch.flatMap { patchBranch($0, installedVersion: installedVersion) }
            let compatible = compatiblePatch(in: latest.manifest.main, installedVersion: installedVersion)
            if staged != nil {
                statusMessage = "Version \(target) is available and already pre-downloaded."
            } else {
                statusMessage = sophon == nil && compatible == nil
                    ? "Version \(installedVersion ?? "unknown") has no compatible incremental package."
                    : "Version \(target) is available."
            }
        } else if installedVersion == nil {
            statusMessage = "No installed client found."
        } else if preDownloadReady {
            statusMessage = "Pre-download for \(preDownloadVersion ?? "unknown") is complete."
        } else if preDownloadAvailable {
            statusMessage = "Pre-download for \(preDownloadVersion ?? "unknown") is open."
        } else if let preDownloadIssue {
            statusMessage = preDownloadIssue
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
        defer { finishRun() }

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
        installedVersion = GameVersionDetector.detectInstalledVersion(gameType: .honkaiStarRail, installDir: directory)
            ?? major.version
        // The full package can lag the live tag, so a fresh install may still owe a sophon patch.
        latestVersion = (try? await api.fetchStarRailBranch(region: region))?.main?.tag ?? major.version
        updateAvailable = isUpdateAvailable
        finish("Download complete.", onProgress: onProgress)
        return installedVersion ?? major.version
    }

    func updateGame(directory: String, region: OfficialGameRegion) async throws -> String {
        begin(stage: "Checking incremental packages")
        defer { finishRun() }

        refreshInstalledInfo(directory: directory)
        let latest = try await resolveLatest(region: region)
        let manifest = latest.manifest
        guard let target = latest.tag else { throw OfficialClientError.missingPackage }
        try patchManager.ensureToolsAvailable()

        if let staged = usablePreDownload(directory: directory, region: region, target: target) {
            try await applySophonPatch(staged.ledger, at: staged.root, to: directory)
        } else if let ledger = try? await refreshLedger(directory: directory, region: region, from: installedVersion ?? ""),
                  ledger.toVersion == target {
            let root = preDownloadRoot(in: directory, region: region, from: ledger.fromVersion)
            let remaining = max(0, ledger.totalBytes - stagedBytes(for: ledger, at: root))
            try checkAvailableSpace(at: directory, required: remaining + ledger.totalBytes * 2)
            try await fetchChunks(ledger, at: root)
            try await applySophonPatch(ledger, at: root, to: directory)
        } else {
            guard let major = manifest.main.major,
                  let patch = compatiblePatch(in: manifest.main, installedVersion: installedVersion),
                  let gamePackage = patch.game_pkgs.first else {
                throw OfficialClientError.noCompatiblePatch(installedVersion ?? "unknown")
            }

            var packages = [DownloadItem(url: gamePackage.url, size: gamePackage.byteCount, md5: gamePackage.md5)]
            var expanded = gamePackage.decompressedByteCount
            for language in installedAudioLanguages(at: directory) {
                if let audio = patch.audio_pkgs.first(where: { $0.language == language }) {
                    packages.append(DownloadItem(url: audio.url, size: audio.byteCount, md5: audio.md5))
                    expanded += audio.decompressedByteCount
                }
            }
            try checkAvailableSpace(at: directory, required: packages.reduce(0) { $0 + $1.size } + expanded)

            let name = "update-\(region.rawValue)-\(installedVersion ?? "unknown")-\(major.version)"
            pruneStagingDirectories(in: directory, prefix: "update-", keeping: name)
            let staging = try stagingDirectory(in: directory, name: name)
            let files = try await download(packages, to: staging)
            for file in files {
                stage = "Applying \(file.lastPathComponent)"
                try await patchManager.applyPatch(gameDir: directory, archivePath: file.path)
            }
            try? fm.removeItem(atPath: staging)
        }

        latestManifest = manifest
        latestVersion = target
        installedVersion = GameVersionDetector.detectInstalledVersion(gameType: .honkaiStarRail, installDir: directory)
            ?? target
        updateAvailable = isUpdateAvailable
        clearPreDownloadState()
        progress = 1
        statusMessage = "Updated to \(installedVersion ?? target)."
        return installedVersion ?? target
    }

    private func applySophonPatch(_ ledger: PreDownloadLedger, at root: String, to directory: String) async throws {
        try checkAvailableSpace(at: directory, required: ledger.totalBytes * 2)
        for (index, category) in ledger.categories.enumerated() {
            stage = "Applying \(category.matchingField) data"
            progress = Double(index) / Double(ledger.categories.count)
            try await patchManager.applyPatchDirectory(
                gameDir: directory,
                patchDirectory: root + "/" + category.id
            )
            // patch-cli consumes ldiff/ but leaves the manifest it moved in.
            try? fm.removeItem(atPath: directory + "/manifest")
            try? fm.removeItem(atPath: directory + "/ldiff")
        }
        try? fm.removeItem(atPath: root)
    }

    // MARK: - Pre-download

    func preDownload(directory: String, region: OfficialGameRegion) async throws -> String {
        begin(stage: "Preparing pre-download")
        // Cancelling throws, so recompute from disk on the way out to show what is already staged.
        var staged: (root: String, ledger: PreDownloadLedger)?
        defer {
            if let staged {
                preDownloadStagedBytes = stagedBytes(for: staged.ledger, at: staged.root)
                preDownloadReady = isComplete(staged.ledger, at: staged.root)
                preDownloadAvailable = !preDownloadReady
            }
            finishRun()
        }

        refreshInstalledInfo(directory: directory)
        guard let installedVersion else { throw OfficialClientError.noPreDownload("unknown") }

        let ledger = try await refreshLedger(
            directory: directory,
            region: region,
            from: installedVersion,
            preDownloadOnly: true
        )
        let root = preDownloadRoot(in: directory, region: region, from: installedVersion)
        staged = (root, ledger)
        preDownloadVersion = ledger.toVersion
        preDownloadTotalBytes = ledger.totalBytes
        pruneStagingDirectories(in: directory, prefix: "predownload-", keeping: (root as NSString).lastPathComponent)
        pruneUnreferencedFiles(ledger, at: root)

        let remaining = max(0, ledger.totalBytes - stagedBytes(for: ledger, at: root))
        try checkAvailableSpace(at: directory, required: remaining + (1 << 30))
        try await fetchChunks(ledger, at: root)

        preDownloadVersion = ledger.toVersion
        preDownloadTotalBytes = ledger.totalBytes
        preDownloadStagedBytes = ledger.totalBytes
        preDownloadReady = true
        preDownloadAvailable = false
        progress = 1
        statusMessage = "Pre-download complete. \(ledger.toVersion) will install without downloading again."
        return ledger.toVersion
    }

    func cancelDownload() {
        cancelRequested = true
        activeProcess?.terminate()
    }

    private func fetchChunks(_ ledger: PreDownloadLedger, at root: String) async throws {
        let jobs = ledger.categories.flatMap { category in
            category.chunks.map { chunk in
                DownloadJob(
                    item: DownloadItem(
                        url: category.chunkURLPrefix + "/" + chunk.name + category.chunkURLSuffix,
                        size: chunk.size,
                        md5: chunk.md5
                    ),
                    destination: URL(fileURLWithPath: root + "/" + category.id + "/ldiff/" + chunk.name)
                )
            }
        }
        _ = try await run(jobs)
    }

    // Network state is best effort: a sophon outage must not break the ordinary update check.
    private func refreshPreDownloadState(
        directory: String,
        region: OfficialGameRegion,
        branch: GameBranch?
    ) async {
        clearPreDownloadState()
        preDownloadIssue = nil
        guard let installedVersion else { return }

        let root = preDownloadRoot(in: directory, region: region, from: installedVersion)
        var ledger: PreDownloadLedger?
        if branch?.pre_download != nil {
            do {
                ledger = try await refreshLedger(
                    directory: directory,
                    region: region,
                    from: installedVersion,
                    preDownloadOnly: true
                )
            } catch {
                if let issue = error as? OfficialClientError, case .noPreDownloadPatch = issue {
                    preDownloadIssue = issue.localizedDescription
                }
                ledger = loadLedger(at: root)
            }
        } else {
            // The window has closed, so only report bytes that are actually staged on disk.
            ledger = loadLedger(at: root)
            if let ledger, stagedBytes(for: ledger, at: root) == 0 { return }
        }
        guard let ledger, ledger.toVersion != installedVersion else { return }

        preDownloadVersion = ledger.toVersion
        preDownloadTotalBytes = ledger.totalBytes
        preDownloadStagedBytes = stagedBytes(for: ledger, at: root)
        preDownloadReady = isComplete(ledger, at: root)
        preDownloadAvailable = !preDownloadReady
        pruneStagingDirectories(in: directory, prefix: "predownload-", keeping: (root as NSString).lastPathComponent)
    }

    private func refreshLedger(
        directory: String,
        region: OfficialGameRegion,
        from installedVersion: String,
        preDownloadOnly: Bool = false
    ) async throws -> PreDownloadLedger {
        guard !installedVersion.isEmpty else { throw OfficialClientError.noPreDownload("unknown") }
        let branch = try await api.fetchStarRailBranch(region: region)
        let candidate = preDownloadOnly ? branch.pre_download : branch.main ?? branch.pre_download
        guard let pre = patchBranch(branch, installedVersion: installedVersion, preDownloadOnly: preDownloadOnly) else {
            guard let candidate, candidate.tag != installedVersion else {
                throw OfficialClientError.noPreDownload(installedVersion)
            }
            throw OfficialClientError.noPreDownloadPatch(installedVersion, candidate.tag)
        }

        let build = try await api.fetchSophonPatchBuild(region: region, branch: pre)
        let root = preDownloadRoot(in: directory, region: region, from: installedVersion)
        let fields = wantedFields(at: directory)
        if let cached = loadLedger(at: root),
           cached.buildId == build.build_id,
           cached.toVersion == pre.tag,
           Set(cached.categories.map(\.matchingField)) == Set(fields) {
            return cached
        }

        stage = "Reading pre-download manifest"
        var categories: [PreDownloadLedger.Category] = []
        for manifest in build.manifests where fields.contains(manifest.matching_field) {
            guard let manifestURL = manifest.manifestURL, let diff = manifest.diff_download else {
                throw OfficialClientError.invalidResponse
            }
            let categoryRoot = root + "/" + manifest.category_id
            try fm.createDirectory(atPath: categoryRoot + "/ldiff", withIntermediateDirectories: true)
            // The manifest checksum covers the decompressed bytes, so only its size is checked here.
            try await downloadFile(
                DownloadItem(url: manifestURL.absoluteString, size: manifest.manifest.byteCount, md5: ""),
                to: URL(fileURLWithPath: categoryRoot + "/manifest")
            )
            let chunks = try await parseChunks(
                at: categoryRoot,
                from: installedVersion,
                checksum: manifest.manifest.checksum
            )
            if let expected = manifest.stats?[installedVersion], expected.chunkCount > 0,
               expected.chunkCount != chunks.count {
                throw SophonManifestError.chunkListMismatch(parsed: chunks.count, expected: expected.chunkCount)
            }
            categories.append(
                PreDownloadLedger.Category(
                    id: manifest.category_id,
                    matchingField: manifest.matching_field,
                    chunkURLPrefix: diff.url_prefix,
                    chunkURLSuffix: diff.url_suffix ?? "",
                    chunks: chunks
                )
            )
        }
        guard !categories.isEmpty else { throw OfficialClientError.noPreDownload(installedVersion) }

        let ledger = PreDownloadLedger(
            region: region.rawValue,
            fromVersion: installedVersion,
            toVersion: pre.tag,
            buildId: build.build_id,
            categories: categories
        )
        try saveLedger(ledger, at: root)
        pruneUnreferencedFiles(ledger, at: root)
        return ledger
    }

    // The manifest stays zstd-compressed on disk because patch-cli decompresses it itself.
    private func parseChunks(at categoryRoot: String, from version: String, checksum: String?) async throws -> [SophonChunk] {
        let archive = categoryRoot + "/manifest.zst"
        let expanded = categoryRoot + "/manifest-expanded"
        try? fm.removeItem(atPath: archive)
        try? fm.removeItem(atPath: expanded)
        try fm.copyItem(atPath: categoryRoot + "/manifest", toPath: archive)
        defer {
            try? fm.removeItem(atPath: archive)
            try? fm.removeItem(atPath: expanded)
        }
        try patchManager.ensureToolsAvailable()
        let code = try await ProcessRunner.run(
            patchManager.sevenZipPath,
            arguments: ["x", archive, "-o\(expanded)", "-y"]
        )
        guard code == 0 else { throw SophonManifestError.malformed }
        let decompressed = expanded + "/manifest"
        if let checksum, !checksum.isEmpty {
            guard let actual = try? OfficialClientVerification.md5(decompressed),
                  actual.caseInsensitiveCompare(checksum) == .orderedSame else {
                throw SophonManifestError.malformed
            }
        }
        return try SophonManifestReader.chunks(inDecompressedManifestAt: decompressed, fromVersion: version)
    }

    private func usablePreDownload(
        directory: String,
        region: OfficialGameRegion,
        target: String
    ) -> (root: String, ledger: PreDownloadLedger)? {
        guard let installedVersion, !target.isEmpty else { return nil }
        let root = preDownloadRoot(in: directory, region: region, from: installedVersion)
        guard let ledger = loadLedger(at: root),
              ledger.toVersion == target,
              Set(ledger.categories.map(\.matchingField)) == Set(wantedFields(at: directory)),
              isComplete(ledger, at: root) else { return nil }
        return (root, ledger)
    }

    private func preDownloadRoot(in directory: String, region: OfficialGameRegion, from version: String) -> String {
        directory + "/.evernight-downloads/predownload-\(region.rawValue)-\(version)"
    }

    private func loadLedger(at root: String) -> PreDownloadLedger? {
        guard let data = fm.contents(atPath: root + "/ledger.json") else { return nil }
        return try? JSONDecoder().decode(PreDownloadLedger.self, from: data)
    }

    private func saveLedger(_ ledger: PreDownloadLedger, at root: String) throws {
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ledger)
        try data.write(to: URL(fileURLWithPath: root + "/ledger.json"), options: .atomic)
    }

    private func stagedBytes(for ledger: PreDownloadLedger, at root: String) -> Int64 {
        ledger.categories.reduce(0) { total, category in
            let directory = root + "/" + category.id + "/ldiff/"
            return total + category.chunks.reduce(0) { $0 + min(byteCount(at: directory + $1.name), $1.size) }
        }
    }

    private func isComplete(_ ledger: PreDownloadLedger, at root: String) -> Bool {
        guard !ledger.categories.isEmpty else { return false }
        for category in ledger.categories {
            guard fm.fileExists(atPath: root + "/" + category.id + "/manifest") else { return false }
            let directory = root + "/" + category.id + "/ldiff/"
            for chunk in category.chunks where byteCount(at: directory + chunk.name) != chunk.size {
                return false
            }
        }
        return true
    }

    private func wantedFields(at directory: String) -> [String] {
        ["game"] + installedAudioLanguages(at: directory)
    }

    private func clearPreDownloadState() {
        preDownloadVersion = nil
        preDownloadAvailable = false
        preDownloadReady = false
        preDownloadStagedBytes = 0
        preDownloadTotalBytes = 0
    }

    private func pruneStagingDirectories(in directory: String, prefix: String, keeping name: String?) {
        let root = directory + "/.evernight-downloads"
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return }
        for entry in entries where entry.hasPrefix(prefix) && entry != name {
            try? fm.removeItem(atPath: root + "/" + entry)
        }
    }

    // Chunk names are content addressed, so a re-cut build reuses whatever is still referenced.
    private func pruneUnreferencedFiles(_ ledger: PreDownloadLedger, at root: String) {
        let known = Set(ledger.categories.map(\.id))
        if let entries = try? fm.contentsOfDirectory(atPath: root) {
            for entry in entries where entry != "ledger.json" && !known.contains(entry) {
                try? fm.removeItem(atPath: root + "/" + entry)
            }
        }
        for category in ledger.categories {
            let directory = root + "/" + category.id + "/ldiff"
            let wanted = Set(category.chunks.map(\.name))
            guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for entry in entries where !wanted.contains(entry) {
                try? fm.removeItem(atPath: directory + "/" + entry)
            }
        }
    }

    // MARK: - Verification

    func verifyFiles(directory: String, region: OfficialGameRegion) async throws -> [IntegrityIssue] {
        begin(stage: "Loading official file list")
        defer { finishRun() }

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
        // Verification uses the shipped package list; it must not walk back a newer sophon tag.
        if latestVersion == nil { latestVersion = major.version }
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
        defer { finishRun() }

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
        defer { finishRun() }

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

    // MARK: - Download

    private struct DownloadItem {
        let url: String
        let size: Int64
        let md5: String
    }

    private struct DownloadJob {
        let item: DownloadItem
        let destination: URL
    }

    private func begin(stage: String) {
        isRunning = true
        self.stage = stage
        progress = 0
        statusMessage = ""
        cancelRequested = false
        transferredBytes = 0
        transferTotalBytes = 0
        transferSpeed = 0
        lastSampleBytes = 0
        lastSampleTime = Date()
    }

    private func finishRun() {
        isRunning = false
        isDownloading = false
    }

    private func finish(_ message: String, onProgress: (Double, String) -> Void) {
        progress = 1
        statusMessage = message
        onProgress(1, message)
    }

    private func compatiblePatch(
        in info: GamePackageManifest.PackageInfo?,
        installedVersion: String?
    ) -> GamePackageManifest.PackageVersion? {
        guard let installedVersion else { return nil }
        return info?.patches?.first(where: { $0.version == installedVersion })
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
        let jobs = try items.map { item -> DownloadJob in
            guard let url = URL(string: item.url) else { throw OfficialClientError.invalidResponse }
            return DownloadJob(
                item: item,
                destination: URL(fileURLWithPath: directory).appendingPathComponent(url.lastPathComponent)
            )
        }
        return try await run(jobs, onProgress: onProgress)
    }

    private func run(
        _ jobs: [DownloadJob],
        onProgress: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> [URL] {
        let total = jobs.reduce(0) { $0 + $1.item.size }
        transferTotalBytes = total
        var completed: Int64 = 0
        var files: [URL] = []

        for (index, job) in jobs.enumerated() {
            let message = "Downloading \(index + 1) of \(jobs.count): \(job.destination.lastPathComponent)"
            stage = message
            let base = completed
            try await downloadFile(job.item, to: job.destination) { [weak self] written in
                self?.publishTransfer(base + min(written, job.item.size), of: total, message: message, onProgress: onProgress)
            }
            completed += job.item.size
            publishTransfer(completed, of: total, message: message, onProgress: onProgress)
            files.append(job.destination)
        }
        return files
    }

    private func publishTransfer(
        _ done: Int64,
        of total: Int64,
        message: String,
        onProgress: @escaping (Double, String) -> Void
    ) {
        DispatchQueue.main.async {
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastSampleTime)
            if elapsed > 0.5 {
                self.transferSpeed = max(0, Int64(Double(done - self.lastSampleBytes) / elapsed))
                self.lastSampleTime = now
                self.lastSampleBytes = done
            }
            self.transferredBytes = done
            self.transferTotalBytes = total
            self.progress = total > 0 ? 0.95 * Double(done) / Double(total) : 0
            onProgress(self.progress, message)
        }
    }

    private func downloadFile(
        _ item: DownloadItem,
        to destination: URL,
        onBytes: ((Int64) -> Void)? = nil
    ) async throws {
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if isVerified(destination.path, item) {
            onBytes?(item.size)
            return
        }
        if byteCount(at: destination.path) > item.size {
            try? fm.removeItem(at: destination)
        }

        for attempt in 0..<2 {
            try checkCancelled()
            let code = try await runCurl(item.url, to: destination, onBytes: onBytes)
            try checkCancelled()
            if code == 0, isVerified(destination.path, item) {
                onBytes?(item.size)
                return
            }
            if attempt == 0 { try? fm.removeItem(at: destination) }
        }
        throw OfficialClientError.verificationFailed(destination.lastPathComponent)
    }

    private func runCurl(_ url: String, to destination: URL, onBytes: ((Int64) -> Void)?) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--fail", "--location", "--retry", "3", "--retry-delay", "5", "--retry-all-errors",
            "--speed-limit", "1024", "--speed-time", "60",
            "--continue-at", "-", "--output", destination.path, url,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // curl writes straight to the destination, so its size is an accurate resumable progress source.
        let monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let written = self?.byteCount(at: destination.path) else { continue }
                onBytes?(written)
            }
        }
        defer {
            monitor.cancel()
            activeProcess = nil
            isDownloading = false
        }
        return try await ProcessRunner.run(process) { [weak self] started in
            self?.activeProcess = started
            self?.isDownloading = true
        }
    }

    private func checkCancelled() throws {
        if cancelRequested { throw OfficialClientError.cancelled }
    }

    private func isVerified(_ path: String, _ item: DownloadItem) -> Bool {
        guard item.size > 0, byteCount(at: path) == item.size else { return false }
        guard !item.md5.isEmpty else { return true }
        stage = "Verifying \((path as NSString).lastPathComponent)"
        guard let actual = try? OfficialClientVerification.md5(path) else { return false }
        return actual.caseInsensitiveCompare(item.md5) == .orderedSame
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

    private func byteCount(at path: String) -> Int64 {
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              let number = attributes[.size] as? NSNumber else { return 0 }
        return number.int64Value
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

    fileprivate static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum OfficialClientError: LocalizedError {
    case invalidResponse
    case missingPackage
    case missingResourceList
    case noCompatiblePatch(String)
    case noPreDownload(String)
    case noPreDownloadPatch(String, String)
    case cancelled
    case verificationFailed(String)
    case extractionFailed(String)
    case insufficientSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The official server returned an invalid response."
        case .missingPackage: return "The official package list is incomplete."
        case .missingResourceList: return "The official file verification list is unavailable."
        case .noCompatiblePatch(let version): return "No incremental update is available for version \(version)."
        case .noPreDownload: return "No pre-download is open right now."
        case .noPreDownloadPatch(let installed, let target):
            return "Version \(installed) has no compatible incremental pre-download package for \(target)."
        case .cancelled: return "Download cancelled. Progress is kept and will resume."
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
