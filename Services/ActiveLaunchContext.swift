import Foundation

private struct ActiveLaunchContext: Codable {
    let schemaVersion: Int
    let gameType: String
    let launchMode: String
    let wineBinary: String
    let winePrefix: String
    let gameDirectory: String
    let wineExecutable: String
    let wineEnvironment: [String: String]
    let createdAt: TimeInterval
}

enum ActiveLaunchContextManager {
    private static let directoryPath = WineManager.basePath + "/runtime"
    static let filePath = directoryPath + "/active-hsr-launch.json"
    private static let environmentKeys = ["WINEMSYNC", "WINEESYNC", "WINEDEBUG", "WINEDLLOVERRIDES"]

    static func publish(
        wineBinary: String,
        winePrefix: String,
        gameDirectory: String,
        wineExecutable: String,
        environment: [String: String]
    ) throws {
        let selectedEnvironment = environment.reduce(into: [String: String]()) { result, entry in
            if environmentKeys.contains(entry.key) {
                result[entry.key] = entry.value
            }
        }
        let context = ActiveLaunchContext(
            schemaVersion: 1,
            gameType: GameType.honkaiStarRail.rawValue,
            launchMode: "direct",
            wineBinary: wineBinary,
            winePrefix: winePrefix,
            gameDirectory: gameDirectory,
            wineExecutable: wineExecutable,
            wineEnvironment: selectedEnvironment,
            createdAt: Date().timeIntervalSince1970
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(context).write(to: URL(fileURLWithPath: filePath), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath)
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: filePath)
    }
}
