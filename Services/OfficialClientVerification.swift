import CryptoKit
import Darwin
import Foundation

nonisolated struct OfficialResourceEntry: Decodable, Sendable {
    let remoteName: String
    let md5: String
    let fileSize: Int64
}

nonisolated struct OfficialIntegrityIssue: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case missing = "Missing"
        case sizeMismatch = "Size mismatch"
        case hashMismatch = "MD5 mismatch"
    }

    let path: String
    let expectedMD5: String
    let expectedSize: Int64
    let kind: Kind
    var id: String { path }
}

enum OfficialClientVerification {
    enum Error: Swift.Error {
        case invalidResponse
    }

    nonisolated static func detectRegion(at directory: String) -> OfficialGameRegion? {
        let fm = FileManager.default
        let executable = directory + "/StarRail.exe"
        let dataDirectory = directory + "/StarRail_Data"
        guard fm.fileExists(atPath: executable), fm.fileExists(atPath: dataDirectory) else { return nil }

        let appInfo = dataDirectory + "/app.info"
        if let data = fm.contents(atPath: appInfo),
           let contents = String(data: data, encoding: .utf8),
           let company = contents.split(whereSeparator: \.isNewline).first,
           String(company).trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("miHoYo") == .orderedSame {
            return .mainlandChina
        }

        let config = directory + "/config.ini"
        if let data = fm.contents(atPath: config),
           let contents = String(data: data, encoding: .utf8),
           contents.range(of: "cps=hyp_mihoyo", options: .caseInsensitive) != nil {
            return .mainlandChina
        }
        return .global
    }

    nonisolated static func decodeResourceList(_ data: Data) throws -> [OfficialResourceEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw Error.invalidResponse
        }
        let decoder = JSONDecoder()
        return try text.split(whereSeparator: \.isNewline).map {
            try decoder.decode(OfficialResourceEntry.self, from: Data($0.utf8))
        }
    }

    nonisolated static func scan(
        directory: String,
        entries: [OfficialResourceEntry],
        onProgress: ((Int, Int) -> Void)? = nil
    ) throws -> [OfficialIntegrityIssue] {
        let fm = FileManager.default
        let entries = selectedEntries(from: entries)
        var issues: [OfficialIntegrityIssue] = []
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 100) { onProgress?(index, entries.count) }
            let path = directory + "/" + entry.remoteName
            guard fm.fileExists(atPath: path) else {
                issues.append(OfficialIntegrityIssue(
                    path: entry.remoteName,
                    expectedMD5: entry.md5,
                    expectedSize: entry.fileSize,
                    kind: .missing
                ))
                continue
            }
            let attributes = try fm.attributesOfItem(atPath: path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            if size != entry.fileSize {
                issues.append(OfficialIntegrityIssue(
                    path: entry.remoteName,
                    expectedMD5: entry.md5,
                    expectedSize: entry.fileSize,
                    kind: .sizeMismatch
                ))
            } else if try md5(path).caseInsensitiveCompare(entry.md5) != .orderedSame {
                issues.append(OfficialIntegrityIssue(
                    path: entry.remoteName,
                    expectedMD5: entry.md5,
                    expectedSize: entry.fileSize,
                    kind: .hashMismatch
                ))
            }
        }
        onProgress?(entries.count, entries.count)
        return issues
    }

    nonisolated static func selectedEntries(from entries: [OfficialResourceEntry]) -> [OfficialResourceEntry] {
        let essential = entries.filter { isEssential($0.remoteName) }
        let essentialPaths = Set(essential.map(\.remoteName))
        let candidates = entries.filter {
            !essentialPaths.contains($0.remoteName)
                && $0.remoteName.hasPrefix("StarRail_Data/StreamingAssets/")
                && $0.fileSize > 0
                && $0.fileSize <= 8 * 1024 * 1024
        }
        let groups = Dictionary(grouping: candidates) { entry in
            entry.remoteName.split(separator: "/").dropFirst(2).first.map(String.init) ?? "Other"
        }
        let samples = groups.keys.sorted().flatMap { key -> [OfficialResourceEntry] in
            let group = groups[key, default: []].sorted { $0.remoteName < $1.remoteName }
            guard group.count > 1 else { return group }
            return [group[0], group[group.count / 2]]
        }
        return (essential + samples).sorted { $0.remoteName < $1.remoteName }
    }

    nonisolated private static func isEssential(_ path: String) -> Bool {
        let fixedPaths: Set<String> = [
            "GameAssembly.dll",
            "StarRail.exe",
            "UnityPlayer.dll",
            "config.ini",
            "StarRail_Data/app.info",
            "StarRail_Data/boot.config",
            "StarRail_Data/StreamingAssets/BinaryVersion.bytes",
            "StarRail_Data/StreamingAssets/ClientConfig.bytes",
            "StarRail_Data/StreamingAssets/DevConfig.bytes",
            "StarRail_Data/StreamingAssets/EarlyAccessInfo.json"
        ]
        if fixedPaths.contains(path) { return true }
        return path.hasPrefix("StarRail_Data/Plugins/x86_64/")
            && path.lowercased().hasSuffix(".dll")
    }

    nonisolated static func md5(_ path: String) throws -> String {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_NOCACHE, 1)

        let capacity = 1024 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 64)
        defer { buffer.deallocate() }
        var hasher = Insecure.MD5()
        while true {
            let count = read(descriptor, buffer, capacity)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
