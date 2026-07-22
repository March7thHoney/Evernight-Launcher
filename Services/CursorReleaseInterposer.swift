import Foundation

enum CursorReleaseInterposer {
    static func configure(environment: inout [String: String]) throws {
        guard let interposerURL = Bundle.main.url(
            forResource: "evernight-cursor-release",
            withExtension: "bin"
        ) else {
            throw CursorReleaseError.resourceMissing
        }

        var libraries = environment["DYLD_INSERT_LIBRARIES"]?
            .split(separator: ":")
            .map(String.init) ?? []
        if !libraries.contains(interposerURL.path) {
            libraries.append(interposerURL.path)
        }
        environment["DYLD_INSERT_LIBRARIES"] = libraries.joined(separator: ":")
    }
}

private enum CursorReleaseError: LocalizedError {
    case resourceMissing

    var errorDescription: String? {
        "Bundled cursor release interposer is missing."
    }
}
