import Foundation

enum OfficialHSRLaunchBlocker {
    static let blockDuration: TimeInterval = 15

    static func configure(environment: inout [String: String], blockedHost: String) throws {
        guard let blockerURL = Bundle.main.url(
            forResource: "evernight-host-blocker",
            withExtension: "bin"
        ) else {
            throw BlockerError.resourceMissing
        }

        var libraries = environment["DYLD_INSERT_LIBRARIES"]?
            .split(separator: ":")
            .map(String.init) ?? []
        if !libraries.contains(blockerURL.path) {
            libraries.append(blockerURL.path)
        }

        environment["DYLD_INSERT_LIBRARIES"] = libraries.joined(separator: ":")
        environment["EVERNIGHT_BLOCK_HOSTS"] = blockedHost
        environment["EVERNIGHT_BLOCK_UNTIL_EPOCH"] = String(
            format: "%.3f",
            Date().timeIntervalSince1970 + blockDuration
        )
    }
}

private enum BlockerError: LocalizedError {
    case resourceMissing

    var errorDescription: String? {
        "Bundled official HSR launch blocker is missing."
    }
}
