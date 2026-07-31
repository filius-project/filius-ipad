import CoreGraphics
import Foundation

enum TopologyJavaRouteTableColumn: Int, CaseIterable, Equatable, Hashable {
    case destination
    case subnetMask
    case nextGateway
    case interface

    var title: String {
        switch self {
        case .destination:
            return "Ziel"
        case .subnetMask:
            return "Netzmaske"
        case .nextGateway:
            return "Nächstes Gateway"
        case .interface:
            return "Über Schnittstelle"
        }
    }
}

enum TopologyJavaRouteTable {
    static let rowHeight: CGFloat = 20
    static let rowMargin: CGFloat = 2
    static let compactViewportSize = CGSize(width: 300, height: 120)
    static let windowSize = CGSize(width: 600, height: 400)
    static let tableContentInset: CGFloat = 2

    static func equalColumnWidth(for viewportWidth: CGFloat) -> CGFloat {
        let interColumnMargins = rowMargin * CGFloat(TopologyJavaRouteTableColumn.allCases.count - 1)
        let availableWidth = viewportWidth - (tableContentInset * 2) - interColumnMargins
        return max(0, availableWidth / CGFloat(TopologyJavaRouteTableColumn.allCases.count))
    }

    static func isValid(_ value: String, for column: TopologyJavaRouteTableColumn) -> Bool {
        switch column {
        case .destination, .nextGateway, .interface:
            return isValidJavaIPAddress(value)
        case .subnetMask:
            return isValidJavaSubnetMask(value)
        }
    }

    static func isValidJavaIPAddress(_ value: String) -> Bool {
        parseIPv4(value) != nil
    }

    static func isValidJavaSubnetMask(_ value: String) -> Bool {
        // FILIUS uses musterSubNetz, a dotted-decimal syntax check. It intentionally
        // accepts non-contiguous masks in the route editor.
        parseIPv4(value) != nil
    }

    static func rows(
        interfaces: [TopologyRuntimeInterfaceConfigurationItem],
        manualRoutes: [TopologyRuntimeManualRoute],
        defaultGateway: String?
    ) -> [TopologyRuntimeRouteRow] {
        rows(
            interfaceConfigurations: interfaces.compactMap(\.configuration),
            manualRoutes: manualRoutes,
            defaultGateway: defaultGateway
        )
    }

    static func rows(
        interfaceConfigurations: [TopologyRuntimeInterfaceConfiguration],
        manualRoutes: [TopologyRuntimeManualRoute],
        defaultGateway: String?
    ) -> [TopologyRuntimeRouteRow] {
        let validInterfaces = interfaceConfigurations.filter {
            parseIPv4($0.ipAddress) != nil && parseIPv4($0.subnetMask) != nil
        }

        var result = manualRoutes.map { route in
            TopologyRuntimeRouteRow(
                destinationNetwork: route.destinationNetwork,
                subnetMask: route.subnetMask,
                nextHop: route.gateway,
                interfaceIPAddress: route.interfaceIPAddress,
                origin: .manual,
                isEditable: true,
                metric: nil,
                expiresAtMilliseconds: nil
            )
        }

        result.insert(
            TopologyRuntimeRouteRow(
                destinationNetwork: "127.0.0.0",
                subnetMask: "255.0.0.0",
                nextHop: "127.0.0.1",
                interfaceIPAddress: "127.0.0.1",
                origin: .localhost,
                isEditable: false,
                metric: nil,
                expiresAtMilliseconds: nil
            ),
            at: 0
        )

        for configuration in validInterfaces {
            guard let network = networkAddress(
                ipAddress: configuration.ipAddress,
                subnetMask: configuration.subnetMask
            ) else {
                continue
            }
            result.insert(
                TopologyRuntimeRouteRow(
                    destinationNetwork: network,
                    subnetMask: configuration.subnetMask,
                    nextHop: configuration.ipAddress,
                    interfaceIPAddress: configuration.ipAddress,
                    origin: .connected,
                    isEditable: false,
                    metric: nil,
                    expiresAtMilliseconds: nil
                ),
                at: 0
            )
        }

        for configuration in validInterfaces {
            result.insert(
                TopologyRuntimeRouteRow(
                    destinationNetwork: configuration.ipAddress,
                    subnetMask: "255.255.255.255",
                    nextHop: "127.0.0.1",
                    interfaceIPAddress: "127.0.0.1",
                    origin: .localHost,
                    isEditable: false,
                    metric: nil,
                    expiresAtMilliseconds: nil
                ),
                at: 0
            )
        }

        let trimmedGateway = defaultGateway?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if parseIPv4(trimmedGateway) != nil, let primaryInterface = validInterfaces.first {
            var selectedInterface = primaryInterface.ipAddress
            for configuration in validInterfaces where sameNetwork(
                trimmedGateway,
                configuration.ipAddress,
                configuration.subnetMask
            ) {
                selectedInterface = configuration.ipAddress
            }

            result.append(
                TopologyRuntimeRouteRow(
                    destinationNetwork: "0.0.0.0",
                    subnetMask: "0.0.0.0",
                    nextHop: trimmedGateway,
                    interfaceIPAddress: selectedInterface,
                    origin: .defaultGateway,
                    isEditable: false,
                    metric: nil,
                    expiresAtMilliseconds: nil
                )
            )
        }

        return result
    }

    static func visibleRows(
        _ rows: [TopologyRuntimeRouteRow],
        showAllEntries: Bool
    ) -> [TopologyRuntimeRouteRow] {
        showAllEntries ? rows : rows.filter(\.isEditable)
    }

    private static func sameNetwork(_ lhs: String, _ rhs: String, _ mask: String) -> Bool {
        guard
            let lhsAddress = parseIPv4(lhs),
            let rhsAddress = parseIPv4(rhs),
            let maskAddress = parseIPv4(mask)
        else {
            return false
        }
        return (lhsAddress & maskAddress) == (rhsAddress & maskAddress)
    }

    private static func networkAddress(ipAddress: String, subnetMask: String) -> String? {
        guard let address = parseIPv4(ipAddress), let mask = parseIPv4(subnetMask) else {
            return nil
        }
        let network = address & mask
        return [24, 16, 8, 0]
            .map { String((network >> $0) & 0xFF) }
            .joined(separator: ".")
    }

    private static func parseIPv4(_ value: String) -> UInt32? {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else {
            return nil
        }

        var address = UInt32(0)
        for segment in segments {
            guard let octet = parseJavaOctet(segment) else {
                return nil
            }
            address = (address << 8) | UInt32(octet)
        }
        return address
    }

    private static func parseJavaOctet(_ segment: Substring) -> UInt8? {
        guard !segment.isEmpty, segment.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }

        let significant = segment.drop(while: { $0 == "0" })
        guard !significant.isEmpty else {
            return 0
        }
        guard significant.count <= 3, let value = Int(significant), value <= 255 else {
            return nil
        }
        return UInt8(value)
    }
}

struct TopologyJavaRouteDraft: Identifiable, Equatable {
    let id: UUID
    var destinationNetwork: String
    var subnetMask: String
    var nextGateway: String
    var interfaceIPAddress: String
    var isPendingInsertion: Bool

    init(
        id: UUID = UUID(),
        destinationNetwork: String,
        subnetMask: String,
        nextGateway: String,
        interfaceIPAddress: String,
        isPendingInsertion: Bool
    ) {
        self.id = id
        self.destinationNetwork = destinationNetwork
        self.subnetMask = subnetMask
        self.nextGateway = nextGateway
        self.interfaceIPAddress = interfaceIPAddress
        self.isPendingInsertion = isPendingInsertion
    }

    init(id: UUID = UUID(), route: TopologyRuntimeManualRoute) {
        self.init(
            id: id,
            destinationNetwork: route.destinationNetwork,
            subnetMask: route.subnetMask,
            nextGateway: route.gateway,
            interfaceIPAddress: route.interfaceIPAddress,
            isPendingInsertion: false
        )
    }

    static func blank(id: UUID = UUID()) -> TopologyJavaRouteDraft {
        TopologyJavaRouteDraft(
            id: id,
            destinationNetwork: "",
            subnetMask: "",
            nextGateway: "",
            interfaceIPAddress: "",
            isPendingInsertion: true
        )
    }

    var manualRoute: TopologyRuntimeManualRoute? {
        guard
            TopologyJavaRouteTable.isValid(destinationNetwork, for: .destination),
            TopologyJavaRouteTable.isValid(subnetMask, for: .subnetMask),
            TopologyJavaRouteTable.isValid(nextGateway, for: .nextGateway),
            TopologyJavaRouteTable.isValid(interfaceIPAddress, for: .interface)
        else {
            return nil
        }

        return TopologyRuntimeManualRoute(
            destinationNetwork: destinationNetwork,
            subnetMask: subnetMask,
            gateway: nextGateway,
            interfaceIPAddress: interfaceIPAddress
        )
    }

    func value(for column: TopologyJavaRouteTableColumn) -> String {
        switch column {
        case .destination:
            return destinationNetwork
        case .subnetMask:
            return subnetMask
        case .nextGateway:
            return nextGateway
        case .interface:
            return interfaceIPAddress
        }
    }

    static func appendingBlankIfNeeded(to drafts: [TopologyJavaRouteDraft]) -> [TopologyJavaRouteDraft] {
        guard !drafts.contains(where: \.isPendingInsertion) else {
            return drafts
        }
        return drafts + [.blank()]
    }
}
