import Foundation

// Changes the in-game text language by patching HSR's DesignData binary language table.
struct LanguagePatchManager {

    struct LanguageOption: Identifiable {
        let code: String
        let displayName: String
        var id: String { code }
    }

    // Text language choices; codes match the values stored in the game's language table.
    static let textLanguages: [LanguageOption] = [
        LanguageOption(code: "en", displayName: "English"),
        LanguageOption(code: "cn", displayName: "Chinese"),
        LanguageOption(code: "jp", displayName: "Japanese"),
        LanguageOption(code: "kr", displayName: "Korean"),
    ]

    // NameHash of the HSR language table inside the design index (version-specific).
    private static let languageTableHash: Int32 = -515329346

    private static func assetFolder(_ installDirectory: String) -> String {
        installDirectory + "/StarRail_Data/StreamingAssets/DesignData/Windows"
    }

    // MARK: - Public API

    static func getTextLanguage(installDirectory: String) throws -> String {
        let folder = assetFolder(installDirectory)
        let (dataEntry, fileEntry) = try locateLanguageTable(folder)
        let rows = try parseLanguageRows(folder: folder, fileEntry: fileEntry, dataEntry: dataEntry)
        for area in ["os", "cn"] {
            if let row = rows.first(where: { $0.area == area && $0.type == nil }),
               let lang = row.defaultLanguage {
                return lang
            }
        }
        throw LanguagePatchError.languageTableNotFound
    }

    static func setTextLanguage(installDirectory: String, code: String) throws {
        let folder = assetFolder(installDirectory)
        let (dataEntry, fileEntry) = try locateLanguageTable(folder)
        var rows = try parseLanguageRows(folder: folder, fileEntry: fileEntry, dataEntry: dataEntry)

        // Update both text rows ("os"/"cn", Type == nil); leave voice rows (Type == 1) untouched.
        for i in rows.indices where rows[i].type == nil && (rows[i].area == "os" || rows[i].area == "cn") {
            rows[i].defaultLanguage = code
            rows[i].languageList = [code]
        }

        var out = serializeLanguageRows(rows)
        guard out.count <= Int(dataEntry.size) else { throw LanguagePatchError.dataTooLarge }
        if out.count < Int(dataEntry.size) {
            out.append(contentsOf: [UInt8](repeating: 0, count: Int(dataEntry.size) - out.count))
        }

        let bytesPath = folder + "/" + fileEntry.fileByteName + ".bytes"
        guard let handle = FileHandle(forUpdatingAtPath: bytesPath) else {
            throw LanguagePatchError.fileNotFound(bytesPath)
        }
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(dataEntry.offset))
        try handle.write(contentsOf: Data(out))
    }

    // MARK: - Language table (excel) parse / serialize

    private struct LanguageRow {
        var area: String?
        var type: UInt8?
        var languageList: [String] = []
        var defaultLanguage: String?
    }

    private static func parseLanguageRows(folder: String, fileEntry: FileEntry, dataEntry: DataEntry) throws -> [LanguageRow] {
        let bytesPath = folder + "/" + fileEntry.fileByteName + ".bytes"
        guard let fileData = FileManager.default.contents(atPath: bytesPath) else {
            throw LanguagePatchError.fileNotFound(bytesPath)
        }
        let all = Array(fileData)
        let start = Int(dataEntry.offset)
        let end = start + Int(dataEntry.size)
        guard end <= all.count else { throw LanguagePatchError.unexpectedEOF }

        var r = ByteReader(Array(all[start..<end]))
        _ = try r.u8()                       // leading version byte
        let count = try r.zigzagVarint()
        guard count >= 0 else { throw LanguagePatchError.unexpectedEOF }

        var rows: [LanguageRow] = []
        rows.reserveCapacity(count)
        for _ in 0..<count {
            let bitmask = try r.u8()
            var row = LanguageRow()
            if bitmask & (1 << 0) != 0 { row.area = try r.lenString() }
            if bitmask & (1 << 1) != 0 { row.type = try r.u8() }
            if bitmask & (1 << 2) != 0 {
                let n = try r.zigzagVarint()
                guard n >= 0 else { throw LanguagePatchError.unexpectedEOF }
                var arr: [String] = []
                for _ in 0..<n { arr.append(try r.lenString()) }
                row.languageList = arr
            }
            if bitmask & (1 << 3) != 0 { row.defaultLanguage = try r.lenString() }
            rows.append(row)
        }
        return rows
    }

    private static func serializeLanguageRows(_ rows: [LanguageRow]) -> [UInt8] {
        var w = ByteWriter()
        w.u8(0)
        w.zigzagVarint(rows.count)
        for row in rows {
            var bitmask: UInt8 = 0
            if row.area != nil { bitmask |= 1 << 0 }
            if row.type != nil { bitmask |= 1 << 1 }
            if !row.languageList.isEmpty { bitmask |= 1 << 2 }
            if row.defaultLanguage != nil { bitmask |= 1 << 3 }
            w.u8(bitmask)
            if let a = row.area { w.lenString(a) }
            if let t = row.type { w.u8(t) }
            if !row.languageList.isEmpty {
                w.zigzagVarint(row.languageList.count)
                for s in row.languageList { w.lenString(s) }
            }
            if let d = row.defaultLanguage { w.lenString(d) }
        }
        return w.bytes
    }

    // MARK: - Design index (asset-meta) parse

    private struct DataEntry {
        let nameHash: Int32
        let size: UInt32
        let offset: UInt32
    }

    private struct FileEntry {
        let nameHash: Int32
        let fileByteName: String
        let dataEntries: [DataEntry]
    }

    private static func locateLanguageTable(_ folder: String) throws -> (DataEntry, FileEntry) {
        let indexHash = try getIndexHash(folder)
        let path = folder + "/DesignV_\(indexHash).bytes"
        guard let data = FileManager.default.contents(atPath: path) else {
            throw LanguagePatchError.fileNotFound(path)
        }
        var r = ByteReader(Array(data))
        _ = try r.i64BE()                    // UnkI64
        let fileCount = try r.i32BE()
        _ = try r.i32BE()                    // DesignDataCount
        for _ in 0..<Int(fileCount) {
            let fileEntry = try readFileEntry(&r)
            for entry in fileEntry.dataEntries where entry.nameHash == languageTableHash {
                return (entry, fileEntry)
            }
        }
        throw LanguagePatchError.languageTableNotFound
    }

    private static func readFileEntry(_ r: inout ByteReader) throws -> FileEntry {
        let nameHash = try r.i32BE()
        let fileByteName = try r.bytesN(16).map { String(format: "%02x", $0) }.joined()
        _ = try r.u64BE()                    // Size
        let dataCount = try r.u32BE()
        var entries: [DataEntry] = []
        entries.reserveCapacity(Int(dataCount))
        for _ in 0..<Int(dataCount) {
            let nh = try r.i32BE()
            let sz = try r.u32BE()
            let off = try r.u32BE()
            entries.append(DataEntry(nameHash: nh, size: sz, offset: off))
        }
        let subLen = try r.u16BE()
        if subLen > 0 { _ = try r.bytesN(Int(subLen)) }   // SubPath
        _ = try r.u8()                       // marker
        return FileEntry(nameHash: nameHash, fileByteName: fileByteName, dataEntries: entries)
    }

    // M_DesignV.bytes holds the index hash at 0x1C as four little-endian 32-bit words.
    private static func getIndexHash(_ folder: String) throws -> String {
        let path = folder + "/M_DesignV.bytes"
        guard let data = FileManager.default.contents(atPath: path) else {
            throw LanguagePatchError.fileNotFound(path)
        }
        let all = Array(data)
        guard all.count >= 0x1C + 0x10 else { throw LanguagePatchError.unexpectedEOF }
        var hash = [UInt8](repeating: 0, count: 16)
        var index = 0
        for i in 0..<4 {
            let chunkStart = 0x1C + i * 4
            for bytePos in stride(from: 3, through: 0, by: -1) {
                hash[index] = all[chunkStart + bytePos]
                index += 1
            }
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Binary readers / writers

    private struct ByteReader {
        let bytes: [UInt8]
        var offset = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func u8() throws -> UInt8 {
            guard offset < bytes.count else { throw LanguagePatchError.unexpectedEOF }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func bytesN(_ n: Int) throws -> [UInt8] {
            guard n >= 0, offset + n <= bytes.count else { throw LanguagePatchError.unexpectedEOF }
            defer { offset += n }
            return Array(bytes[offset..<offset + n])
        }

        mutating func u16BE() throws -> UInt16 {
            let b = try bytesN(2)
            return (UInt16(b[0]) << 8) | UInt16(b[1])
        }

        mutating func u32BE() throws -> UInt32 {
            let b = try bytesN(4)
            return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        }

        mutating func i32BE() throws -> Int32 { Int32(bitPattern: try u32BE()) }

        mutating func u64BE() throws -> UInt64 {
            let b = try bytesN(8)
            var v: UInt64 = 0
            for x in b { v = (v << 8) | UInt64(x) }
            return v
        }

        mutating func i64BE() throws -> Int64 { Int64(bitPattern: try u64BE()) }

        mutating func lenString() throws -> String {
            let n = Int(try u8())
            return String(decoding: try bytesN(n), as: UTF8.self)
        }

        // LEB128 unsigned varint.
        mutating func uvarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let b = try u8()
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { break }
                shift += 7
            }
            return result
        }

        // Zigzag-decoded varint (Go's int8 varint).
        mutating func zigzagVarint() throws -> Int {
            let uv = try uvarint()
            let mask = 0 &- (uv & 1)              // 0 or all-ones
            return Int(Int64(bitPattern: (uv >> 1) ^ mask))
        }
    }

    private struct ByteWriter {
        var bytes: [UInt8] = []

        mutating func u8(_ v: UInt8) { bytes.append(v) }

        mutating func lenString(_ s: String) {
            let b = Array(s.utf8)
            bytes.append(UInt8(truncatingIfNeeded: b.count))
            bytes.append(contentsOf: b)
        }

        mutating func uvarint(_ value: UInt64) {
            var v = value
            while v >= 0x80 {
                bytes.append(UInt8((v & 0x7F) | 0x80))
                v >>= 7
            }
            bytes.append(UInt8(v))
        }

        // Zigzag-encoded varint mirroring Go's writeI8Varint(int8).
        mutating func zigzagVarint(_ value: Int) {
            let v8 = Int32(Int8(truncatingIfNeeded: value))
            let uv = UInt64((UInt32(bitPattern: v8) << 1) ^ UInt32(bitPattern: v8 >> 7))
            uvarint(uv)
        }
    }
}

enum LanguagePatchError: LocalizedError {
    case fileNotFound(String)
    case languageTableNotFound
    case unexpectedEOF
    case dataTooLarge

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p):
            return "Game asset not found: \((p as NSString).lastPathComponent). Install the game first."
        case .languageTableNotFound:
            return "Language table not found (incompatible game version?)."
        case .unexpectedEOF:
            return "Game asset is incomplete or corrupted."
        case .dataTooLarge:
            return "Patched language table exceeds the original size; aborted."
        }
    }
}
