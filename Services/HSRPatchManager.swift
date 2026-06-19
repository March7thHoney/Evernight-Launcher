import Foundation

// MARK: - HSR-Patch Manager

// Provisions the bundled HSR-Patch (HSRLauncher.exe + CyreneHook.dll from HSRPatch/) plus jadeite's game_payload into the managed dir for the March7thHoney login redirect.
struct HSRPatchManager {
    static let patchPath = WineManager.basePath + "/hsrpatch"
    static let launcherExe = patchPath + "/HSRLauncher.exe"

    // Files shipped inside the app bundle.
    private static let bundledFiles = ["HSRLauncher.exe", "CyreneHook.dll"]

    // Copy the bundled patch + jadeite's game_payload into the managed dir; call after jadeite is ensured.
    static func ensureAvailable() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: patchPath, withIntermediateDirectories: true)

        for name in bundledFiles {
            guard let src = Bundle.main.resourceURL?.appendingPathComponent(name).path,
                  fm.fileExists(atPath: src) else {
                throw HSRPatchError.missingBundledResource(name)
            }
            try copyIfDifferent(from: src, to: patchPath + "/" + name)
        }

        let gamePayload = JadeiteManager.jadeitePath + "/game_payload.dll"
        guard fm.fileExists(atPath: gamePayload) else {
            throw HSRPatchError.missingGamePayload
        }
        try copyIfDifferent(from: gamePayload, to: patchPath + "/game_payload.dll")
    }

    private static func copyIfDifferent(from src: String, to dst: String) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst) {
            let srcSize = (try? fm.attributesOfItem(atPath: src))?[.size] as? Int
            let dstSize = (try? fm.attributesOfItem(atPath: dst))?[.size] as? Int
            // Same size isn't enough (a rebuild can be same-size, different content); compare bytes, size fast-rejects the common case.
            if srcSize != nil, srcSize == dstSize, fm.contentsEqual(atPath: src, andPath: dst) { return }
            try? fm.removeItem(atPath: dst)
        }
        try fm.copyItem(atPath: src, toPath: dst)
    }
}

enum HSRPatchError: LocalizedError {
    case missingBundledResource(String)
    case missingGamePayload

    var errorDescription: String? {
        switch self {
        case .missingBundledResource(let name):
            return "Bundled HSR-Patch resource not found in app: \(name)"
        case .missingGamePayload:
            return "game_payload.dll not found in jadeite folder; ensure jadeite first."
        }
    }
}
