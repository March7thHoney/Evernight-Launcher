import Foundation

// One diff chunk file as listed by a sophon patch manifest.
struct SophonChunk: Codable, Equatable {
    let name: String
    let size: Int64
    let md5: String
}

// On-disk record of a staged pre-download; lets the payload be applied after the branch closes.
struct PreDownloadLedger: Codable {
    let region: String
    let fromVersion: String
    let toVersion: String
    let buildId: String
    let categories: [Category]

    struct Category: Codable {
        let id: String
        let matchingField: String
        let chunkURLPrefix: String
        let chunkURLSuffix: String
        let chunks: [SophonChunk]
    }

    var totalBytes: Int64 {
        categories.reduce(0) { total, category in
            total + category.chunks.reduce(0) { $0 + $1.size }
        }
    }
}

// Minimal protobuf wire walker for sophon patch manifests, so the app needs no protobuf dependency.
enum SophonManifestReader {

    // ManifestProto.assets(1) > AssetManifestProperty.asset_data(4) > AssetManifestChunk.assets(2) > AssetManifest
    static func chunks(inDecompressedManifestAt path: String, fromVersion: String) throws -> [SophonChunk] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw SophonManifestError.unreadable
        }
        let bytes = [UInt8](data)
        var seen = Set<String>()
        var chunks: [SophonChunk] = []

        for property in try messages(bytes, bytes.startIndex..<bytes.endIndex, field: 1) {
            for holder in try messages(bytes, property, field: 4) {
                for entry in try messages(bytes, holder, field: 2) {
                    var name = ""
                    var version = ""
                    var size: Int64 = 0
                    var md5 = ""
                    try scan(bytes, entry) { field, value in
                        switch (field, value) {
                        case (1, .bytes(let range)): name = text(bytes, range)
                        case (2, .bytes(let range)): version = text(bytes, range)
                        case (4, .varint(let value)): size = Int64(value)
                        case (5, .bytes(let range)): md5 = text(bytes, range)
                        default: break
                        }
                    }
                    guard version == fromVersion, !name.isEmpty, seen.insert(name).inserted else { continue }
                    chunks.append(SophonChunk(name: name, size: size, md5: md5))
                }
            }
        }
        return chunks
    }

    // MARK: - Wire format

    private enum WireValue {
        case varint(UInt64)
        case bytes(Range<Int>)
    }

    private static func messages(_ bytes: [UInt8], _ range: Range<Int>, field: Int) throws -> [Range<Int>] {
        var found: [Range<Int>] = []
        try scan(bytes, range) { number, value in
            if number == field, case .bytes(let inner) = value { found.append(inner) }
        }
        return found
    }

    private static func scan(
        _ bytes: [UInt8],
        _ range: Range<Int>,
        _ visit: (Int, WireValue) throws -> Void
    ) throws {
        var index = range.lowerBound
        while index < range.upperBound {
            let (key, afterKey) = try varint(bytes, index, range.upperBound)
            index = afterKey
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                let (value, next) = try varint(bytes, index, range.upperBound)
                index = next
                try visit(number, .varint(value))
            case 2:
                let (length, afterLength) = try varint(bytes, index, range.upperBound)
                let end = afterLength + Int(length)
                guard length <= UInt64(range.upperBound), end <= range.upperBound else {
                    throw SophonManifestError.malformed
                }
                index = end
                try visit(number, .bytes(afterLength..<end))
            case 5:
                index += 4
                guard index <= range.upperBound else { throw SophonManifestError.malformed }
            case 1:
                index += 8
                guard index <= range.upperBound else { throw SophonManifestError.malformed }
            default:
                throw SophonManifestError.malformed
            }
        }
    }

    private static func varint(_ bytes: [UInt8], _ start: Int, _ limit: Int) throws -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < limit {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return (result, index) }
            shift += 7
            guard shift < 64 else { throw SophonManifestError.malformed }
        }
        throw SophonManifestError.malformed
    }

    private static func text(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }
}

enum SophonManifestError: LocalizedError {
    case unreadable
    case malformed
    case chunkListMismatch(parsed: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The official pre-download manifest could not be read."
        case .malformed:
            return "The official pre-download manifest is malformed."
        case .chunkListMismatch(let parsed, let expected):
            return "The pre-download manifest lists \(parsed) chunks but the server reported \(expected)."
        }
    }
}
