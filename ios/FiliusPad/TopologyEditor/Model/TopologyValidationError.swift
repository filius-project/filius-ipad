import Foundation

enum TopologyValidationErrorCode: String, Equatable {
    case missingNodeIdentifier
    case unknownNodeKind
    case nodeNotFound
    case linkNotFound
    case malformedActionPayload
    case invalidPortIdentifier
    case noFreePort
    case duplicateLink
    case incompatibleEndpoint
    case connectionSourceNotSelected
    case selfConnectionNotAllowed
    case simulationMustBeStopped
    case invalidDisplayName
    case invalidDeviceConfiguration
    case unsupportedConfiguration
    case connectedPortRemovalRequiresConfirmation
    case routerRequiresInterface
}

extension TopologyValidationErrorCode {
    var localizedMessage: String {
        FiliusLocalization.t("error.validation.\(rawValue)")
    }
}
