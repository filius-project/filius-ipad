import Foundation

enum TopologyVirtualFileSystemError: Error, Equatable, LocalizedError {
    case pathMustBeAbsolute(String)
    case pathEscapesRoot(String)
    case invalidPathComponent(String)
    case itemAlreadyExists(String)
    case caseInsensitiveSiblingCollision(existing: String, attempted: String)
    case itemNotFound(String)
    case parentDirectoryNotFound(String)
    case expectedDirectory(String)
    case expectedFile(String)
    case expectedTextFile(String)
    case expectedImageFile(String)
    case directoryNotEmpty(String)
    case cannotMutateRoot
    case cannotMoveDirectoryIntoItself(source: String, destination: String)
    case fileSizeQuotaExceeded(path: String, actualBytes: Int, limitBytes: Int)
    case deviceSizeQuotaExceeded(actualBytes: Int, limitBytes: Int)
    case deviceEntryQuotaExceeded(actualEntries: Int, limitEntries: Int)
    case totalSizeQuotaExceeded(actualBytes: Int, limitBytes: Int)
    case totalEntryQuotaExceeded(actualEntries: Int, limitEntries: Int)

    var errorDescription: String? {
        switch self {
        case let .pathMustBeAbsolute(path):
            return "Virtual filesystem paths must be absolute: \(path)"
        case let .pathEscapesRoot(path):
            return "Virtual filesystem path escapes root: \(path)"
        case let .invalidPathComponent(component):
            return "Virtual filesystem path contains an invalid component: \(component)"
        case let .itemAlreadyExists(path):
            return "An item already exists at \(path)."
        case let .caseInsensitiveSiblingCollision(existing, attempted):
            return "Virtual filesystem item \(attempted) conflicts case-insensitively with sibling \(existing)."
        case let .itemNotFound(path):
            return "No item exists at \(path)."
        case let .parentDirectoryNotFound(path):
            return "The parent directory does not exist for \(path)."
        case let .expectedDirectory(path):
            return "A directory was required at \(path)."
        case let .expectedFile(path):
            return "A file was required at \(path)."
        case let .expectedTextFile(path):
            return "A text file was required at \(path)."
        case let .expectedImageFile(path):
            return "An image file was required at \(path)."
        case let .directoryNotEmpty(path):
            return "Directory \(path) is not empty."
        case .cannotMutateRoot:
            return "The virtual filesystem root cannot be moved, renamed, or deleted."
        case let .cannotMoveDirectoryIntoItself(source, destination):
            return "Directory \(source) cannot be copied or moved into \(destination)."
        case let .fileSizeQuotaExceeded(path, actualBytes, limitBytes):
            return "Virtual file \(path) uses \(actualBytes) bytes; the per-file limit is \(limitBytes) bytes."
        case let .deviceSizeQuotaExceeded(actualBytes, limitBytes):
            return "Virtual filesystem uses \(actualBytes) bytes; the per-device limit is \(limitBytes) bytes."
        case let .deviceEntryQuotaExceeded(actualEntries, limitEntries):
            return "Virtual filesystem contains \(actualEntries) entries; the per-device limit is \(limitEntries) entries."
        case let .totalSizeQuotaExceeded(actualBytes, limitBytes):
            return "Project virtual filesystems use \(actualBytes) bytes; the project limit is \(limitBytes) bytes."
        case let .totalEntryQuotaExceeded(actualEntries, limitEntries):
            return "Project virtual filesystems contain \(actualEntries) entries; the project limit is \(limitEntries) entries."
        }
    }
}

enum TopologyVirtualFileContent: Equatable {
    case directory
    case text(String)
    case binary(Data, mediaType: String?)
    case image(Data, mediaType: String)

    var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }

    var isFile: Bool { !isDirectory }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    var byteCount: Int {
        switch self {
        case .directory:
            return 0
        case let .text(value):
            return value.lengthOfBytes(using: .utf8)
        case let .binary(data, _), let .image(data, _):
            return data.count
        }
    }
}

struct TopologyVirtualFileEntry: Equatable, Identifiable {
    let path: String
    let content: TopologyVirtualFileContent

    var id: String { path }

    var name: String {
        guard path != "/" else { return "/" }
        return String(path.split(separator: "/").last ?? "")
    }

    var parentPath: String {
        TopologyVirtualFileSystem.parentPath(ofNormalizedPath: path)
    }
}

struct TopologyVirtualFileSystem: Equatable {
    // The 64 MiB project payload ceiling leaves headroom below the 128 MiB
    // konfiguration.xml archive-entry limit for Base64 and XML structure.
    static let maximumFileBytes = 8 * 1_024 * 1_024
    static let maximumDeviceBytes = 32 * 1_024 * 1_024
    static let maximumProjectBytes = 64 * 1_024 * 1_024
    static let maximumDeviceEntries = 4_096
    static let maximumProjectEntries = 16_384

    private static let legacyDefaultImageData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ) ?? Data()

    private static let defaultImageFiles: [(name: String, base64: String)] = [
        (
            name: "network-map.png",
            base64: """
            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
            kOsYAnLd/zErh3iMFphVAAAAAElFTkSuQmCC
            """
        ),
        (
            name: "traffic-heatmap.png",
            base64: """
            iVBORw0KGgoAAAANSUhEUgAAAUAAAAC0CAMAAADSOgUjAAAAwFBMVEWaWzVWblUtXWIuJVQcboZxVDNcMEqpSEaOi0ZuNzVshFrB
            PUOCLjc5Qzmxmzweg6PJy86GOWFePIQbMjzCQ0ugo6pNhoV2fIW+wcW7vsIQGzAUIzIWNU4jM00rJi0sJUwpHS3+/v6yljQzNi1O
            JTG0O0RORy2NeDELSGeoiTNtKjQLZ40NVnVzZjGRNDmPNk5qWC4RdZmqOD1JLWuYhTRNKk4MLENLOC5XVDJTMnRtNGsMeqOsRTyM
            aDFzMk0RQ1pPNnn/AAAAQHRSTlP/////////////////////////////////////////////////////////////////////////
            ////////////73leyQAAFuJJREFUeNrt3QlbGkm3AGAWhZhEY5JJvrlA07gAakRQJGoS9f//q1tdXcvZqhdoxDGc5wlBBqO8c2rv
            qq5FudGrPqIKI/nXlvthOd9V7NesRR0e0mu9il+LKn5tlZ+7yve+acDoLQP2toBvBzDaAm4Bt4BbwL8EMN4CbgG3gP8VwHhTgJuK
            qkcn8QqvvWnA3hZwC/jmAaMtIIEZpBGrP1vAcoADGLF7Vk3L/KoAe9UDDmjE6Ks3loGVAw4GOYCp4WoZCMK/XD88PDo8rKs/h3X1
            1VG300me/88+6nd86ydvPTIP6X/R7zXfXUIubzGjwHpHXFlk/NyoV2hNpGNh1J/osNP59q1uoNxjXb1c/xcBpt+m3+u+Wj0De0uO
            OsRsC722ljrQAHaU1L/RNwr4f40ESwDU7904YAaW/Nr6AOvfOvX/JYoY8BC9zwOm790wYA6W/Np6AFW91u180zVh8jyyjxBQvXJo
            6sCGee9GAbOxFmHU9WTg9+8JlspDkoGBIpy+d4OAWdnWV5EBOFhmeJcL2PimQQ5pI/KvkcKA5r2bA5SLa9/Hwvy9TOd6yUZEN6uH
            EQZMyuq3Lu3GfDPvXTNgcNQhZZYBOzWxSB4IYjzggvFbGYmUAeT1HbLzgKdOkRX1vxmQNxhUT8Ud/MIQxnx09xcCDniLsTjl0cJf
            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
            """
        ),
        (
            name: "switch-backplane.png",
            base64: """
                        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
            """
        )
    ]

    private(set) var contentByPath: [String: TopologyVirtualFileContent]

    init() {
        contentByPath = ["/": .directory]
    }

    init(entries: [TopologyVirtualFileEntry]) throws {
        contentByPath = ["/": .directory]
        let sortedEntries = entries.sorted { lhs, rhs in
            let lhsDepth = lhs.path.split(separator: "/").count
            let rhsDepth = rhs.path.split(separator: "/").count
            if lhsDepth == rhsDepth { return lhs.path < rhs.path }
            return lhsDepth < rhsDepth
        }
        for entry in sortedEntries {
            let normalizedPath = try Self.normalizedAbsolutePath(entry.path)
            guard normalizedPath != "/" else {
                throw TopologyVirtualFileSystemError.itemAlreadyExists("/")
            }
            guard contentByPath[normalizedPath] == nil else {
                throw TopologyVirtualFileSystemError.itemAlreadyExists(normalizedPath)
            }
            let parent = Self.parentPath(ofNormalizedPath: normalizedPath)
            guard contentByPath[parent]?.isDirectory == true else {
                throw TopologyVirtualFileSystemError.parentDirectoryNotFound(normalizedPath)
            }
            try ensureNoCaseInsensitiveSiblingCollision(at: normalizedPath)
            contentByPath[normalizedPath] = entry.content
        }
        try validateQuotas()
    }

    static func defaultForDevice() -> TopologyVirtualFileSystem {
        var fileSystem = TopologyVirtualFileSystem()
        try? fileSystem.createDirectory(at: "/home")
        try? fileSystem.createDirectory(at: "/images")
        try? fileSystem.createDirectory(at: "/var/log", recursive: true)
        try? fileSystem.writeTextFile(
            at: "/home/lab-notes.txt",
            text: "Document deterministic runtime notes here.",
            overwrite: false
        )
        try? fileSystem.writeTextFile(
            at: "/home/topology-exports.csv",
            text: "timestamp,event,detail\n",
            overwrite: false
        )
        try? fileSystem.writeTextFile(
            at: "/var/log/runtime-events.log",
            text: "Virtual runtime initialized.\n",
            overwrite: false
        )
        for imageFile in defaultImageFiles {
            guard let imageData = Data(
                base64Encoded: imageFile.base64,
                options: .ignoreUnknownCharacters
            ) else { continue }
            try? fileSystem.writeImageFile(
                at: "/images/\(imageFile.name)",
                data: imageData,
                mediaType: "image/png",
                overwrite: false
            )
        }
        return fileSystem
    }

    @discardableResult
    mutating func upgradeLegacyDefaultImages() -> Int {
        var replacementCount = 0
        for imageFile in Self.defaultImageFiles {
            let path = "/images/\(imageFile.name)"
            guard case let .image(existingData, _) = contentByPath[path],
                  existingData == Self.legacyDefaultImageData,
                  let replacementData = Data(
                      base64Encoded: imageFile.base64,
                      options: .ignoreUnknownCharacters
                  )
            else { continue }

            contentByPath[path] = .image(replacementData, mediaType: "image/png")
            replacementCount += 1
        }
        return replacementCount
    }

    static func normalizedAbsolutePath(_ rawPath: String) throws -> String {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard path.hasPrefix("/") else {
            throw TopologyVirtualFileSystemError.pathMustBeAbsolute(rawPath)
        }

        var components: [String] = []
        for substring in path.split(separator: "/", omittingEmptySubsequences: true) {
            let component = String(substring)
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else {
                    throw TopologyVirtualFileSystemError.pathEscapesRoot(rawPath)
                }
                components.removeLast()
                continue
            }
            let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !component.isEmpty,
                  component == trimmedComponent,
                  component != ".",
                  component != "..",
                  !component.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else {
                throw TopologyVirtualFileSystemError.invalidPathComponent(component)
            }
            components.append(component)
        }
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }

    static func parentPath(ofNormalizedPath path: String) -> String {
        guard path != "/", let separator = path.lastIndex(of: "/") else { return "/" }
        return separator == path.startIndex ? "/" : String(path[..<separator])
    }

    static func validateProjectQuotas(_ fileSystemsByNodeID: [UUID: TopologyVirtualFileSystem]) throws {
        var totalBytes = 0
        var totalEntries = 0
        for nodeID in fileSystemsByNodeID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let fileSystem = fileSystemsByNodeID[nodeID] else { continue }
            try fileSystem.validateQuotas()
            let (nextBytes, bytesOverflow) = totalBytes.addingReportingOverflow(fileSystem.totalFileBytes)
            guard !bytesOverflow else {
                throw TopologyVirtualFileSystemError.totalSizeQuotaExceeded(
                    actualBytes: Int.max,
                    limitBytes: maximumProjectBytes
                )
            }
            totalBytes = nextBytes
            let (nextEntries, entriesOverflow) = totalEntries.addingReportingOverflow(fileSystem.persistedEntryCount)
            guard !entriesOverflow else {
                throw TopologyVirtualFileSystemError.totalEntryQuotaExceeded(
                    actualEntries: Int.max,
                    limitEntries: maximumProjectEntries
                )
            }
            totalEntries = nextEntries
        }
        guard totalBytes <= maximumProjectBytes else {
            throw TopologyVirtualFileSystemError.totalSizeQuotaExceeded(
                actualBytes: totalBytes,
                limitBytes: maximumProjectBytes
            )
        }
        guard totalEntries <= maximumProjectEntries else {
            throw TopologyVirtualFileSystemError.totalEntryQuotaExceeded(
                actualEntries: totalEntries,
                limitEntries: maximumProjectEntries
            )
        }
    }

    func entry(at rawPath: String) throws -> TopologyVirtualFileEntry {
        let path = try existingPath(for: rawPath)
        guard let content = contentByPath[path] else {
            throw TopologyVirtualFileSystemError.itemNotFound(path)
        }
        return TopologyVirtualFileEntry(path: path, content: content)
    }

    func contains(_ rawPath: String) -> Bool {
        existingPathIfPresent(rawPath) != nil
    }

    func allEntries() -> [TopologyVirtualFileEntry] {
        contentByPath
            .map { TopologyVirtualFileEntry(path: $0.key, content: $0.value) }
            .sorted { $0.path < $1.path }
    }

    func entries(in rawDirectoryPath: String) throws -> [TopologyVirtualFileEntry] {
        let directoryPath = try existingPath(for: rawDirectoryPath)
        guard let content = contentByPath[directoryPath] else {
            throw TopologyVirtualFileSystemError.itemNotFound(directoryPath)
        }
        guard content.isDirectory else {
            throw TopologyVirtualFileSystemError.expectedDirectory(directoryPath)
        }
        return contentByPath.compactMap { path, content in
            guard path != directoryPath, Self.parentPath(ofNormalizedPath: path) == directoryPath else { return nil }
            return TopologyVirtualFileEntry(path: path, content: content)
        }.sorted { lhs, rhs in
            if lhs.content.isDirectory != rhs.content.isDirectory { return lhs.content.isDirectory }
            if lhs.name == rhs.name { return lhs.path < rhs.path }
            return lhs.name < rhs.name
        }
    }

    func textFile(at rawPath: String) throws -> String {
        let entry = try entry(at: rawPath)
        guard case let .text(value) = entry.content else {
            throw TopologyVirtualFileSystemError.expectedTextFile(entry.path)
        }
        return value
    }

    func imageFile(at rawPath: String) throws -> (data: Data, mediaType: String) {
        let entry = try entry(at: rawPath)
        guard case let .image(data, mediaType) = entry.content else {
            throw TopologyVirtualFileSystemError.expectedImageFile(entry.path)
        }
        return (data, mediaType)
    }

    mutating func createDirectory(at rawPath: String, recursive: Bool = false) throws {
        var candidate = self
        try candidate.createDirectoryUnchecked(at: rawPath, recursive: recursive)
        try candidate.validateQuotas()
        self = candidate
    }

    mutating func writeTextFile(at rawPath: String, text: String, overwrite: Bool = true) throws {
        try writeFileContent(.text(text), at: rawPath, overwrite: overwrite)
    }

    mutating func writeBinaryFile(
        at rawPath: String,
        data: Data,
        mediaType: String? = nil,
        overwrite: Bool = true
    ) throws {
        try writeFileContent(.binary(data, mediaType: mediaType), at: rawPath, overwrite: overwrite)
    }

    mutating func writeImageFile(
        at rawPath: String,
        data: Data,
        mediaType: String,
        overwrite: Bool = true
    ) throws {
        try writeFileContent(.image(data, mediaType: mediaType), at: rawPath, overwrite: overwrite)
    }

    mutating func copyItem(
        at rawSourcePath: String,
        to rawDestinationPath: String,
        overwrite: Bool = false
    ) throws {
        var candidate = self
        try candidate.copyItemUnchecked(at: rawSourcePath, to: rawDestinationPath, overwrite: overwrite)
        try candidate.validateQuotas()
        self = candidate
    }

    mutating func moveItem(
        at rawSourcePath: String,
        to rawDestinationPath: String,
        overwrite: Bool = false
    ) throws {
        var candidate = self
        try candidate.moveItemUnchecked(at: rawSourcePath, to: rawDestinationPath, overwrite: overwrite)
        try candidate.validateQuotas()
        self = candidate
    }

    mutating func renameItem(at rawPath: String, to newName: String) throws -> String {
        guard !newName.contains("/"), !newName.contains("\\") else {
            throw TopologyVirtualFileSystemError.invalidPathComponent(newName)
        }
        let sourcePath = try existingPath(for: rawPath)
        guard sourcePath != "/" else { throw TopologyVirtualFileSystemError.cannotMutateRoot }
        let parent = Self.parentPath(ofNormalizedPath: sourcePath)
        let destinationPath = parent + (parent == "/" ? "" : "/") + newName
        let normalizedDestination = try Self.normalizedAbsolutePath(destinationPath)
        try moveItem(at: sourcePath, to: normalizedDestination)
        return try existingPath(for: normalizedDestination)
    }

    mutating func deleteItem(at rawPath: String, recursive: Bool = false) throws {
        let path = try existingPath(for: rawPath)
        guard path != "/" else { throw TopologyVirtualFileSystemError.cannotMutateRoot }
        guard let content = contentByPath[path] else {
            throw TopologyVirtualFileSystemError.itemNotFound(path)
        }
        let descendants = contentByPath.keys.filter { $0.hasPrefix(path + "/") }
        if content.isDirectory, !recursive, !descendants.isEmpty {
            throw TopologyVirtualFileSystemError.directoryNotEmpty(path)
        }
        for descendant in descendants { contentByPath.removeValue(forKey: descendant) }
        contentByPath.removeValue(forKey: path)
    }

    private var persistedEntryCount: Int {
        max(0, contentByPath.count - 1)
    }

    private var totalFileBytes: Int {
        contentByPath.values.reduce(into: 0) { total, content in
            let (next, overflow) = total.addingReportingOverflow(content.byteCount)
            total = overflow ? Int.max : next
        }
    }

    private func validateQuotas() throws {
        for path in contentByPath.keys.sorted() {
            guard let content = contentByPath[path], content.isFile else { continue }
            guard content.byteCount <= Self.maximumFileBytes else {
                throw TopologyVirtualFileSystemError.fileSizeQuotaExceeded(
                    path: path,
                    actualBytes: content.byteCount,
                    limitBytes: Self.maximumFileBytes
                )
            }
        }
        let bytes = totalFileBytes
        guard bytes <= Self.maximumDeviceBytes else {
            throw TopologyVirtualFileSystemError.deviceSizeQuotaExceeded(
                actualBytes: bytes,
                limitBytes: Self.maximumDeviceBytes
            )
        }
        let entries = persistedEntryCount
        guard entries <= Self.maximumDeviceEntries else {
            throw TopologyVirtualFileSystemError.deviceEntryQuotaExceeded(
                actualEntries: entries,
                limitEntries: Self.maximumDeviceEntries
            )
        }
    }

    private mutating func createDirectoryUnchecked(at rawPath: String, recursive: Bool) throws {
        let normalizedPath = try Self.normalizedAbsolutePath(rawPath)
        if normalizedPath == "/" { return }
        if let existingPath = existingPathIfPresent(normalizedPath) {
            throw TopologyVirtualFileSystemError.itemAlreadyExists(existingPath)
        }

        let rawParent = Self.parentPath(ofNormalizedPath: normalizedPath)
        let parentPath: String
        if let existingParent = existingPathIfPresent(rawParent) {
            parentPath = existingParent
        } else {
            guard recursive else {
                throw TopologyVirtualFileSystemError.parentDirectoryNotFound(normalizedPath)
            }
            try createDirectoryUnchecked(at: rawParent, recursive: true)
            parentPath = try existingPath(for: rawParent)
        }

        guard contentByPath[parentPath]?.isDirectory == true else {
            throw TopologyVirtualFileSystemError.parentDirectoryNotFound(normalizedPath)
        }
        let name = Self.name(ofNormalizedPath: normalizedPath)
        let destinationPath = parentPath == "/" ? "/\(name)" : "\(parentPath)/\(name)"
        try ensureNoCaseInsensitiveSiblingCollision(at: destinationPath)
        contentByPath[destinationPath] = .directory
    }

    private mutating func writeFileContent(
        _ content: TopologyVirtualFileContent,
        at rawPath: String,
        overwrite: Bool
    ) throws {
        var candidate = self
        let normalizedPath = try Self.normalizedAbsolutePath(rawPath)
        guard normalizedPath != "/" else { throw TopologyVirtualFileSystemError.expectedFile(normalizedPath) }

        let destinationPath: String
        if let existingPath = candidate.existingPathIfPresent(normalizedPath) {
            destinationPath = existingPath
            guard overwrite else {
                if existingPath == normalizedPath {
                    throw TopologyVirtualFileSystemError.itemAlreadyExists(existingPath)
                }
                throw TopologyVirtualFileSystemError.caseInsensitiveSiblingCollision(
                    existing: existingPath,
                    attempted: normalizedPath
                )
            }
            guard candidate.contentByPath[existingPath]?.isFile == true else {
                throw TopologyVirtualFileSystemError.expectedFile(existingPath)
            }
        } else {
            let rawParent = Self.parentPath(ofNormalizedPath: normalizedPath)
            let parentPath = try candidate.existingPath(for: rawParent)
            guard candidate.contentByPath[parentPath]?.isDirectory == true else {
                throw TopologyVirtualFileSystemError.parentDirectoryNotFound(normalizedPath)
            }
            let name = Self.name(ofNormalizedPath: normalizedPath)
            destinationPath = parentPath == "/" ? "/\(name)" : "\(parentPath)/\(name)"
            try candidate.ensureNoCaseInsensitiveSiblingCollision(at: destinationPath)
        }

        candidate.contentByPath[destinationPath] = content
        try candidate.validateQuotas()
        self = candidate
    }

    private mutating func copyItemUnchecked(
        at rawSourcePath: String,
        to rawDestinationPath: String,
        overwrite: Bool
    ) throws {
        let sourcePath = try existingPath(for: rawSourcePath)
        let normalizedDestination = try Self.normalizedAbsolutePath(rawDestinationPath)
        guard sourcePath != "/" else { throw TopologyVirtualFileSystemError.cannotMutateRoot }
        guard let sourceContent = contentByPath[sourcePath] else {
            throw TopologyVirtualFileSystemError.itemNotFound(sourcePath)
        }
        let destinationPath = try canonicalDestinationPath(normalizedDestination)
        if destinationPath == sourcePath {
            if overwrite { return }
            throw TopologyVirtualFileSystemError.itemAlreadyExists(destinationPath)
        }
        if sourceContent.isDirectory,
           destinationPath.hasPrefix(sourcePath + "/") || sourcePath.hasPrefix(destinationPath + "/") {
            throw TopologyVirtualFileSystemError.cannotMoveDirectoryIntoItself(
                source: sourcePath,
                destination: destinationPath
            )
        }
        let destinationExisting = existingPathIfPresent(destinationPath)
        if let destinationExisting,
           destinationExisting != sourcePath {
            guard overwrite else { throw TopologyVirtualFileSystemError.itemAlreadyExists(destinationExisting) }
            guard let destinationContent = contentByPath[destinationExisting] else {
                throw TopologyVirtualFileSystemError.itemNotFound(destinationExisting)
            }
            guard destinationContent.isDirectory == sourceContent.isDirectory else {
                throw sourceContent.isDirectory
                    ? TopologyVirtualFileSystemError.expectedDirectory(destinationExisting)
                    : TopologyVirtualFileSystemError.expectedFile(destinationExisting)
            }
            removeItemTree(at: destinationExisting)
        }
        let destinationParent = Self.parentPath(ofNormalizedPath: destinationPath)
        guard contentByPath[destinationParent]?.isDirectory == true else {
            throw TopologyVirtualFileSystemError.parentDirectoryNotFound(destinationPath)
        }
        try ensureNoCaseInsensitiveSiblingCollision(at: destinationPath)

        let sourceEntries = contentByPath
            .filter { path, _ in path == sourcePath || path.hasPrefix(sourcePath + "/") }
            .sorted { lhs, rhs in
                let lhsDepth = lhs.key.split(separator: "/").count
                let rhsDepth = rhs.key.split(separator: "/").count
                if lhsDepth == rhsDepth { return lhs.key < rhs.key }
                return lhsDepth < rhsDepth
            }
        for (path, content) in sourceEntries {
            let suffix = String(path.dropFirst(sourcePath.count))
            contentByPath[destinationPath + suffix] = content
        }
    }

    private mutating func moveItemUnchecked(
        at rawSourcePath: String,
        to rawDestinationPath: String,
        overwrite: Bool
    ) throws {
        let sourcePath = try existingPath(for: rawSourcePath)
        let normalizedDestination = try Self.normalizedAbsolutePath(rawDestinationPath)
        guard sourcePath != "/" else { throw TopologyVirtualFileSystemError.cannotMutateRoot }
        guard let sourceContent = contentByPath[sourcePath] else {
            throw TopologyVirtualFileSystemError.itemNotFound(sourcePath)
        }
        let destinationPath = try canonicalDestinationPath(normalizedDestination)
        if destinationPath == sourcePath { return }
        if sourceContent.isDirectory,
           destinationPath.hasPrefix(sourcePath + "/") || sourcePath.hasPrefix(destinationPath + "/") {
            throw TopologyVirtualFileSystemError.cannotMoveDirectoryIntoItself(
                source: sourcePath,
                destination: destinationPath
            )
        }
        let destinationExisting = existingPathIfPresent(destinationPath)
        if let destinationExisting {
            guard overwrite else { throw TopologyVirtualFileSystemError.itemAlreadyExists(destinationExisting) }
            guard let destinationContent = contentByPath[destinationExisting] else {
                throw TopologyVirtualFileSystemError.itemNotFound(destinationExisting)
            }
            guard destinationContent.isDirectory == sourceContent.isDirectory else {
                throw sourceContent.isDirectory
                    ? TopologyVirtualFileSystemError.expectedDirectory(destinationExisting)
                    : TopologyVirtualFileSystemError.expectedFile(destinationExisting)
            }
            removeItemTree(at: destinationExisting)
        }
        let destinationParent = Self.parentPath(ofNormalizedPath: destinationPath)
        guard contentByPath[destinationParent]?.isDirectory == true else {
            throw TopologyVirtualFileSystemError.parentDirectoryNotFound(destinationPath)
        }
        try ensureNoCaseInsensitiveSiblingCollision(at: destinationPath)

        let sourceEntries = contentByPath
            .filter { path, _ in path == sourcePath || path.hasPrefix(sourcePath + "/") }
            .sorted { lhs, rhs in
                let lhsDepth = lhs.key.split(separator: "/").count
                let rhsDepth = rhs.key.split(separator: "/").count
                if lhsDepth == rhsDepth { return lhs.key < rhs.key }
                return lhsDepth < rhsDepth
            }
        for (path, _) in sourceEntries.sorted(by: { $0.key.count > $1.key.count }) {
            contentByPath.removeValue(forKey: path)
        }
        for (path, content) in sourceEntries {
            let suffix = String(path.dropFirst(sourcePath.count))
            contentByPath[destinationPath + suffix] = content
        }
    }

    private func canonicalDestinationPath(_ normalizedPath: String) throws -> String {
        if let existingPath = existingPathIfPresent(normalizedPath) {
            return existingPath
        }
        let rawParent = Self.parentPath(ofNormalizedPath: normalizedPath)
        let parentPath = try existingPath(for: rawParent)
        let name = Self.name(ofNormalizedPath: normalizedPath)
        return parentPath == "/" ? "/\(name)" : "\(parentPath)/\(name)"
    }

    private func existingPathIfPresent(_ rawPath: String) -> String? {
        try? existingPath(for: rawPath)
    }

    private func existingPath(for rawPath: String) throws -> String {
        let normalizedPath = try Self.normalizedAbsolutePath(rawPath)
        guard normalizedPath != "/" else { return "/" }
        var currentPath = "/"
        for component in normalizedPath.split(separator: "/", omittingEmptySubsequences: true) {
            let componentName = String(component)
            let candidates = contentByPath.keys.filter { candidate in
                Self.parentPath(ofNormalizedPath: candidate) == currentPath &&
                    Self.name(ofNormalizedPath: candidate).lowercased() == componentName.lowercased()
            }.sorted()
            guard candidates.count == 1, let candidate = candidates.first else {
                throw TopologyVirtualFileSystemError.itemNotFound(normalizedPath)
            }
            currentPath = candidate
        }
        return currentPath
    }

    private mutating func removeItemTree(at path: String) {
        let descendants = contentByPath.keys.filter { $0 == path || $0.hasPrefix(path + "/") }
        for descendant in descendants {
            contentByPath.removeValue(forKey: descendant)
        }
    }

    private func ensureNoCaseInsensitiveSiblingCollision(
        at path: String,
        excludingPath: String? = nil
    ) throws {
        let parent = Self.parentPath(ofNormalizedPath: path)
        let name = Self.name(ofNormalizedPath: path)
        if let existing = contentByPath.keys
            .filter({ candidate in
                candidate != excludingPath &&
                    candidate != path &&
                    Self.parentPath(ofNormalizedPath: candidate) == parent &&
                    Self.name(ofNormalizedPath: candidate).lowercased() == name.lowercased()
            })
            .sorted()
            .first
        {
            throw TopologyVirtualFileSystemError.caseInsensitiveSiblingCollision(
                existing: existing,
                attempted: path
            )
        }
    }

    private static func name(ofNormalizedPath path: String) -> String {
        guard path != "/" else { return "/" }
        return String(path.split(separator: "/").last ?? "")
    }
}
