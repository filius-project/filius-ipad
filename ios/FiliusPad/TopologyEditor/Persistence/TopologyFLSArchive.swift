import Compression
import Foundation

enum TopologyFLSArchiveErrorCode: String, Equatable {
    case malformedArchive
    case missingConfiguration
    case duplicateEntry
    case unsupportedCompression
    case encryptedEntry
    case unsafeEntryPath
    case checksumMismatch
    case archiveLimitExceeded
    case unsafeOpaquePayload
}

struct TopologyFLSArchiveError: Error, Equatable, LocalizedError {
    let code: TopologyFLSArchiveErrorCode
    let entryPath: String?
    let detail: String

    var errorDescription: String? {
        if let entryPath {
            return "FILIUS archive entry '\(entryPath)': \(detail)"
        }
        return "FILIUS archive: \(detail)"
    }
}

enum TopologyFLSArchiveLimits {
    static let maxEntryCount = 10_000
    static let maxEntryUncompressedBytes = 128 * 1_024 * 1_024
    static let maxTotalUncompressedBytes = 256 * 1_024 * 1_024
    static let maxArchiveBytes = 256 * 1_024 * 1_024
}

private enum TopologyFLSArchivePathPolicy {
    private static let reservedDeviceNames: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for index in 1...9 {
            names.insert("COM\(index)")
            names.insert("LPT\(index)")
        }
        for suffix in ["¹", "²", "³"] {
            names.insert("COM\(suffix)")
            names.insert("LPT\(suffix)")
        }
        return names
    }()

    static func validate(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let hasAbsolutePrefix = path.hasPrefix("/") || path.hasPrefix("\\")
        let hasDrivePrefix = path.count >= 2 && path[path.index(after: path.startIndex)] == ":"
        guard !path.isEmpty,
              !path.contains("\\"),
              !path.contains("\0"),
              !hasAbsolutePrefix,
              !hasDrivePrefix,
              !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            throw TopologyFLSArchiveError(
                code: .unsafeEntryPath,
                entryPath: path,
                detail: "Absolute, empty, dot, parent-traversal, backslash, drive-prefixed, or NUL paths are rejected."
            )
        }

        for component in components {
            let forbiddenScalars = CharacterSet(charactersIn: "\"*:<>?|")
            let containsForbiddenScalar = component.unicodeScalars.contains { scalar in
                scalar.value <= 0x1f || forbiddenScalars.contains(scalar)
            }
            guard let lastScalar = component.unicodeScalars.last,
                  lastScalar.value != 0x20,
                  lastScalar.value != 0x2e,
                  !containsForbiddenScalar
            else {
                throw TopologyFLSArchiveError(
                    code: .unsafeEntryPath,
                    entryPath: path,
                    detail: "Portable archive components cannot end in a space or period or contain Windows-forbidden characters or controls."
                )
            }

            let stem = String(component.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                .uppercased()
            guard !reservedDeviceNames.contains(stem) else {
                throw TopologyFLSArchiveError(
                    code: .unsafeEntryPath,
                    entryPath: path,
                    detail: "Windows reserved device names are not portable archive components."
                )
            }
        }
    }

    static func canonicalKey(_ path: String) -> String {
        path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map {
                String($0)
                    .precomposedStringWithCanonicalMapping
                    .folding(
                        options: [.caseInsensitive, .widthInsensitive],
                        locale: Locale(identifier: "en_US_POSIX")
                    )
            }
            .joined(separator: "/")
    }
}

struct TopologyFLSArchiveImportResult {
    let project: TopologyFLSImportResult
    let supplementalEntries: [String: Data]
    let opaqueContent: TopologyFLSOpaqueContent
    let archiveEntryPaths: [String]
}

extension TopologyProjectStore {
    static let filiusConfigurationArchivePath = "projekt/konfiguration.xml"
    static let filiusApplicationsArchivePath = "projekt/anwendungen/EigeneAnwendungen.txt"

    /// Imports the Java-compatible project and retains every non-configuration archive entry
    /// for the next explicit Save. These entries stay outside the native autosave snapshot.
    static func importFiliusArchiveDocument(_ archiveData: Data) throws -> TopologyFLSArchiveImportResult {
        let entries = try TopologyFLSZIPArchive.readEntries(from: archiveData)
        guard let configurationXML = entries[filiusConfigurationArchivePath] else {
            throw TopologyFLSArchiveError(
                code: .missingConfiguration,
                entryPath: filiusConfigurationArchivePath,
                detail: "The required configuration entry is missing."
            )
        }
        var supplementalEntries = entries
        supplementalEntries.removeValue(forKey: filiusConfigurationArchivePath)
        let project = try importFiliusConfigurationXML(configurationXML)
        return TopologyFLSArchiveImportResult(
            project: project,
            supplementalEntries: supplementalEntries,
            opaqueContent: project.opaqueContent,
            archiveEntryPaths: entries.keys.sorted()
        )
    }

    static func importFiliusArchive(_ archiveData: Data) throws -> TopologyFLSImportResult {
        try importFiliusArchiveDocument(archiveData).project
    }

    static func exportFiliusArchive(
        from state: TopologyEditorState,
        filiusVersion: String = "Filius version: 2.1.0 (iPad compatibility export)"
    ) throws -> Data {
        try exportFiliusArchiveWithReport(from: state, filiusVersion: filiusVersion).data
    }

    static func exportFiliusArchiveWithReport(
        from state: TopologyEditorState,
        filiusVersion: String = "Filius version: 2.1.0 (iPad compatibility export)",
        supplementalEntries: [String: Data] = [:],
        opaqueContent: TopologyFLSOpaqueContent = .empty
    ) throws -> TopologyFLSExportResult {
        var state = state
        do {
            for nodeID in state.runtimeInstalledProgramsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                let programs = state.runtimeInstalledProgramsByNodeID[nodeID] ?? []
                if programs.contains(.emailClient) {
                    try state.persistRuntimeEmailClientConfiguration(nodeID: nodeID)
                }
                if programs.contains(.emailServer) {
                    try state.persistRuntimeEmailServerConfiguration(nodeID: nodeID)
                }
                if programs.contains(.gnutella) {
                    try state.persistRuntimeGnutellaConfiguration(nodeID: nodeID)
                }
            }
            try validateVirtualFileSystemsForPersistence(from: state)
        } catch {
            throw TopologyFLSArchiveError(
                code: .archiveLimitExceeded,
                entryPath: filiusConfigurationArchivePath,
                detail: "Virtual filesystem export validation failed (including email and Gnutella mirrors): \(error.localizedDescription)"
            )
        }
        let configuration: TopologyFLSExportResult
        do {
            configuration = try exportFiliusConfigurationXMLWithReport(
                from: state,
                filiusVersion: filiusVersion
            )
        } catch {
            throw TopologyFLSArchiveError(
                code: .archiveLimitExceeded,
                entryPath: filiusConfigurationArchivePath,
                detail: "Native FILIUS XML serialization failed: \(error.localizedDescription)"
            )
        }
        var entries = supplementalEntries
        let criticalConfigurationKey = TopologyFLSArchivePathPolicy.canonicalKey(filiusConfigurationArchivePath)
        let criticalApplicationsKey = TopologyFLSArchivePathPolicy.canonicalKey(filiusApplicationsArchivePath)
        for path in entries.keys {
            let normalizedPath = TopologyFLSArchivePathPolicy.canonicalKey(path)
            let isAllowedExactCriticalPath = path == filiusConfigurationArchivePath || path == filiusApplicationsArchivePath
            if (normalizedPath == criticalConfigurationKey || normalizedPath == criticalApplicationsKey)
                && !isAllowedExactCriticalPath {
                throw TopologyFLSArchiveError(
                    code: .duplicateEntry,
                    entryPath: path,
                    detail: "Supplemental entry conflicts with a critical FILIUS archive path."
                )
            }
        }
        if entries[filiusApplicationsArchivePath] == nil {
            entries[filiusApplicationsArchivePath] = Data()
        }
        entries[filiusConfigurationArchivePath] = try TopologyFLSOpaqueXMLMerger.merge(
            generatedConfiguration: configuration.data,
            opaqueContent: opaqueContent,
            state: state
        )
        let data = try TopologyFLSZIPArchive.writeEntries(entries)
        return TopologyFLSExportResult(data: data, report: configuration.report)
    }
}

private enum TopologyFLSZIPArchive {
    private static let localHeaderSignature: UInt32 = 0x04034b50
    private static let centralHeaderSignature: UInt32 = 0x02014b50
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    private static let utf8Flag: UInt16 = 0x0800
    private static let encryptedFlag: UInt16 = 0x0001
    private static let maxEntryCount = TopologyFLSArchiveLimits.maxEntryCount
    private static let maxEntryUncompressedBytes = TopologyFLSArchiveLimits.maxEntryUncompressedBytes
    private static let maxTotalUncompressedBytes = TopologyFLSArchiveLimits.maxTotalUncompressedBytes
    private static let maxArchiveBytes = TopologyFLSArchiveLimits.maxArchiveBytes

    private struct EntryMetadata {
        let path: String
        let compressionMethod: UInt16
        let checksum: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private struct WrittenEntry {
        let pathData: Data
        let checksum: UInt32
        let size: UInt32
        let localHeaderOffset: UInt32
    }

    static func readEntries(from archiveData: Data) throws -> [String: Data] {
        guard archiveData.count <= maxArchiveBytes else {
            throw limitExceeded("The compressed archive exceeds \(maxArchiveBytes) bytes.")
        }
        let endOffset = try endOfCentralDirectoryOffset(in: archiveData)
        guard endOffset + 22 <= archiveData.count else {
            throw malformed("The end-of-central-directory record is truncated.")
        }

        let diskNumber = archiveData.uint16LE(at: endOffset + 4)
        let centralDirectoryDisk = archiveData.uint16LE(at: endOffset + 6)
        let entriesOnDisk = Int(archiveData.uint16LE(at: endOffset + 8))
        let entryCount = Int(archiveData.uint16LE(at: endOffset + 10))
        let centralDirectorySize = Int(archiveData.uint32LE(at: endOffset + 12))
        let centralDirectoryOffset = Int(archiveData.uint32LE(at: endOffset + 16))
        let commentLength = Int(archiveData.uint16LE(at: endOffset + 20))

        guard endOffset + 22 + commentLength == archiveData.count else {
            throw malformed("The archive comment length is inconsistent with the payload.")
        }
        guard diskNumber == 0, centralDirectoryDisk == 0, entriesOnDisk == entryCount else {
            throw malformed("Multi-disk ZIP archives are not supported.")
        }
        guard entryCount <= maxEntryCount else {
            throw limitExceeded("The archive contains more than \(maxEntryCount) entries.")
        }
        guard centralDirectoryOffset <= endOffset,
              centralDirectorySize <= endOffset - centralDirectoryOffset
        else {
            throw malformed("The central directory points outside the archive.")
        }

        let metadata = try parseCentralDirectory(
            archiveData,
            offset: centralDirectoryOffset,
            size: centralDirectorySize,
            entryCount: entryCount
        )

        try rejectDuplicateEntries(in: metadata)

        var entries: [String: Data] = [:]
        var totalUncompressedBytes = 0
        for entry in metadata {
            let (newTotal, overflow) = totalUncompressedBytes.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, newTotal <= maxTotalUncompressedBytes else {
                throw limitExceeded("The expanded archive exceeds \(maxTotalUncompressedBytes) bytes.")
            }
            totalUncompressedBytes = newTotal
            entries[entry.path] = try extract(entry, from: archiveData)
        }
        return entries
    }

    static func writeEntries(_ entries: [String: Data]) throws -> Data {
        guard entries.count <= maxEntryCount, entries.count <= Int(UInt16.max) else {
            throw limitExceeded("The archive contains too many entries for supported ZIP output.")
        }
        var canonicalPaths: [String: String] = [:]
        for path in entries.keys {
            try TopologyFLSArchivePathPolicy.validate(path)
            let canonicalPath = TopologyFLSArchivePathPolicy.canonicalKey(path)
            if let existingPath = canonicalPaths[canonicalPath], existingPath != path {
                throw TopologyFLSArchiveError(
                    code: .duplicateEntry,
                    entryPath: path,
                    detail: "Portable archive path collides with '\(existingPath)'."
                )
            }
            canonicalPaths[canonicalPath] = path
        }

        var totalUncompressedBytes = 0
        for (path, payload) in entries {
            guard payload.count <= maxEntryUncompressedBytes else {
                throw TopologyFLSArchiveError(
                    code: .archiveLimitExceeded,
                    entryPath: path,
                    detail: "The output entry exceeds \(maxEntryUncompressedBytes) bytes."
                )
            }
            let (nextTotal, overflow) = totalUncompressedBytes.addingReportingOverflow(payload.count)
            guard !overflow, nextTotal <= maxTotalUncompressedBytes else {
                throw limitExceeded("The output archive exceeds \(maxTotalUncompressedBytes) expanded bytes.")
            }
            totalUncompressedBytes = nextTotal
        }

        var archive = Data()
        var writtenEntries: [WrittenEntry] = []
        for path in entries.keys.sorted() {
            guard let payload = entries[path] else { continue }
            guard let pathData = path.data(using: .utf8), pathData.count <= Int(UInt16.max) else {
                throw malformed("An archive path cannot be represented as a classic ZIP filename.", entryPath: path)
            }
            guard payload.count <= Int(UInt32.max), archive.count <= Int(UInt32.max) else {
                throw limitExceeded("The archive exceeds classic ZIP size limits.")
            }

            let checksum = CRC32.checksum(payload)
            let size = UInt32(payload.count)
            let localOffset = UInt32(archive.count)
            archive.appendUInt32LE(localHeaderSignature)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(utf8Flag)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0x0021)
            archive.appendUInt32LE(checksum)
            archive.appendUInt32LE(size)
            archive.appendUInt32LE(size)
            archive.appendUInt16LE(UInt16(pathData.count))
            archive.appendUInt16LE(0)
            archive.append(pathData)
            archive.append(payload)
            try enforceArchiveSize(archive, entryPath: path)
            writtenEntries.append(
                WrittenEntry(
                    pathData: pathData,
                    checksum: checksum,
                    size: size,
                    localHeaderOffset: localOffset
                )
            )
        }

        guard archive.count <= Int(UInt32.max) else {
            throw limitExceeded("The archive exceeds classic ZIP size limits.")
        }
        let centralDirectoryOffset = UInt32(archive.count)
        for entry in writtenEntries {
            archive.appendUInt32LE(centralHeaderSignature)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(utf8Flag)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0x0021)
            archive.appendUInt32LE(entry.checksum)
            archive.appendUInt32LE(entry.size)
            archive.appendUInt32LE(entry.size)
            archive.appendUInt16LE(UInt16(entry.pathData.count))
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(0)
            archive.appendUInt32LE(entry.localHeaderOffset)
            archive.append(entry.pathData)
            try enforceArchiveSize(archive)
        }

        guard archive.count <= Int(UInt32.max) else {
            throw limitExceeded("The archive exceeds classic ZIP size limits.")
        }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        archive.appendUInt32LE(endOfCentralDirectorySignature)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(writtenEntries.count))
        archive.appendUInt16LE(UInt16(writtenEntries.count))
        archive.appendUInt32LE(centralDirectorySize)
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)
        try enforceArchiveSize(archive)
        return archive
    }

    private static func endOfCentralDirectoryOffset(in data: Data) throws -> Int {
        guard data.count >= 22 else {
            throw malformed("The payload is too short to be a ZIP archive.")
        }
        let earliestOffset = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: earliestOffset, by: -1) {
            guard data.uint32LE(at: offset) == endOfCentralDirectorySignature,
                  offset + 22 <= data.count
            else {
                continue
            }
            let commentLength = Int(data.uint16LE(at: offset + 20))
            if offset + 22 + commentLength == data.count {
                return offset
            }
        }
        throw malformed("The ZIP end-of-central-directory record was not found.")
    }

    private static func parseCentralDirectory(
        _ data: Data,
        offset: Int,
        size: Int,
        entryCount: Int
    ) throws -> [EntryMetadata] {
        var cursor = offset
        let end = offset + size
        var entries: [EntryMetadata] = []
        entries.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard cursor <= end, end - cursor >= 46,
                  data.uint32LE(at: cursor) == centralHeaderSignature
            else {
                throw malformed("A central-directory entry is truncated or invalid.")
            }

            let flags = data.uint16LE(at: cursor + 8)
            let method = data.uint16LE(at: cursor + 10)
            let checksum = data.uint32LE(at: cursor + 16)
            let compressedSize = Int(data.uint32LE(at: cursor + 20))
            let uncompressedSize = Int(data.uint32LE(at: cursor + 24))
            let pathLength = Int(data.uint16LE(at: cursor + 28))
            let extraLength = Int(data.uint16LE(at: cursor + 30))
            let commentLength = Int(data.uint16LE(at: cursor + 32))
            let diskStart = data.uint16LE(at: cursor + 34)
            let localHeaderOffset = Int(data.uint32LE(at: cursor + 42))
            let trailingLength = pathLength + extraLength + commentLength

            guard trailingLength <= end - cursor - 46 else {
                throw malformed("A central-directory filename or extra field is truncated.")
            }
            guard diskStart == 0 else {
                throw malformed("Multi-disk ZIP entries are not supported.")
            }
            let pathData = data.subdata(in: cursor + 46..<cursor + 46 + pathLength)
            guard let path = String(data: pathData, encoding: .utf8) else {
                throw TopologyFLSArchiveError(
                    code: .malformedArchive,
                    entryPath: "central-directory-entry-\(entries.count)",
                    detail: "An archive filename is not valid UTF-8."
                )
            }
            try TopologyFLSArchivePathPolicy.validate(path)
            guard flags & encryptedFlag == 0 else {
                throw TopologyFLSArchiveError(
                    code: .encryptedEntry,
                    entryPath: path,
                    detail: "Encrypted ZIP entries are not supported."
                )
            }
            guard method == 0 || method == 8 else {
                throw TopologyFLSArchiveError(
                    code: .unsupportedCompression,
                    entryPath: path,
                    detail: "Compression method \(method) is not supported; expected stored or DEFLATE."
                )
            }
            guard uncompressedSize <= maxEntryUncompressedBytes else {
                throw TopologyFLSArchiveError(
                    code: .archiveLimitExceeded,
                    entryPath: path,
                    detail: "The expanded entry exceeds \(maxEntryUncompressedBytes) bytes."
                )
            }

            if !path.hasSuffix("/") {
                entries.append(
                    EntryMetadata(
                        path: path,
                        compressionMethod: method,
                        checksum: checksum,
                        compressedSize: compressedSize,
                        uncompressedSize: uncompressedSize,
                        localHeaderOffset: localHeaderOffset
                    )
                )
            }
            cursor += 46 + trailingLength
        }

        guard cursor == end else {
            throw malformed("The central-directory size does not match its entries.")
        }
        return entries
    }

    private static func rejectDuplicateEntries(in metadata: [EntryMetadata]) throws {
        var canonicalPaths: [String: String] = [:]
        for entry in metadata {
            let canonicalPath = TopologyFLSArchivePathPolicy.canonicalKey(entry.path)
            if let existingPath = canonicalPaths[canonicalPath] {
                throw TopologyFLSArchiveError(
                    code: .duplicateEntry,
                    entryPath: entry.path,
                    detail: "Portable archive path collides with '\(existingPath)'."
                )
            }
            canonicalPaths[canonicalPath] = entry.path
        }
    }

    private static func enforceArchiveSize(_ archive: Data, entryPath: String? = nil) throws {
        guard archive.count <= maxArchiveBytes else {
            throw TopologyFLSArchiveError(
                code: .archiveLimitExceeded,
                entryPath: entryPath,
                detail: "The final ZIP archive exceeds \(maxArchiveBytes) bytes including headers."
            )
        }
    }

    private static func extract(_ entry: EntryMetadata, from archive: Data) throws -> Data {
        let localOffset = entry.localHeaderOffset
        guard localOffset >= 0, localOffset <= archive.count, archive.count - localOffset >= 30,
              archive.uint32LE(at: localOffset) == localHeaderSignature
        else {
            throw malformed("The local file header is missing or truncated.", entryPath: entry.path)
        }

        let localFlags = archive.uint16LE(at: localOffset + 6)
        let localMethod = archive.uint16LE(at: localOffset + 8)
        let localPathLength = Int(archive.uint16LE(at: localOffset + 26))
        let localExtraLength = Int(archive.uint16LE(at: localOffset + 28))
        guard localFlags & encryptedFlag == 0, localMethod == entry.compressionMethod else {
            throw malformed("The local header conflicts with the central directory.", entryPath: entry.path)
        }
        let headerTailLength = localPathLength + localExtraLength
        guard headerTailLength <= archive.count - localOffset - 30 else {
            throw malformed("The local filename or extra field is truncated.", entryPath: entry.path)
        }
        let localPathData = archive.subdata(in: localOffset + 30..<localOffset + 30 + localPathLength)
        guard let localPath = String(data: localPathData, encoding: .utf8), localPath == entry.path else {
            throw malformed("The local filename conflicts with the central directory.", entryPath: entry.path)
        }
        let payloadOffset = localOffset + 30 + headerTailLength
        guard entry.compressedSize <= archive.count - payloadOffset else {
            throw malformed("The compressed entry payload is truncated.", entryPath: entry.path)
        }
        let compressed = archive.subdata(in: payloadOffset..<payloadOffset + entry.compressedSize)

        let payload: Data
        switch entry.compressionMethod {
        case 0:
            guard compressed.count == entry.uncompressedSize else {
                throw malformed("A stored entry has inconsistent compressed and expanded sizes.", entryPath: entry.path)
            }
            payload = compressed
        case 8:
            payload = try inflate(
                compressed,
                expectedSize: entry.uncompressedSize,
                entryPath: entry.path
            )
        default:
            throw TopologyFLSArchiveError(
                code: .unsupportedCompression,
                entryPath: entry.path,
                detail: "Compression method \(entry.compressionMethod) is not supported."
            )
        }

        guard CRC32.checksum(payload) == entry.checksum else {
            throw TopologyFLSArchiveError(
                code: .checksumMismatch,
                entryPath: entry.path,
                detail: "The CRC-32 checksum does not match the expanded entry."
            )
        }
        return payload
    }

    private static func inflate(_ compressed: Data, expectedSize: Int, entryPath: String) throws -> Data {
        if expectedSize == 0 {
            return Data()
        }
        guard !compressed.isEmpty else {
            throw malformed("A DEFLATE entry has no compressed payload.", entryPath: entryPath)
        }

        var output = Data(count: expectedSize)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer -> Int in
            compressed.withUnsafeBytes { inputBuffer -> Int in
                guard let outputBase = outputBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let inputBase = inputBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return 0
                }
                return compression_decode_buffer(
                    outputBase,
                    expectedSize,
                    inputBase,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == expectedSize else {
            throw malformed(
                "DEFLATE expansion produced \(decodedCount) bytes; expected \(expectedSize).",
                entryPath: entryPath
            )
        }
        return output
    }

    private static func malformed(_ detail: String, entryPath: String? = nil) -> TopologyFLSArchiveError {
        TopologyFLSArchiveError(code: .malformedArchive, entryPath: entryPath, detail: detail)
    }

    private static func limitExceeded(_ detail: String) -> TopologyFLSArchiveError {
        TopologyFLSArchiveError(code: .archiveLimitExceeded, entryPath: nil, detail: detail)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var checksum = UInt32(value)
        for _ in 0..<8 {
            checksum = checksum & 1 == 1
                ? 0xedb88320 ^ (checksum >> 1)
                : checksum >> 1
        }
        return checksum
    }

    static func checksum(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((checksum ^ UInt32(byte)) & 0xff)
            checksum = table[index] ^ (checksum >> 8)
        }
        return checksum ^ 0xffffffff
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
