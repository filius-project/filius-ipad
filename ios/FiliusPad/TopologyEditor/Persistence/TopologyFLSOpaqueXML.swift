import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

private enum TopologyFLSOpaqueXMLLimits {
    static let maxDepth = 128
    static let maxElementCount = 200_000
    static let maxAttributesPerElement = 64
    static let maxStartTagBytes = 64 * 1_024
    static let maxPreservedBytes = 32 * 1_024 * 1_024
    static let maxDeclarationPreambleBytes = 64 * 1_024
}

struct TopologyFLSInertXMLPath: Hashable, Equatable, CustomStringConvertible {
    let elementIndices: [Int]
    var description: String { elementIndices.map(String.init).joined(separator: ".") }
}

struct TopologyFLSSemanticSourcePlan: Equatable {
    let versionStringPath: TopologyFLSInertXMLPath?
    let nodeContainerPath: TopologyFLSInertXMLPath?
    let nodeObjectPaths: Set<TopologyFLSInertXMLPath>
    let cableObjectPaths: Set<TopologyFLSInertXMLPath>
    let documentationObjectPaths: Set<TopologyFLSInertXMLPath>
}

struct TopologyFLSOpaqueInspection {
    let normalizedData: Data
    let semanticPlan: TopologyFLSSemanticSourcePlan
    let residualCount: Int

    func content(
        recognizedNodeIDsBySourcePath: [TopologyFLSInertXMLPath: UUID],
        recognizedLinkIDsBySourcePath: [TopologyFLSInertXMLPath: UUID],
        recognizedDocumentationItemIDsBySourcePath: [TopologyFLSInertXMLPath: UUID]
    ) throws -> TopologyFLSOpaqueContent {
        guard Set(recognizedNodeIDsBySourcePath.keys).isSubset(of: semanticPlan.nodeObjectPaths),
              Set(recognizedLinkIDsBySourcePath.keys).isSubset(of: semanticPlan.cableObjectPaths),
              Set(recognizedDocumentationItemIDsBySourcePath.keys).isSubset(of: semanticPlan.documentationObjectPaths)
        else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Recognized Java GUI objects escaped their classified direct semantic containers."
            )
        }
        return TopologyFLSOpaqueContent(
            sourceConfigurationXML: normalizedData,
            recognizedNodeIDsBySourcePath: recognizedNodeIDsBySourcePath,
            recognizedLinkIDsBySourcePath: recognizedLinkIDsBySourcePath,
            recognizedDocumentationItemIDsBySourcePath: recognizedDocumentationItemIDsBySourcePath,
            residualCount: residualCount
        )
    }
}

fileprivate final class TopologyFLSInertXMLNode {
    enum Child {
        case element(TopologyFLSInertXMLNode)
        case text(String)
        case comment(String)
        case processingInstruction(target: String, data: String?)
    }

    let name: String
    let path: TopologyFLSInertXMLPath
    var attributes: [String: String]
    var children: [Child]

    init(
        name: String,
        path: TopologyFLSInertXMLPath = TopologyFLSInertXMLPath(elementIndices: []),
        attributes: [String: String] = [:],
        children: [Child] = []
    ) {
        self.name = name
        self.path = path
        self.attributes = attributes
        self.children = children
    }

    var elementChildren: [TopologyFLSInertXMLNode] {
        children.compactMap {
            if case let .element(element) = $0 { return element }
            return nil
        }
    }

    func firstElement(named name: String) -> TopologyFLSInertXMLNode? {
        elementChildren.first { $0.name == name }
    }

    func firstVoid(property: String) -> TopologyFLSInertXMLNode? {
        elementChildren.first { $0.name == "void" && $0.attributes["property"] == property }
    }

    func textValue() -> String {
        children.compactMap {
            if case let .text(text) = $0 { return text }
            return nil
        }.joined()
    }

    func deepCopy() -> TopologyFLSInertXMLNode {
        TopologyFLSInertXMLNode(
            name: name,
            path: path,
            attributes: attributes,
            children: children.map(TopologyFLSOpaqueXMLMerger.copyChild)
        )
    }
}

private final class TopologyFLSInertXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var stack: [TopologyFLSInertXMLNode] = []
    private var nextElementChildIndexStack: [Int] = []
    private(set) var root: TopologyFLSInertXMLNode?
    private var elementCount = 0
    private var retainedBytes = 0
    private var policyError: TopologyFLSCompatibilityError?

    init(data: Data) { self.data = data }

    func parse() throws -> TopologyFLSInertXMLNode {
        guard data.count <= TopologyFLSOpaqueXMLLimits.maxPreservedBytes else {
            throw quotaError("Lossless XML preservation exceeds \(TopologyFLSOpaqueXMLLimits.maxPreservedBytes) input bytes.")
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), policyError == nil, let root else {
            if let policyError { throw policyError }
            throw TopologyFLSCompatibilityError(
                code: .malformedConfigurationXML,
                detail: "Failed inert XML preservation parse at line \(parser.lineNumber): \(parser.parserError?.localizedDescription ?? "unknown XML parser error")"
            )
        }
        return root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard policyError == nil else { return }
        elementCount += 1
        let attributeBytes = attributeDict.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
        guard addBytes(elementName.utf8.count + attributeBytes),
              stack.count < TopologyFLSOpaqueXMLLimits.maxDepth,
              elementCount <= TopologyFLSOpaqueXMLLimits.maxElementCount,
              attributeDict.count <= TopologyFLSOpaqueXMLLimits.maxAttributesPerElement
        else {
            policyError = quotaError("Lossless XML preservation quota exceeded while reading elements or attributes.")
            parser.abortParsing()
            return
        }
        let path: TopologyFLSInertXMLPath
        if stack.isEmpty {
            path = TopologyFLSInertXMLPath(elementIndices: [])
        } else {
            let index = nextElementChildIndexStack[nextElementChildIndexStack.count - 1]
            nextElementChildIndexStack[nextElementChildIndexStack.count - 1] += 1
            path = TopologyFLSInertXMLPath(elementIndices: stack.last!.path.elementIndices + [index])
        }
        let node = TopologyFLSInertXMLNode(name: elementName, path: path, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(.element(node))
        } else if root == nil {
            root = node
        } else {
            policyError = TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Lossless XML preservation found multiple document roots."
            )
            parser.abortParsing()
            return
        }
        stack.append(node)
        nextElementChildIndexStack.append(0)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard addBytes(string.utf8.count) else {
            policyError = quotaError("Lossless XML preservation quota exceeded while reading text.")
            parser.abortParsing()
            return
        }
        stack.last?.children.append(.text(string))
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        guard addBytes(data.count) else {
            policyError = quotaError("Lossless XML preservation quota exceeded while reading CDATA.")
            parser.abortParsing()
            return
        }
        stack.last?.children.append(.text(String(decoding: data, as: UTF8.self)))
    }

    func parser(_ parser: XMLParser, foundComment comment: String) {
        guard addBytes(comment.utf8.count) else {
            policyError = quotaError("Lossless XML preservation quota exceeded while reading comments.")
            parser.abortParsing()
            return
        }
        stack.last?.children.append(.comment(comment))
    }

    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        let byteCount = target.utf8.count + (data?.utf8.count ?? 0)
        guard addBytes(byteCount) else {
            policyError = quotaError("Lossless XML preservation quota exceeded while reading processing instructions.")
            parser.abortParsing()
            return
        }
        stack.last?.children.append(.processingInstruction(target: target, data: data))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard stack.last?.name == elementName else {
            policyError = TopologyFLSCompatibilityError(
                code: .malformedConfigurationXML,
                detail: "Lossless XML preservation observed an unbalanced element."
            )
            parser.abortParsing()
            return
        }
        stack.removeLast()
        nextElementChildIndexStack.removeLast()
    }

    private func addBytes(_ amount: Int) -> Bool {
        let (next, overflow) = retainedBytes.addingReportingOverflow(amount)
        guard !overflow, next <= TopologyFLSOpaqueXMLLimits.maxPreservedBytes else { return false }
        retainedBytes = next
        return true
    }

    private func quotaError(_ detail: String) -> TopologyFLSCompatibilityError {
        TopologyFLSCompatibilityError(code: .unsupportedConfigurationStructure, detail: detail)
    }
}

private struct TopologyFLSTopLevelRoles {
    let versionString: TopologyFLSInertXMLNode?
    let nodeContainer: TopologyFLSInertXMLNode?
    let cableContainer: TopologyFLSInertXMLNode?
    let documentationContainer: TopologyFLSInertXMLNode?

    var consumed: Set<ObjectIdentifier> {
        Set([versionString, nodeContainer, cableContainer, documentationContainer]
            .compactMap { $0 }.map(ObjectIdentifier.init))
    }
}

fileprivate struct TopologyFLSBoundedXMLSink {
    private(set) var data = Data()

    mutating func appendLiteral(_ value: String) throws {
        try appendBytes(value.utf8)
    }

    mutating func appendEscapedAttribute(_ value: String) throws {
        try appendEscaped(value, replacements: [
            0x26: "&amp;", 0x3C: "&lt;", 0x22: "&quot;",
        ])
    }

    mutating func appendEscapedText(_ value: String) throws {
        // '>' remains escaped for deterministic compatibility with prior exports; quotes and
        // apostrophes are intentionally not escaped in text context.
        try appendEscaped(value, replacements: [
            0x26: "&amp;", 0x3C: "&lt;", 0x3E: "&gt;",
        ])
    }

    private mutating func appendEscaped(_ value: String, replacements: [UInt8: String]) throws {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(8_192)
        for byte in value.utf8 {
            if let replacement = replacements[byte] {
                if !buffer.isEmpty { try appendBytes(buffer); buffer.removeAll(keepingCapacity: true) }
                try appendLiteral(replacement)
            } else {
                buffer.append(byte)
                if buffer.count == 8_192 {
                    try appendBytes(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        }
        if !buffer.isEmpty { try appendBytes(buffer) }
    }

    private mutating func appendBytes<C: Collection>(_ bytes: C) throws where C.Element == UInt8 {
        let (next, overflow) = data.count.addingReportingOverflow(bytes.count)
        guard !overflow, next <= TopologyFLSOpaqueXMLLimits.maxPreservedBytes else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Serialized lossless FILIUS XML exceeds \(TopologyFLSOpaqueXMLLimits.maxPreservedBytes) bytes."
            )
        }
        data.append(contentsOf: bytes)
    }
}

private struct TopologyFLSLexicalPreflight {
    private enum Encoding { case utf8, utf16LittleEndian, utf16BigEndian }
    private struct Unit { let scalar: UInt32; let next: Int }
    let data: Data

    func validate() throws {
        let encoding: Encoding
        let startOffset: Int
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { encoding = .utf8; startOffset = 3 }
        else if data.starts(with: [0xFF, 0xFE]) { encoding = .utf16LittleEndian; startOffset = 2 }
        else if data.starts(with: [0xFE, 0xFF]) { encoding = .utf16BigEndian; startOffset = 2 }
        else if data.count >= 4, data[0] == 0x3C, data[1] == 0, data[2] == 0x3F, data[3] == 0 {
            encoding = .utf16LittleEndian; startOffset = 0
        } else if data.count >= 4, data[0] == 0, data[1] == 0x3C, data[2] == 0, data[3] == 0x3F {
            encoding = .utf16BigEndian; startOffset = 0
        } else { encoding = .utf8; startOffset = 0 }

        func fail(_ detail: String) throws -> Never {
            throw TopologyFLSCompatibilityError(code: .unsupportedConfigurationStructure, detail: detail)
        }
        func unit(at offset: Int) -> Unit? {
            guard offset < data.count else { return nil }
            switch encoding {
            case .utf8:
                let first = data[offset]
                if first < 0x80 { return Unit(scalar: UInt32(first), next: offset + 1) }
                let length: Int
                let initial: UInt32
                let minimum: UInt32
                if (0xC2...0xDF).contains(first) { length = 2; initial = UInt32(first & 0x1F); minimum = 0x80 }
                else if (0xE0...0xEF).contains(first) { length = 3; initial = UInt32(first & 0x0F); minimum = 0x800 }
                else if (0xF0...0xF4).contains(first) { length = 4; initial = UInt32(first & 0x07); minimum = 0x10000 }
                else { return Unit(scalar: 0xFFFD, next: offset + 1) }
                guard offset + length <= data.count else { return Unit(scalar: 0xFFFD, next: data.count) }
                var scalar = initial
                for index in 1..<length {
                    let byte = data[offset + index]
                    guard byte & 0xC0 == 0x80 else { return Unit(scalar: 0xFFFD, next: offset + 1) }
                    scalar = (scalar << 6) | UInt32(byte & 0x3F)
                }
                guard scalar >= minimum, scalar <= 0x10FFFF, !(0xD800...0xDFFF).contains(scalar) else {
                    return Unit(scalar: 0xFFFD, next: offset + 1)
                }
                return Unit(scalar: scalar, next: offset + length)
            case .utf16LittleEndian, .utf16BigEndian:
                guard offset + 2 <= data.count else { return Unit(scalar: 0xFFFD, next: data.count) }
                func codeUnit(_ at: Int) -> UInt16 {
                    if encoding == .utf16LittleEndian { return UInt16(data[at]) | UInt16(data[at + 1]) << 8 }
                    return UInt16(data[at]) << 8 | UInt16(data[at + 1])
                }
                let first = codeUnit(offset)
                if (0xD800...0xDBFF).contains(first), offset + 4 <= data.count {
                    let second = codeUnit(offset + 2)
                    if (0xDC00...0xDFFF).contains(second) {
                        let scalar = 0x10000 + (UInt32(first - 0xD800) << 10) + UInt32(second - 0xDC00)
                        return Unit(scalar: scalar, next: offset + 4)
                    }
                }
                return Unit(scalar: UInt32(first), next: offset + 2)
            }
        }
        func match(_ token: [UInt32], at start: Int, caseInsensitive: Bool = false) -> Int? {
            var cursor = start
            for wantedValue in token {
                guard let next = unit(at: cursor) else { return nil }
                var actual = next.scalar
                var wanted = wantedValue
                if caseInsensitive {
                    if (0x61...0x7A).contains(actual) { actual -= 0x20 }
                    if (0x61...0x7A).contains(wanted) { wanted -= 0x20 }
                }
                guard actual == wanted else { return nil }
                cursor = next.next
            }
            return cursor
        }
        func ascii(_ value: String) -> [UInt32] { value.unicodeScalars.map(\.value) }
        func find(_ token: String, from start: Int, boundedFrom tagStart: Int? = nil) throws -> Int? {
            let expected = ascii(token)
            var cursor = start
            while let current = unit(at: cursor) {
                if let tagStart { try enforceTagLimit(tagStart, current.next) }
                if let end = match(expected, at: cursor) {
                    if let tagStart { try enforceTagLimit(tagStart, end) }
                    return end
                }
                cursor = current.next
            }
            return nil
        }
        func enforceTagLimit(_ start: Int, _ cursor: Int) throws {
            guard cursor - start <= TopologyFLSOpaqueXMLLimits.maxStartTagBytes else {
                try fail("XML tag exceeds the \(TopologyFLSOpaqueXMLLimits.maxStartTagBytes)-byte lexical limit.")
            }
        }
        func isWhitespace(_ scalar: UInt32) -> Bool { scalar == 0x20 || scalar == 0x09 || scalar == 0x0A || scalar == 0x0D }

        var cursor = startOffset
        var depth = 0
        var elementCount = 0
        var sawRoot = false
        while let current = unit(at: cursor) {
            guard current.scalar == 0x3C else { cursor = current.next; continue }
            let tagStart = cursor
            guard let marker = unit(at: current.next) else { try fail("Unterminated XML markup.") }
            if marker.scalar == 0x3F {
                guard let end = try find("?>", from: marker.next, boundedFrom: tagStart) else { try fail("Unterminated XML processing instruction.") }
                try enforceTagLimit(tagStart, end)
                cursor = end
                continue
            }
            if marker.scalar == 0x21 {
                if let after = match(ascii("!--"), at: current.next) {
                    guard let end = try find("-->", from: after) else { try fail("Unterminated XML comment.") }
                    cursor = end
                    continue
                }
                if let after = match(ascii("![CDATA["), at: current.next) {
                    guard let end = try find("]]>", from: after) else { try fail("Unterminated XML CDATA section.") }
                    cursor = end
                    continue
                }
                if match(ascii("!DOCTYPE"), at: current.next, caseInsensitive: true) != nil
                    || match(ascii("!ENTITY"), at: current.next, caseInsensitive: true) != nil {
                    try fail("Lossless XML preservation rejects DTD and entity declarations.")
                }
                try fail("Lossless XML preservation rejects unsupported declarations.")
            }

            let closing = marker.scalar == 0x2F
            var nameCursor = closing ? marker.next : current.next
            var nameScalars: [UInt32] = []
            while let value = unit(at: nameCursor) {
                try enforceTagLimit(tagStart, value.next)
                if isWhitespace(value.scalar) || value.scalar == 0x2F || value.scalar == 0x3E { break }
                nameScalars.append(value.scalar)
                nameCursor = value.next
            }
            guard !nameScalars.isEmpty else { try fail("XML markup has an empty element name.") }

            var scan = nameCursor
            var quote: UInt32?
            var attributeCount = 0
            var lastSignificant: UInt32 = 0
            var terminated = false
            while let value = unit(at: scan) {
                try enforceTagLimit(tagStart, value.next)
                if let active = quote {
                    if value.scalar == active { quote = nil }
                } else if value.scalar == 0x22 || value.scalar == 0x27 { quote = value.scalar }
                else if value.scalar == 0x3D, !closing {
                    attributeCount += 1
                    guard attributeCount <= TopologyFLSOpaqueXMLLimits.maxAttributesPerElement else {
                        try fail("XML start tag exceeds the \(TopologyFLSOpaqueXMLLimits.maxAttributesPerElement)-attribute limit.")
                    }
                } else if value.scalar == 0x3E {
                    terminated = true
                    scan = value.next
                    break
                }
                if !isWhitespace(value.scalar), value.scalar != 0x3E { lastSignificant = value.scalar }
                scan = value.next
            }
            guard terminated, quote == nil else { try fail("Unterminated XML tag or attribute value.") }
            if closing {
                guard depth > 0 else { try fail("XML has an unmatched closing element.") }
                depth -= 1
            } else {
                elementCount += 1
                guard elementCount <= TopologyFLSOpaqueXMLLimits.maxElementCount else {
                    try fail("XML exceeds the \(TopologyFLSOpaqueXMLLimits.maxElementCount)-element limit.")
                }
                if !sawRoot {
                    guard tagStart <= TopologyFLSOpaqueXMLLimits.maxDeclarationPreambleBytes,
                          nameScalars == ascii("java") else { try fail("Expected a Java XMLDecoder root element within the bounded preamble.") }
                    sawRoot = true
                }
                if lastSignificant != 0x2F {
                    depth += 1
                    guard depth <= TopologyFLSOpaqueXMLLimits.maxDepth else {
                        try fail("XML exceeds the \(TopologyFLSOpaqueXMLLimits.maxDepth)-element nesting limit.")
                    }
                }
            }
            cursor = scan
        }
        guard sawRoot, depth == 0 else { try fail("XML document is missing a balanced Java root.") }
    }
}

enum TopologyFLSOpaqueXMLPreserver {
    static func preflight(_ data: Data) throws {
        guard data.count <= TopologyFLSOpaqueXMLLimits.maxPreservedBytes else {
            throw TopologyFLSCompatibilityError(
                code: .unsupportedConfigurationStructure,
                detail: "Lossless FILIUS configuration exceeds \(TopologyFLSOpaqueXMLLimits.maxPreservedBytes) bytes."
            )
        }
        try TopologyFLSLexicalPreflight(data: data).validate()
    }

    static func inspect(from data: Data) throws -> TopologyFLSOpaqueInspection {
        let root = try TopologyFLSInertXMLParser(data: data).parse()
        try validateSemanticRoleUniqueness(root)
        let roles = classifyTopLevelRoles(root)
        let plan = TopologyFLSSemanticSourcePlan(
            versionStringPath: roles.versionString?.path,
            nodeContainerPath: roles.nodeContainer?.path,
            nodeObjectPaths: semanticObjectPaths(in: roles.nodeContainer, className: "filius.gui.netzwerksicht.GUIKnotenItem"),
            cableObjectPaths: semanticObjectPaths(in: roles.cableContainer, className: "filius.gui.netzwerksicht.GUIKabelItem"),
            documentationObjectPaths: semanticObjectPaths(in: roles.documentationContainer, className: "filius.gui.netzwerksicht.GUIDocuItem")
        )
        var sink = TopologyFLSBoundedXMLSink()
        try sink.appendLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        try serialize(root, into: &sink)
        try sink.appendLiteral("\n")
        return TopologyFLSOpaqueInspection(
            normalizedData: sink.data,
            semanticPlan: plan,
            residualCount: countResiduals(in: root)
        )
    }

    private static func semanticObjectPaths(
        in container: TopologyFLSInertXMLNode?,
        className: String
    ) -> Set<TopologyFLSInertXMLPath> {
        Set((container.map(additions) ?? []).compactMap { addition in
            guard let object = addition.firstElement(named: "object"), object.attributes["class"] == className else { return nil }
            return object.path
        })
    }

    private static func validateSemanticRoleUniqueness(_ root: TopologyFLSInertXMLNode) throws {
        let containers = root.elementChildren.filter {
            $0.name == "object"
                && ($0.attributes["class"] == "java.util.LinkedList"
                    || $0.attributes["class"] == "java.util.ArrayList")
        }
        let classes = [
            "filius.gui.netzwerksicht.GUIKnotenItem",
            "filius.gui.netzwerksicht.GUIKabelItem",
            "filius.gui.netzwerksicht.GUIDocuItem",
        ]
        var claimedContainers = Set<ObjectIdentifier>()
        for className in classes {
            let matches = containers.filter { container in
                additions(in: container).contains {
                    $0.firstElement(named: "object")?.attributes["class"] == className
                }
            }
            guard matches.count <= 1 else {
                throw TopologyFLSCompatibilityError(
                    code: .unsupportedConfigurationStructure,
                    detail: "Lossless FILIUS XML has ambiguous semantic containers for \(className)."
                )
            }
            if let match = matches.first {
                guard claimedContainers.insert(ObjectIdentifier(match)).inserted else {
                    throw TopologyFLSCompatibilityError(
                        code: .unsupportedConfigurationStructure,
                        detail: "Lossless FILIUS XML combines incompatible semantic container roles."
                    )
                }
            }
        }
    }

    fileprivate static func classifyTopLevelRoles(_ root: TopologyFLSInertXMLNode) -> TopologyFLSTopLevelRoles {
        let elements = root.elementChildren
        let versionString = elements.first {
            $0.name == "string" && $0.textValue().trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Filius version:")
        }
        let linkedLists = elements.filter { $0.name == "object" && $0.attributes["class"] == "java.util.LinkedList" }
        let arrayLists = elements.filter { $0.name == "object" && $0.attributes["class"] == "java.util.ArrayList" }
        func contains(_ container: TopologyFLSInertXMLNode, _ className: String) -> Bool {
            additions(in: container).contains {
                $0.firstElement(named: "object")?.attributes["class"] == className
            }
        }
        var nodes = linkedLists.first { contains($0, "filius.gui.netzwerksicht.GUIKnotenItem") }
        var cables = linkedLists.first { contains($0, "filius.gui.netzwerksicht.GUIKabelItem") }
        var docs = arrayLists.first { contains($0, "filius.gui.netzwerksicht.GUIDocuItem") }

        // Empty projects and containers holding only unknown future beans have no recognized
        // child class to reveal their role. FILIUS still writes the two top-level linked
        // lists in canonical node/cable order, so use that order only when there are exactly
        // two candidates. Extra collections remain deliberately unclassified and inert.
        if linkedLists.count == 2 {
            if nodes == nil, cables == nil {
                nodes = linkedLists[0]
                cables = linkedLists[1]
            } else if nodes == nil, let cables {
                nodes = linkedLists.first { $0 !== cables }
            } else if cables == nil, let nodes {
                cables = linkedLists.first { $0 !== nodes }
            }
        }
        if docs == nil, arrayLists.count == 1 {
            docs = arrayLists[0]
        }

        return TopologyFLSTopLevelRoles(
            versionString: versionString,
            nodeContainer: nodes,
            cableContainer: cables,
            documentationContainer: docs
        )
    }

    fileprivate static func classifyGeneratedTopLevelRoles(_ root: TopologyFLSInertXMLNode) -> TopologyFLSTopLevelRoles {
        let semantic = classifyTopLevelRoles(root)
        let elements = root.elementChildren
        let linkedLists = elements.filter { $0.name == "object" && $0.attributes["class"] == "java.util.LinkedList" }
        let arrayLists = elements.filter { $0.name == "object" && $0.attributes["class"] == "java.util.ArrayList" }
        return TopologyFLSTopLevelRoles(
            versionString: semantic.versionString,
            nodeContainer: semantic.nodeContainer ?? (linkedLists.count == 2 ? linkedLists[0] : nil),
            cableContainer: semantic.cableContainer ?? (linkedLists.count == 2 ? linkedLists[1] : nil),
            documentationContainer: semantic.documentationContainer ?? (arrayLists.count == 1 ? arrayLists[0] : nil)
        )
    }

    fileprivate static func isStructurallyEmptyGenericCollection(_ node: TopologyFLSInertXMLNode) -> Bool {
        guard node.name == "object",
              let className = node.attributes["class"],
              className == "java.util.LinkedList" || className == "java.util.ArrayList",
              Set(node.attributes.keys).isSubset(of: ["class"])
        else { return false }
        return node.children.allSatisfy {
            if case let .text(text) = $0 { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return false
        }
    }

    fileprivate static func additions(in container: TopologyFLSInertXMLNode) -> [TopologyFLSInertXMLNode] {
        container.elementChildren.filter { $0.name == "void" && $0.attributes["method"] == "add" }
    }

    fileprivate static func serialize(_ node: TopologyFLSInertXMLNode, into sink: inout TopologyFLSBoundedXMLSink) throws {
        try sink.appendLiteral("<\(node.name)")
        for key in node.attributes.keys.sorted() {
            try sink.appendLiteral(" \(key)=\"")
            try sink.appendEscapedAttribute(node.attributes[key] ?? "")
            try sink.appendLiteral("\"")
        }
        if node.children.isEmpty {
            try sink.appendLiteral("/>")
            return
        }
        try sink.appendLiteral(">")
        for child in node.children {
            switch child {
            case let .element(element): try serialize(element, into: &sink)
            case let .text(text): try sink.appendEscapedText(text)
            case let .comment(comment):
                try sink.appendLiteral("<!--")
                try sink.appendLiteral(comment)
                try sink.appendLiteral("-->")
            case let .processingInstruction(target, data):
                try sink.appendLiteral("<?\(target)")
                if let data, !data.isEmpty { try sink.appendLiteral(" \(data)") }
                try sink.appendLiteral("?>")
            }
        }
        try sink.appendLiteral("</\(node.name)>")
    }

    private static func countResiduals(in root: TopologyFLSInertXMLNode) -> Int {
        let roles = classifyTopLevelRoles(root)
        var count = countUnknownClasses(in: root)
        count += root.attributes.keys.filter { $0 != "class" && $0 != "version" }.count
        count += root.children.reduce(into: 0) { total, child in
            switch child {
            case let .element(element):
                if !roles.consumed.contains(ObjectIdentifier(element)),
                   !isStructurallyEmptyGenericCollection(element) { total += 1 }
            case .comment, .processingInstruction: total += 1
            case .text: break
            }
        }
        return count
    }

    private static func countUnknownClasses(in node: TopologyFLSInertXMLNode) -> Int {
        let knownPrefixes = ["java.", "javax.", "filius."]
        var count = 0
        if let className = node.attributes["class"], !knownPrefixes.contains(where: className.hasPrefix) { count += 1 }
        for child in node.elementChildren { count += countUnknownClasses(in: child) }
        return count
    }
}

private enum TopologyFLSXMLPatchContext {
    case node, imageLabel, rectangle, hardware, networkInterfaceCollection, nativePortCollection, systemSoftware
    case fileSystem, fileSystemRoot
    case cable, cableHardware, cableEndpointCollection, cablePanel, documentation, color, font
    case application(String)
}

enum TopologyFLSOpaqueXMLMerger {
    private static let recognizedApplicationClasses: Set<String> = [
        "filius.software.www.WebServer", "filius.software.www.WebBrowser",
        "filius.software.dns.DNSServer", "filius.software.email.EmailAnwendung",
        "filius.software.email.EmailServer", "filius.software.dateiaustausch.PeerToPeerAnwendung",
        "filius.software.firewall.Firewall", "filius.software.nat.NatGateway",
    ]

    static func merge(
        generatedConfiguration: Data,
        opaqueContent: TopologyFLSOpaqueContent,
        state: TopologyEditorState
    ) throws -> Data {
        guard let sourceData = opaqueContent.sourceConfigurationXML else { return generatedConfiguration }
        let sourceRoot = try TopologyFLSInertXMLParser(data: sourceData).parse()
        let generatedRoot = try TopologyFLSInertXMLParser(data: generatedConfiguration).parse()
        guard sourceRoot.name == "java", generatedRoot.name == "java" else {
            throw unsafe("Lossless merge requires Java XMLDecoder roots.")
        }

        var sourceIdentifierList: [String] = []
        collectIdentifierList(in: sourceRoot, into: &sourceIdentifierList)
        let sourceIdentifiers = Set(sourceIdentifierList)
        guard sourceIdentifiers.count == sourceIdentifierList.count else {
            throw unsafe("Lossless FILIUS XML contains duplicate JavaBean identifiers.")
        }
        var generatedNamespace: [String: String] = [:]
        namespaceGeneratedIdentifiers(in: generatedRoot, avoiding: sourceIdentifiers, rewrite: &generatedNamespace)

        let sourceRoles = TopologyFLSOpaqueXMLPreserver.classifyTopLevelRoles(sourceRoot)
        let generatedRoles = TopologyFLSOpaqueXMLPreserver.classifyGeneratedTopLevelRoles(generatedRoot)
        guard let generatedNodes = generatedRoles.nodeContainer,
              let generatedCables = generatedRoles.cableContainer,
              let generatedDocumentation = generatedRoles.documentationContainer
        else {
            throw unsafe("Generated FILIUS XML is missing a semantic node, cable, or documentation container.")
        }

        var generatedToSourceIdentifiers: [String: String] = [:]
        let mergedNodes = try mergeNodeContainer(
            source: sourceRoles.nodeContainer,
            generated: generatedNodes,
            opaqueContent: opaqueContent,
            state: state,
            identifierMap: &generatedToSourceIdentifiers
        )
        let mergedCables = try mergeCableContainer(
            source: sourceRoles.cableContainer,
            generated: generatedCables,
            opaqueContent: opaqueContent,
            state: state,
            identifierMap: &generatedToSourceIdentifiers
        )
        let mergedDocumentation = try mergeDocumentationContainer(
            source: sourceRoles.documentationContainer,
            generated: generatedDocumentation,
            opaqueContent: opaqueContent,
            state: state,
            identifierMap: &generatedToSourceIdentifiers
        )

        let outputRoot = generatedRoot.deepCopy()
        for (key, value) in sourceRoot.attributes where key != "class" && key != "version" {
            outputRoot.attributes[key] = value
        }
        let replacements: [ObjectIdentifier: TopologyFLSInertXMLNode] = [
            ObjectIdentifier(generatedNodes): mergedNodes,
            ObjectIdentifier(generatedCables): mergedCables,
            ObjectIdentifier(generatedDocumentation): mergedDocumentation,
        ]
        var outputChildren: [TopologyFLSInertXMLNode.Child] = []
        for child in generatedRoot.children {
            if case let .element(element) = child,
               let replacement = replacements[ObjectIdentifier(element)]
            {
                outputChildren.append(.element(replacement))
            } else {
                outputChildren.append(copyChild(child))
            }
        }
        let consumedSource = sourceRoles.consumed
        for child in sourceRoot.children {
            switch child {
            case let .element(element) where !consumedSource.contains(ObjectIdentifier(element)):
                if !TopologyFLSOpaqueXMLPreserver.isStructurallyEmptyGenericCollection(element) {
                    outputChildren.append(.element(element.deepCopy()))
                }
            case .comment, .processingInstruction:
                outputChildren.append(copyChild(child))
            default:
                break
            }
        }
        outputRoot.children = outputChildren
        rewriteIdentifiers(in: outputRoot, using: generatedToSourceIdentifiers)
        try validateIdentifierClosure(in: outputRoot)

        try validateCablePortReferences(nodeContainer: mergedNodes, cableContainer: mergedCables)
        var sink = TopologyFLSBoundedXMLSink()
        try sink.appendLiteral("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        try TopologyFLSOpaqueXMLPreserver.serialize(outputRoot, into: &sink)
        try sink.appendLiteral("\n")
        return sink.data
    }

    private static func mergeNodeContainer(
        source: TopologyFLSInertXMLNode?,
        generated: TopologyFLSInertXMLNode,
        opaqueContent: TopologyFLSOpaqueContent,
        state: TopologyEditorState,
        identifierMap: inout [String: String]
    ) throws -> TopologyFLSInertXMLNode {
        let result = mergeContainerAttributes(source: source, generated: generated)
        let sourceAdditions = source.map(TopologyFLSOpaqueXMLPreserver.additions) ?? []
        let sourceNative = sourceAdditions.filter {
            $0.firstElement(named: "object")?.attributes["class"] == "filius.gui.netzwerksicht.GUIKnotenItem"
        }
        let sourceByID = dictionaryByNativeID(sourceNative, idsByPath: opaqueContent.recognizedNodeIDsBySourcePath)
        let sortedNodes = state.graph.nodes.filter { $0.kind != .unsupported }.sorted { $0.id.uuidString < $1.id.uuidString }
        let generatedNative = TopologyFLSOpaqueXMLPreserver.additions(in: generated).filter {
            $0.firstElement(named: "object")?.attributes["class"] == "filius.gui.netzwerksicht.GUIKnotenItem"
        }
        guard generatedNative.count == sortedNodes.count else { throw unsafe("Generated node container does not match native state.") }

        var additions: [TopologyFLSInertXMLNode] = []
        for (index, node) in sortedNodes.enumerated() {
            if let original = sourceByID[node.id] {
                additions.append(try patch(original, with: generatedNative[index], context: .node, identifierMap: &identifierMap))
            } else {
                additions.append(generatedNative[index].deepCopy())
            }
        }
        additions.append(contentsOf: residualAdditions(
            sourceAdditions,
            recognizedClass: "filius.gui.netzwerksicht.GUIKnotenItem",
            idsByRecognizedPath: opaqueContent.recognizedNodeIDsBySourcePath
        ))
        setAdditions(additions, in: result, preservingFrom: source)
        return result
    }

    private static func mergeCableContainer(
        source: TopologyFLSInertXMLNode?,
        generated: TopologyFLSInertXMLNode,
        opaqueContent: TopologyFLSOpaqueContent,
        state: TopologyEditorState,
        identifierMap: inout [String: String]
    ) throws -> TopologyFLSInertXMLNode {
        let result = mergeContainerAttributes(source: source, generated: generated)
        let sourceAdditions = source.map(TopologyFLSOpaqueXMLPreserver.additions) ?? []
        let sourceNative = sourceAdditions.filter {
            $0.firstElement(named: "object")?.attributes["class"] == "filius.gui.netzwerksicht.GUIKabelItem"
        }
        let sourceByID = dictionaryByNativeID(sourceNative, idsByPath: opaqueContent.recognizedLinkIDsBySourcePath)
        let exportedNodeIDs = Set(state.graph.nodes.filter { $0.kind != .unsupported }.map(\.id))
        let sortedLinks = (state.graph.links + state.wirelessAssociations().map(\.runtimeLink))
            .filter { exportedNodeIDs.contains($0.sourceNodeID) && exportedNodeIDs.contains($0.targetNodeID) }
            .sorted {
                if $0.id == $1.id { return $0.sourcePortID.uuidString < $1.sourcePortID.uuidString }
                return $0.id.uuidString < $1.id.uuidString
            }
        let generatedNative = TopologyFLSOpaqueXMLPreserver.additions(in: generated).filter {
            $0.firstElement(named: "object")?.attributes["class"] == "filius.gui.netzwerksicht.GUIKabelItem"
        }
        guard generatedNative.count == sortedLinks.count else { throw unsafe("Generated cable container does not match native state.") }

        var additions: [TopologyFLSInertXMLNode] = []
        for (index, link) in sortedLinks.enumerated() {
            if let original = sourceByID[link.id] {
                additions.append(try patch(original, with: generatedNative[index], context: .cable, identifierMap: &identifierMap))
            } else {
                additions.append(generatedNative[index].deepCopy())
            }
        }
        additions.append(contentsOf: residualAdditions(
            sourceAdditions,
            recognizedClass: "filius.gui.netzwerksicht.GUIKabelItem",
            idsByRecognizedPath: opaqueContent.recognizedLinkIDsBySourcePath
        ))
        setAdditions(additions, in: result, preservingFrom: source)
        return result
    }

    private static func mergeDocumentationContainer(
        source: TopologyFLSInertXMLNode?,
        generated: TopologyFLSInertXMLNode,
        opaqueContent: TopologyFLSOpaqueContent,
        state: TopologyEditorState,
        identifierMap: inout [String: String]
    ) throws -> TopologyFLSInertXMLNode {
        let result = mergeContainerAttributes(source: source, generated: generated)
        let sourceAdditions = source.map(TopologyFLSOpaqueXMLPreserver.additions) ?? []
        let sourceNative = sourceAdditions.filter {
            $0.firstElement(named: "object")?.attributes["class"] == "filius.gui.netzwerksicht.GUIDocuItem"
        }
        let sourceByID = dictionaryByNativeID(
            sourceNative,
            idsByPath: opaqueContent.recognizedDocumentationItemIDsBySourcePath
        )
        let sortedItems = state.documentationItems.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.uuidString < $1.id.uuidString
        }.filter(\.hasSafeRenderValues)
        let generatedNative = TopologyFLSOpaqueXMLPreserver.additions(in: generated).filter {
            $0.firstElement(named: "object")?.attributes["class"] == "filius.gui.netzwerksicht.GUIDocuItem"
        }
        guard generatedNative.count == sortedItems.count else { throw unsafe("Generated documentation container does not match native state.") }

        var additions: [TopologyFLSInertXMLNode] = []
        for (index, item) in sortedItems.enumerated() {
            if let original = sourceByID[item.id] {
                additions.append(try patch(original, with: generatedNative[index], context: .documentation, identifierMap: &identifierMap))
            } else {
                additions.append(generatedNative[index].deepCopy())
            }
        }
        additions.append(contentsOf: residualAdditions(
            sourceAdditions,
            recognizedClass: "filius.gui.netzwerksicht.GUIDocuItem",
            idsByRecognizedPath: opaqueContent.recognizedDocumentationItemIDsBySourcePath
        ))
        setAdditions(additions, in: result, preservingFrom: source)
        return result
    }

    private static func patch(
        _ source: TopologyFLSInertXMLNode,
        with generated: TopologyFLSInertXMLNode,
        context: TopologyFLSXMLPatchContext,
        identifierMap: inout [String: String]
    ) throws -> TopologyFLSInertXMLNode {
        let result = source.deepCopy()
        mergeAttributes(source: source, generated: generated, result: result, identifierMap: &identifierMap)
        switch context {
        case .node:
            try patchSingleObject(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, nestedMap in
                try mergePropertyChildren(
                    sourceObject, generatedObject, objectResult,
                    recognized: ["typ", "bounds", "imageLabel", "knoten"],
                    identifierMap: &nestedMap
                ) {
                    if $0 == "imageLabel" { return .imageLabel }
                    if $0 == "knoten" { return .hardware }
                    return nil
                }
            }
        case .imageLabel:
            try patchSingleObject(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, nestedMap in
                try mergePropertyChildren(
                    sourceObject, generatedObject, objectResult,
                    recognized: ["bounds", "text", "typ"],
                    identifierMap: &nestedMap
                ) { $0 == "bounds" ? .rectangle : nil }
            }
        case .rectangle:
            try patchVoidObjectOrSelf(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, _ in
                mergeRectangleChildren(sourceObject, generatedObject, objectResult)
            }
        case .hardware:
            try patchVoidObjectOrSelf(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, nestedMap in
                try mergePropertyChildren(
                    sourceObject, generatedObject, objectResult,
                    recognized: ["name", "netzwerkInterfaces", "anschluesse", "systemSoftware", "maxLayerOfOperation"],
                    identifierMap: &nestedMap
                ) {
                    if $0 == "netzwerkInterfaces" { return .networkInterfaceCollection }
                    if $0 == "anschluesse" { return .nativePortCollection }
                    if $0 == "systemSoftware" { return .systemSoftware }
                    return nil
                }
            }
        case .networkInterfaceCollection, .nativePortCollection, .cableEndpointCollection:
            try mergeIndexedChildren(source, generated, result, context: context, identifierMap: &identifierMap)
        case .systemSoftware:
            try mergeSystemSoftware(source, generated, result, identifierMap: &identifierMap)
        case .fileSystem:
            try mergePropertyChildren(
                source, generated, result,
                recognized: ["arbeitsVerzeichnis"],
                identifierMap: &identifierMap
            ) { _ in .fileSystemRoot }
        case .fileSystemRoot:
            mergeAttributes(source: source, generated: generated, result: result, identifierMap: &identifierMap)
            result.children = generated.children.map(copyChild)
        case .cable:
            try patchSingleObject(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, nestedMap in
                try mergePropertyChildren(
                    sourceObject, generatedObject, objectResult,
                    recognized: ["dasKabel", "kabelpanel"],
                    identifierMap: &nestedMap
                ) { $0 == "dasKabel" ? .cableHardware : .cablePanel }
            }
        case .cableHardware:
            try patchVoidObjectOrSelf(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, nestedMap in
                try mergePropertyChildren(
                    sourceObject, generatedObject, objectResult,
                    recognized: ["anschluesse", "wireless"],
                    identifierMap: &nestedMap
                ) { $0 == "anschluesse" ? .cableEndpointCollection : nil }
            }
        case .cablePanel:
            try mergePropertyChildren(
                source, generated, result,
                recognized: ["bounds", "ziel1", "ziel2"],
                identifierMap: &identifierMap
            ) { $0 == "bounds" ? .rectangle : nil }
        case .documentation:
            try patchSingleObject(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, nestedMap in
                try mergePropertyChildren(
                    sourceObject, generatedObject, objectResult,
                    recognized: ["color", "font", "height", "text", "type", "width", "x", "y"],
                    identifierMap: &nestedMap
                ) {
                    if $0 == "color" { return .color }
                    if $0 == "font" { return .font }
                    return nil
                }
            }
        case .color, .font:
            try patchVoidObjectOrSelf(source, generated, result, identifierMap: &identifierMap) {
                sourceObject, generatedObject, objectResult, _ in
                mergeNativePrimitiveChildren(sourceObject, generatedObject, objectResult)
            }
        case let .application(className):
            try mergePropertyChildren(
                source, generated, result,
                recognized: recognizedApplicationProperties(className),
                identifierMap: &identifierMap
            ) { _ in nil }
        }
        return result
    }

    private static func mergeSystemSoftware(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode,
        identifierMap: inout [String: String]
    ) throws {
        try mergePropertyChildren(
            source, generated, result,
            recognized: [
                "mode", "port", "ipAdresse", "SSID", "retentionTime", "ssid", "dateisystem",
                "ripEnabled", "DHCPKonfiguration", "DHCPServer", "firewall", "ruleset", "staticNAT",
                "weiterleitungstabelle",
            ],
            identifierMap: &identifierMap
        ) { property in
            property == "dateisystem" ? .fileSystem : nil
        }

        let sourceContainers = source.elementChildren.filter {
            $0.name == "void" && $0.attributes["property"] == "installierteAnwendungen"
        }
        let generatedContainers = generated.elementChildren.filter {
            $0.name == "void" && $0.attributes["property"] == "installierteAnwendungen"
        }
        let sourceOperations = sourceContainers.flatMap(\.elementChildren)
        let generatedOperations = generatedContainers.flatMap(\.elementChildren)
        var consumedGenerated = Set<ObjectIdentifier>()
        var operations: [TopologyFLSInertXMLNode] = []

        for sourceOperation in sourceOperations {
            let identity = applicationIdentity(sourceOperation)
            if let className = identity.className, recognizedApplicationClasses.contains(className) {
                guard let generatedOperation = generatedOperations.first(where: {
                    !consumedGenerated.contains(ObjectIdentifier($0))
                        && applicationIdentity($0).className == className
                }) else {
                    // A modeled application deleted from native state must not be replayed from the source tree.
                    continue
                }
                consumedGenerated.insert(ObjectIdentifier(generatedOperation))
                operations.append(try patchApplicationOperation(
                    sourceOperation,
                    generatedOperation,
                    className: className,
                    sourceKey: identity.key,
                    identifierMap: &identifierMap
                ))
            } else {
                // A recognized key with an unknown class is still an unknown application bean.
                // It remains one inert map entry and is never replaced by a native application.
                operations.append(sourceOperation.deepCopy())
            }
        }
        operations.append(contentsOf: generatedOperations.filter {
            !consumedGenerated.contains(ObjectIdentifier($0))
        }.map { $0.deepCopy() })

        result.children.removeAll {
            if case let .element(element) = $0 {
                return element.name == "void" && element.attributes["property"] == "installierteAnwendungen"
            }
            return false
        }
        if !operations.isEmpty {
            let container = sourceContainers.first?.deepCopy()
                ?? generatedContainers.first?.deepCopy()
                ?? TopologyFLSInertXMLNode(name: "void", attributes: ["property": "installierteAnwendungen"])
            container.children = operations.map { .element($0) }
            result.children.append(.element(container))
        }
    }

    private static func patchApplicationOperation(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        className: String,
        sourceKey: String?,
        identifierMap: inout [String: String]
    ) throws -> TopologyFLSInertXMLNode {
        let result = source.deepCopy()
        mergeAttributes(source: source, generated: generated, result: result, identifierMap: &identifierMap)
        let sourceObject = source.elementChildren.first {
            $0.name == "object" && $0.attributes["class"] == className
        }
        guard let generatedObject = generated.elementChildren.first(where: {
            $0.name == "object" && $0.attributes["class"] == className
        }) else { return result }
        let generatedKey = generated.firstElement(named: "string")
        // Unknown map keys are metadata we cannot model, so retain them while patching the recognized class.
        let sourceKeyIsCanonical = sourceKey == className
        var children: [TopologyFLSInertXMLNode.Child] = []
        var insertedKey = false
        var insertedObject = false
        for child in source.children {
            if case let .element(element) = child, element.name == "string", !insertedKey {
                children.append(.element((sourceKeyIsCanonical ? generatedKey : element)?.deepCopy() ?? element.deepCopy()))
                insertedKey = true
            } else if case let .element(element) = child,
                      let sourceObject,
                      element === sourceObject,
                      !insertedObject
            {
                children.append(.element(try patch(
                    sourceObject,
                    with: generatedObject,
                    context: .application(className),
                    identifierMap: &identifierMap
                )))
                insertedObject = true
            } else {
                children.append(copyChild(child))
            }
        }
        if !insertedKey, let generatedKey { children.insert(.element(generatedKey.deepCopy()), at: 0) }
        if !insertedObject { children.append(.element(generatedObject.deepCopy())) }
        result.children = children
        return result
    }

    private static func recognizedApplicationProperties(_ className: String) -> Set<String> {
        switch className {
        case "filius.software.www.WebServer": return ["port"]
        case "filius.software.dateiaustausch.PeerToPeerAnwendung": return ["maxTeilnehmerZahl"]
        case "filius.software.email.EmailServer": return ["mailDomain", "listeBenutzerkonten"]
        case "filius.software.email.EmailAnwendung": return ["kontoListe", "eingang", "gesendet", "entwuerfe"]
        case "filius.software.firewall.Firewall", "filius.software.nat.NatGateway":
            return ["activated", "defaultPolicy", "dropICMP", "filterSYNSegmentsOnly", "filterUdp", "ruleset"]
        default: return []
        }
    }

    private static func mergePropertyChildren(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode,
        recognized: Set<String>,
        identifierMap: inout [String: String],
        childContext: (String) -> TopologyFLSXMLPatchContext?
    ) throws {
        var generatedByProperty: [String: [TopologyFLSInertXMLNode]] = [:]
        for child in generated.elementChildren {
            if child.name == "void", let property = child.attributes["property"], recognized.contains(property) {
                generatedByProperty[property, default: []].append(child)
            }
        }
        var children: [TopologyFLSInertXMLNode.Child] = []
        for child in source.children {
            guard case let .element(element) = child,
                  element.name == "void",
                  let property = element.attributes["property"],
                  recognized.contains(property)
            else {
                children.append(copyChild(child))
                continue
            }
            let context = childContext(property)
            guard var candidates = generatedByProperty[property], !candidates.isEmpty else {
                if case .systemSoftware? = context {
                    // The native exporter can omit an otherwise empty systemSoftware branch. Patch
                    // against an empty native shell so unknown applications/properties survive while
                    // modeled applications and modeled system fields remain deleted.
                    let shell = TopologyFLSInertXMLNode(
                        name: element.name,
                        attributes: element.attributes.filter { $0.key == "property" }
                    )
                    children.append(.element(try patch(
                        element,
                        with: shell,
                        context: .systemSoftware,
                        identifierMap: &identifierMap
                    )))
                }
                // Other native-authoritative source properties removed by the generated model stay removed.
                continue
            }
            let generatedChild = candidates.removeFirst()
            generatedByProperty[property] = candidates
            if let context {
                children.append(.element(try patch(
                    element,
                    with: generatedChild,
                    context: context,
                    identifierMap: &identifierMap
                )))
            } else {
                let scalarResult = element.deepCopy()
                mergeAttributes(
                    source: element,
                    generated: generatedChild,
                    result: scalarResult,
                    identifierMap: &identifierMap
                )
                scalarResult.children = generatedChild.children.map(copyChild)
                children.append(.element(scalarResult))
            }
        }
        for child in generated.elementChildren {
            guard child.name == "void",
                  let property = child.attributes["property"],
                  recognized.contains(property),
                  var candidates = generatedByProperty[property],
                  let index = candidates.firstIndex(where: { $0 === child })
            else { continue }
            children.append(.element(child.deepCopy()))
            candidates.remove(at: index)
            generatedByProperty[property] = candidates
        }
        result.children = children
    }

    private struct IndexedEntryIdentity: Equatable {
        let index: Int?
        let objectClass: String?
        let kind: String

        func semanticallyMatches(_ other: IndexedEntryIdentity) -> Bool {
            index == other.index && objectClass == other.objectClass && kind == other.kind
        }
    }

    private static func indexedEntryIdentity(
        _ entry: TopologyFLSInertXMLNode,
        context: TopologyFLSXMLPatchContext
    ) -> IndexedEntryIdentity? {
        guard entry.name == "void" else { return nil }
        switch context {
        case .networkInterfaceCollection:
            if entry.attributes == ["method": "add"],
               let object = entry.firstElement(named: "object"),
               object.attributes["class"] == "filius.hardware.NetzwerkInterface",
               entry.elementChildren.count == 1
            {
                return IndexedEntryIdentity(index: nil, objectClass: object.attributes["class"], kind: "interface-add")
            }
            guard Set(entry.attributes.keys).isSubset(of: ["id", "index"]),
                  let rawIndex = entry.attributes["index"], let index = Int(rawIndex),
                  entry.elementChildren.contains(where: { $0.name == "void" && $0.attributes["property"] == "port" })
            else { return nil }
            return IndexedEntryIdentity(index: index, objectClass: nil, kind: "interface-index")

        case .nativePortCollection:
            guard entry.attributes.count == 2,
                  let rawIndex = entry.attributes["index"], let index = Int(rawIndex),
                  entry.attributes["id"] != nil,
                  entry.children.isEmpty
            else { return nil }
            return IndexedEntryIdentity(index: index, objectClass: nil, kind: "native-direct-port")

        case .cableEndpointCollection:
            guard entry.attributes.count == 1,
                  let rawIndex = entry.attributes["index"], let index = Int(rawIndex),
                  entry.elementChildren.count == 1,
                  let object = entry.firstElement(named: "object"),
                  object.attributes.count == 1, object.attributes["idref"] != nil,
                  object.children.isEmpty
            else { return nil }
            return IndexedEntryIdentity(index: index, objectClass: nil, kind: "cable-endpoint")

        default:
            return nil
        }
    }

    private static func mergeIndexedChildren(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode,
        context: TopologyFLSXMLPatchContext,
        identifierMap: inout [String: String]
    ) throws {
        var generatedEntries = generated.elementChildren.compactMap { entry -> (TopologyFLSInertXMLNode, IndexedEntryIdentity)? in
            guard let identity = indexedEntryIdentity(entry, context: context) else { return nil }
            return (entry, identity)
        }
        var children: [TopologyFLSInertXMLNode.Child] = []
        for child in source.children {
            guard case let .element(sourceEntry) = child,
                  let sourceIdentity = indexedEntryIdentity(sourceEntry, context: context)
            else {
                children.append(copyChild(child))
                continue
            }
            if let match = generatedEntries.firstIndex(where: { sourceIdentity.semanticallyMatches($0.1) }) {
                let generatedEntry = generatedEntries.remove(at: match).0
                children.append(.element(try patchInterfaceEntry(
                    sourceEntry, generatedEntry, identifierMap: &identifierMap
                )))
            }
        }
        children.append(contentsOf: generatedEntries.map { .element($0.0.deepCopy()) })
        result.children = children
    }

    private static func patchInterfaceEntry(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        identifierMap: inout [String: String]
    ) throws -> TopologyFLSInertXMLNode {
        let result = source.deepCopy()
        mergeAttributes(source: source, generated: generated, result: result, identifierMap: &identifierMap)
        if let sourceObject = source.firstElement(named: "object"),
           let generatedObject = generated.firstElement(named: "object")
        {
            let objectResult = sourceObject.deepCopy()
            mergeAttributes(source: sourceObject, generated: generatedObject, result: objectResult, identifierMap: &identifierMap)
            try mergePropertyChildren(
                sourceObject, generatedObject, objectResult,
                recognized: ["ip", "subnetzMaske", "gateway", "dns", "port", "wireless"],
                identifierMap: &identifierMap
            ) { _ in nil }
            replaceFirstObject(in: result, with: objectResult)
        } else {
            try mergePropertyChildren(
                source, generated, result,
                recognized: ["ip", "subnetzMaske", "gateway", "dns", "port", "wireless"],
                identifierMap: &identifierMap
            ) { _ in nil }
        }
        return result
    }

    private static func patchSingleObject(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode,
        identifierMap: inout [String: String],
        body: (
            TopologyFLSInertXMLNode,
            TopologyFLSInertXMLNode,
            TopologyFLSInertXMLNode,
            inout [String: String]
        ) throws -> Void
    ) throws {
        guard let sourceObject = source.firstElement(named: "object"),
              let generatedObject = generated.firstElement(named: "object")
        else {
            result.children = generated.children.map(copyChild)
            return
        }
        let objectResult = sourceObject.deepCopy()
        mergeAttributes(source: sourceObject, generated: generatedObject, result: objectResult, identifierMap: &identifierMap)
        try body(sourceObject, generatedObject, objectResult, &identifierMap)
        replaceFirstObject(in: result, with: objectResult)
    }

    private static func patchVoidObjectOrSelf(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode,
        identifierMap: inout [String: String],
        body: (
            TopologyFLSInertXMLNode,
            TopologyFLSInertXMLNode,
            TopologyFLSInertXMLNode,
            inout [String: String]
        ) throws -> Void
    ) throws {
        if source.name == "void", generated.name == "void",
           source.firstElement(named: "object") != nil,
           generated.firstElement(named: "object") != nil
        {
            try patchSingleObject(source, generated, result, identifierMap: &identifierMap, body: body)
        } else {
            try body(source, generated, result, &identifierMap)
        }
    }

    private static func mergeRectangleChildren(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode
    ) {
        let primitives: Set<String> = ["int", "short", "long", "float", "double"]
        var children = source.children.filter {
            guard case let .element(element) = $0 else { return true }
            if primitives.contains(element.name) { return false }
            return !(element.name == "void"
                && element.attributes["class"] == "java.awt.Rectangle"
                && element.attributes["method"] == "getField")
        }
        children.append(contentsOf: generated.children.map(copyChild))
        result.children = children
    }

    private static func mergeNativePrimitiveChildren(
        _ source: TopologyFLSInertXMLNode,
        _ generated: TopologyFLSInertXMLNode,
        _ result: TopologyFLSInertXMLNode
    ) {
        let primitives: Set<String> = ["string", "int", "short", "long", "boolean", "float", "double"]
        var children = source.children.filter {
            guard case let .element(element) = $0 else { return true }
            return !primitives.contains(element.name)
        }
        children.append(contentsOf: generated.children.compactMap {
            guard case let .element(element) = $0, primitives.contains(element.name) else { return nil }
            return .element(element.deepCopy())
        })
        result.children = children
    }

    private static func mergeContainerAttributes(
        source: TopologyFLSInertXMLNode?,
        generated: TopologyFLSInertXMLNode
    ) -> TopologyFLSInertXMLNode {
        let result = source?.deepCopy() ?? generated.deepCopy()
        for (key, value) in generated.attributes where key != "id" { result.attributes[key] = value }
        return result
    }

    private static func setAdditions(
        _ additions: [TopologyFLSInertXMLNode],
        in result: TopologyFLSInertXMLNode,
        preservingFrom source: TopologyFLSInertXMLNode?
    ) {
        var children = (source?.children ?? []).filter {
            guard case let .element(element) = $0 else { return true }
            return !(element.name == "void" && element.attributes["method"] == "add")
        }
        children.append(contentsOf: additions.map { .element($0) })
        result.children = children
    }

    private static func residualAdditions(
        _ additions: [TopologyFLSInertXMLNode],
        recognizedClass: String,
        idsByRecognizedPath: [TopologyFLSInertXMLPath: UUID]
    ) -> [TopologyFLSInertXMLNode] {
        additions.compactMap { addition in
            guard let object = addition.firstElement(named: "object") else { return addition.deepCopy() }
            if object.attributes["class"] == recognizedClass, idsByRecognizedPath[object.path] != nil { return nil }
            return addition.deepCopy()
        }
    }

    private static func dictionaryByNativeID(
        _ additions: [TopologyFLSInertXMLNode],
        idsByPath: [TopologyFLSInertXMLPath: UUID]
    ) -> [UUID: TopologyFLSInertXMLNode] {
        var result: [UUID: TopologyFLSInertXMLNode] = [:]
        for addition in additions {
            guard let object = addition.firstElement(named: "object"), let id = idsByPath[object.path] else { continue }
            result[id] = addition
        }
        return result
    }

    private static func applicationIdentity(
        _ operation: TopologyFLSInertXMLNode
    ) -> (key: String?, className: String?) {
        let key = operation.firstElement(named: "string")?.textValue()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let className = operation.elementChildren.first { $0.name == "object" }?.attributes["class"]
        return (key, className)
    }

    private static func mergeAttributes(
        source: TopologyFLSInertXMLNode,
        generated: TopologyFLSInertXMLNode,
        result: TopologyFLSInertXMLNode,
        identifierMap: inout [String: String]
    ) {
        recordIdentifierMapping(source: source, generated: generated, into: &identifierMap)
        for (key, value) in generated.attributes where key != "id" { result.attributes[key] = value }
        if source.attributes["id"] == nil, let id = generated.attributes["id"] { result.attributes["id"] = id }
    }

    private static func recordIdentifierMapping(
        source: TopologyFLSInertXMLNode,
        generated: TopologyFLSInertXMLNode,
        into map: inout [String: String]
    ) {
        if let sourceID = source.attributes["id"], let generatedID = generated.attributes["id"] {
            map[generatedID] = sourceID
        }
    }

    private static func namespaceGeneratedIdentifiers(
        in root: TopologyFLSInertXMLNode,
        avoiding sourceIdentifiers: Set<String>,
        rewrite map: inout [String: String]
    ) {
        var identifiers: [String] = []
        collectIdentifierList(in: root, into: &identifiers)
        var occupied = sourceIdentifiers
        var sequence = 0
        for identifier in identifiers where map[identifier] == nil {
            var replacement: String
            repeat {
                sequence += 1
                replacement = "FiliusPadGenerated_\(sequence)"
            } while occupied.contains(replacement)
            map[identifier] = replacement
            occupied.insert(replacement)
        }
        rewriteIdentifiers(in: root, using: map)
    }

    private static func rewriteIdentifiers(
        in node: TopologyFLSInertXMLNode,
        using map: [String: String]
    ) {
        if let identifier = node.attributes["id"], let replacement = map[identifier] {
            node.attributes["id"] = replacement
        }
        if let reference = node.attributes["idref"], let replacement = map[reference] {
            node.attributes["idref"] = replacement
        }
        for child in node.elementChildren { rewriteIdentifiers(in: child, using: map) }
    }

    private static func validateCablePortReferences(
        nodeContainer: TopologyFLSInertXMLNode,
        cableContainer: TopologyFLSInertXMLNode
    ) throws {
        enum PortCollectionKind { case networkInterfaces, directPorts }
        var portIDs = Set<String>()
        func collectSupportedPorts(_ node: TopologyFLSInertXMLNode, collection: PortCollectionKind?) {
            let nextCollection: PortCollectionKind?
            if node.name == "void", node.attributes["property"] == "netzwerkInterfaces" {
                nextCollection = .networkInterfaces
            } else if node.name == "void", node.attributes["property"] == "anschluesse" {
                nextCollection = .directPorts
            } else {
                nextCollection = collection
            }
            if nextCollection == .networkInterfaces,
               node.name == "void", node.attributes.count == 2,
               node.attributes["property"] == "port", let identifier = node.attributes["id"],
               node.children.isEmpty
            {
                portIDs.insert(identifier)
            }
            if nextCollection == .directPorts,
               indexedEntryIdentity(node, context: .nativePortCollection) != nil,
               let identifier = node.attributes["id"]
            {
                portIDs.insert(identifier)
            }
            for child in node.elementChildren { collectSupportedPorts(child, collection: nextCollection) }
        }
        collectSupportedPorts(nodeContainer, collection: nil)

        var cableReferences = Set<String>()
        func collectCableReferences(_ node: TopologyFLSInertXMLNode, insideConnections: Bool) {
            let nowInside = insideConnections || (node.name == "void" && node.attributes["property"] == "anschluesse")
            if nowInside, indexedEntryIdentity(node, context: .cableEndpointCollection) != nil,
               let reference = node.firstElement(named: "object")?.attributes["idref"]
            {
                cableReferences.insert(reference)
            }
            for child in node.elementChildren { collectCableReferences(child, insideConnections: nowInside) }
        }
        collectCableReferences(cableContainer, insideConnections: false)
        let invalid = cableReferences.subtracting(portIDs).sorted()
        guard invalid.isEmpty else {
            throw unsafe("Merged cable endpoints do not target retained supported ports: \(invalid.prefix(8).joined(separator: ", ")).")
        }
    }

    private static func validateIdentifierClosure(in root: TopologyFLSInertXMLNode) throws {
        var identifierList: [String] = []
        collectIdentifierList(in: root, into: &identifierList)
        let identifiers = Set(identifierList)
        guard identifiers.count == identifierList.count else {
            throw unsafe("Merged lossless FILIUS XML contains duplicate JavaBean identifiers.")
        }
        var references = Set<String>()
        collectReferences(in: root, into: &references)
        let unresolved = references.subtracting(identifiers).sorted()
        guard unresolved.isEmpty else {
            throw unsafe("Lossless FILIUS XML contains unresolved object references: \(unresolved.prefix(8).joined(separator: ", ")).")
        }
    }

    private static func collectIdentifierList(
        in node: TopologyFLSInertXMLNode,
        into result: inout [String]
    ) {
        if let identifier = node.attributes["id"] { result.append(identifier) }
        for child in node.elementChildren { collectIdentifierList(in: child, into: &result) }
    }

    private static func collectReferences(
        in node: TopologyFLSInertXMLNode,
        into result: inout Set<String>
    ) {
        if let reference = node.attributes["idref"] { result.insert(reference) }
        for child in node.elementChildren { collectReferences(in: child, into: &result) }
    }

    private static func replaceFirstObject(
        in node: TopologyFLSInertXMLNode,
        with replacement: TopologyFLSInertXMLNode
    ) {
        for index in node.children.indices {
            guard case let .element(element) = node.children[index], element.name == "object" else { continue }
            node.children[index] = .element(replacement)
            return
        }
        node.children.append(.element(replacement))
    }

    fileprivate static func copyChild(_ child: TopologyFLSInertXMLNode.Child) -> TopologyFLSInertXMLNode.Child {
        switch child {
        case let .element(element): return .element(element.deepCopy())
        case let .text(text): return .text(text)
        case let .comment(comment): return .comment(comment)
        case let .processingInstruction(target, data):
            return .processingInstruction(target: target, data: data)
        }
    }

    private static func unsafe(_ detail: String) -> TopologyFLSCompatibilityError {
        TopologyFLSCompatibilityError(code: .unsupportedConfigurationStructure, detail: detail)
    }
}
