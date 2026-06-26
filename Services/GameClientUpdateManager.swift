import Foundation
import Observation

// MARK: - Game Client Update Manager

// Applies a local ldiff/hdiff patch archive by driving the bundled patch-cli; hpatchz + 7zz are bundled too so it needs no homebrew.

@Observable
class GameClientUpdateManager {
    var isRunning = false
    var stage = ""
    var progress: Double = 0
    var statusMessage = ""

    // Managed dir holding patch-cli plus bin/{hpatchz,7zz}; also where patch-cli extracts to (temp/).
    static let toolDir = WineManager.basePath + "/patchtool"

    // Bundle resource name → deployed path. hpatchz/7zz are renamed to what patch-cli's constant pkg expects.
    private var toolMapping: [(bundled: String, dst: String)] {
        [("patch-cli", Self.toolDir + "/patch-cli"),
         ("hpatchz_macos", Self.toolDir + "/bin/hpatchz"),
         ("7zz_macos", Self.toolDir + "/bin/7zz")]
    }

    func applyPatch(gameDir: String, archivePath: String) async throws {
        await MainActor.run {
            isRunning = true
            stage = "Preparing"
            progress = 0
            statusMessage = ""
        }
        defer { Task { @MainActor in self.isRunning = false } }

        try ensureToolsAvailable()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.toolDir + "/patch-cli")
        process.arguments = ["-game", gameDir, "-patch", archivePath]
        var env = ProcessInfo.processInfo.environment
        env["PATCHTOOL_DATA_DIR"] = Self.toolDir
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        var sawError: String?
        for try await line in pipe.fileHandleForReading.bytes.lines {
            if line.hasPrefix("RESULT ERR ") {
                sawError = String(line.dropFirst("RESULT ERR ".count))
            } else if line == "RESULT OK" {
                continue
            } else {
                await applyProgressLine(line)
            }
        }

        process.waitUntilExit()
        if process.terminationStatus != 0 || sawError != nil {
            throw GameClientUpdateError.patchFailed(sawError ?? "patch process exited with code \(process.terminationStatus)")
        }
    }

    // MARK: - Progress protocol

    @MainActor
    private func applyProgressLine(_ line: String) {
        if line.hasPrefix("STAGE ") {
            stage = String(line.dropFirst(6))
            progress = 0
        } else if line.hasPrefix("PROGRESS ") {
            let parts = line.dropFirst(9).split(separator: " ")
            if parts.count == 2, let current = Double(parts[0]), let total = Double(parts[1]), total > 0 {
                progress = min(1, current / total)
            }
        } else if line.hasPrefix("MSG ") {
            statusMessage = String(line.dropFirst(4))
        }
    }

    // MARK: - Tool provisioning

    // Copy the three bundled binaries out of the app into the managed dir, then mark executable + ad-hoc sign.
    private func ensureToolsAvailable() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: Self.toolDir + "/bin", withIntermediateDirectories: true)

        for tool in toolMapping {
            guard let src = Bundle.main.resourceURL?.appendingPathComponent(tool.bundled).path,
                  fm.fileExists(atPath: src) else {
                throw GameClientUpdateError.missingTool(tool.bundled)
            }
            let copied = try copyIfDifferent(from: src, to: tool.dst)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.dst)
            if copied { adhocSignBinary(tool.dst) }
        }
    }

    @discardableResult
    private func copyIfDifferent(from src: String, to dst: String) throws -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst) {
            let srcSize = (try? fm.attributesOfItem(atPath: src))?[.size] as? Int
            let dstSize = (try? fm.attributesOfItem(atPath: dst))?[.size] as? Int
            if srcSize != nil, srcSize == dstSize, fm.contentsEqual(atPath: src, andPath: dst) { return false }
            try? fm.removeItem(atPath: dst)
        }
        try fm.copyItem(atPath: src, toPath: dst)
        return true
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
}

enum GameClientUpdateError: LocalizedError {
    case missingTool(String)
    case patchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTool(let name):
            return "Bundled patch tool not found in app: \(name)"
        case .patchFailed(let msg):
            return "Update failed: \(msg)"
        }
    }
}
