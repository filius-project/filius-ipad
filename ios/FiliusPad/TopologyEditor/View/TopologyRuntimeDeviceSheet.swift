import SwiftUI
import UIKit
import WebKit

func updatingPersonalFirewallConfiguration(
    _ configuration: TopologyFirewallConfiguration,
    update: (inout TopologyFirewallConfiguration) -> Void
) -> TopologyFirewallConfiguration {
    var updated = configuration
    update(&updated)
    return updated
}

enum TopologyRuntimeVirtualHostEditor {
    static func saving(
        _ host: TopologyRuntimeWebVirtualHost,
        selectedHostID: String?,
        selectedDefaultHostID: String?,
        in existing: TopologyRuntimeWebVirtualHostConfiguration?
    ) throws -> TopologyRuntimeWebVirtualHostConfiguration {
        var hosts = existing?.hosts ?? []
        if let selectedHostID {
            hosts.removeAll { $0.id == selectedHostID }
        }
        hosts.removeAll { $0.id == host.id }
        hosts.append(host)

        let previousDefaultID = selectedDefaultHostID ?? existing?.defaultHostID
        let preferredDefaultID = previousDefaultID == selectedHostID
            ? host.id
            : (previousDefaultID ?? host.id)
        let defaultHostID: String
        if hosts.contains(where: { $0.id == preferredDefaultID && $0.isEnabled }) {
            defaultHostID = preferredDefaultID
        } else if host.isEnabled {
            defaultHostID = host.id
        } else if let firstEnabled = hosts.first(where: \.isEnabled) {
            defaultHostID = firstEnabled.id
        } else {
            throw TopologyRuntimeWebVirtualHostError.defaultHostDisabled(preferredDefaultID)
        }
        return try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: hosts,
            defaultHostID: defaultHostID
        )
    }

    static func removing(
        hostID: String,
        from existing: TopologyRuntimeWebVirtualHostConfiguration
    ) throws -> TopologyRuntimeWebVirtualHostConfiguration? {
        let remaining = existing.hosts.filter { $0.id != hostID }
        guard !remaining.isEmpty else { return nil }
        guard let fallbackDefault = remaining.first(where: \.isEnabled) else {
            throw TopologyRuntimeWebVirtualHostError.defaultHostDisabled(existing.defaultHostID)
        }
        let defaultHostID = remaining.contains {
            $0.id == existing.defaultHostID && $0.isEnabled
        } ? existing.defaultHostID : fallbackDefault.id
        return try TopologyRuntimeWebVirtualHostConfiguration(
            hosts: remaining,
            defaultHostID: defaultHostID
        )
    }
}

func topologyRuntimeDeviceTitle(for nodeKind: TopologyNodeKind) -> String {
    switch nodeKind {
    case .pc:
        return FiliusLocalization.t("runtime.kind.pc")
    case .notebook:
        return FiliusLocalization.t("model.notebook")
    case .networkSwitch:
        return FiliusLocalization.t("runtime.kind.switch")
    case .router:
        return FiliusLocalization.t("runtime.kind.router")
    case .gateway:
        return FiliusLocalization.t("runtime.kind.gateway")
    case .remoteLink:
        return FiliusLocalization.t("runtime.kind.remoteLink")
    case .unsupported:
        return FiliusLocalization.t("runtime.kind.unsupported")
    }
}

struct TopologyRuntimeDeviceSheet: View {
    private enum RuntimeWorkspaceDestination {
        case desktop
        case softwareManager
        case runtimeProgram(TopologyRuntimeInstallableProgram)
        case protocolApplication(TopologyProtocolApplicationDefinition)
    }

    let nodeID: UUID
    let nodeKind: TopologyNodeKind
    let configuration: TopologyRuntimeDeviceConfiguration?
    let interfaceConfigurations: [TopologyRuntimeInterfaceConfigurationItem]
    let manualRoutes: [TopologyRuntimeManualRoute]
    let ripEnabled: Bool
    let dhcpClientConfiguration: TopologyDHCPClientConfiguration
    let dhcpServerConfiguration: TopologyDHCPServerConfiguration
    let firewallConfiguration: TopologyFirewallConfiguration
    let firewallDecisions: [TopologyRuntimeFirewallDecision]
    let switchConfiguration: TopologySwitchConfiguration?
    let remoteLinkConfiguration: TopologyRemoteLinkConfiguration?
    let remoteLinkStatus: TopologyRemoteLinkRuntimeStatus?
    let switchSATEntries: [TopologySwitchSATEntry]
    let natMappings: [TopologyRuntimeNATMapping]
    let portForwardingRows: [TopologyGatewayPortForwardingRow]
    let packetCaptureTabs: [TopologyPacketCaptureTab]
    let packetMessageRows: [TopologyPacketMessageRow]
    let packetLayerPath: (TopologyPacketCaptureIdentity, Bool) -> TopologyPacketLayerPath
    let installedPrograms: Set<TopologyRuntimeInstallableProgram>
    let activeProgram: TopologyRuntimeInstallableProgram?
    let protocolApplicationsEnabled: Bool
    let protocolApplicationDefinitions: [TopologyProtocolApplicationDefinition]
    let installedProtocolApplicationIDs: Set<UUID>
    let activeProtocolApplicationID: UUID?
    let activeProtocolClientState: TopologyProtocolApplicationClientState?
    let activeProtocolServerState: TopologyProtocolApplicationServerState?
    let consoleEntries: [String]
    let terminalWorkingDirectory: String
    let dhcpLease: TopologyRuntimeDeviceConfiguration?
    let dnsRecords: [TopologyDNSResourceRecord]
    let dnsRecursiveResolutionEnabled: Bool
    let dnsForwardingServerIPAddress: String?
    let dnsServerState: TopologyRuntimeServiceProcessState?
    let webServerState: TopologyRuntimeServiceProcessState?
    let webServerConfiguration: TopologyRuntimeWebServerConfiguration
    let webServerRequestLogs: [TopologyRuntimeWebServerRequestLogEntry]
    let webAdministrationConfiguration: TopologyRuntimeWebAdministrationConfiguration
    let webAdministrationRunning: Bool
    let webBrowserConfiguration: TopologyRuntimeWebBrowserConfiguration
    let webBrowserState: TopologyRuntimeWebBrowserState?
    let echoServerState: TopologyRuntimeServiceProcessState?
    let virtualFileSystem: TopologyVirtualFileSystem
    let simpleClientState: TopologyRuntimeSimpleClientState?
    let emailClientConfiguration: TopologyRuntimeEmailClientConfiguration
    let emailClientState: TopologyRuntimeEmailClientState
    let emailServerConfiguration: TopologyRuntimeEmailServerConfiguration
    let emailServerProcessState: TopologyRuntimeEmailServerProcessState
    let gnutellaConfiguration: TopologyRuntimeGnutellaConfiguration
    let gnutellaSessionState: TopologyRuntimeGnutellaSessionState
    let fileExplorerSelection: String?
    let imageViewerSelection: String?
    let textEditorSelection: String?
    let textEditorDraft: String?
    let onSaveInterfaceConfiguration: (UUID, String, String) -> Void
    let onSaveManualRoutes: ([TopologyRuntimeManualRoute]) -> Void
    let onSetRIPEnabled: (Bool) -> Void
    let onSetDHCPClientEnabled: (Bool) -> Void
    let onSaveDHCPServerConfiguration: (TopologyDHCPServerConfiguration) -> Void
    let onSaveFirewallConfiguration: (TopologyFirewallConfiguration) -> Void
    let onClearSwitchSAT: () -> Void
    let onResetNATTable: () -> Void
    let onSavePortForwardingRows: ([TopologyGatewayPortForwardingRow]) -> Void
    let onResetPacketCapture: () -> Void
    let onExportPacketCapture: (UUID?) -> Void
    let onInstallProgram: (TopologyRuntimeInstallableProgram) -> Void
    let onUninstallProgram: (TopologyRuntimeInstallableProgram) -> Void
    let onLaunchProgram: (TopologyRuntimeInstallableProgram) -> Void
    let onCloseProgram: () -> Void
    let onInstallProtocolApplication: (UUID) -> Void
    let onLaunchProtocolApplication: (UUID) -> Void
    let onCloseProtocolApplication: () -> Void
    let onStartProtocolServer: (UUID) -> Void
    let onStopProtocolServer: (UUID) -> Void
    let onSendProtocolClientMessage: (UUID, String, UUID) -> Void
    let onExecuteCommand: (String) -> Void
    let onDHCPLease: (String, String) -> Void
    let onDHCPRelease: () -> Void
    let onDNSAddTypedRecord: (String, TopologyDNSRecordType, String, UInt32) -> Void
    let onDNSRemoveTypedRecord: (TopologyDNSResourceRecord) -> Void
    let onDNSResolveTypedRecord: (String, TopologyDNSRecordType) -> Void
    let onDNSSetRecursion: (Bool, String) -> Void
    let onDNSStart: () -> Void
    let onDNSStop: () -> Void
    let onSaveWebServerConfiguration: (TopologyRuntimeWebServerConfiguration) -> Void
    let onSaveWebAdministrationConfiguration: (TopologyRuntimeWebAdministrationConfiguration) -> Void
    let onWebAdministrationStart: (String) -> Void
    let onWebAdministrationStop: () -> Void
    let onWebStart: (String) -> Void
    let onWebStop: () -> Void
    let onWebRestart: (String) -> Void
    let onWebBrowserNavigate: (String) -> Void
    let onWebBrowserBack: () -> Void
    let onWebBrowserForward: () -> Void
    let onWebBrowserReset: () -> Void
    let onEchoStart: (String) -> Void
    let onEchoStop: () -> Void
    let onSimpleClientConnect: (String, String, TopologyRuntimeTransportProtocol) -> Void
    let onSimpleClientSend: (String) -> Void
    let onSimpleClientDisconnect: () -> Void
    let onSaveEmailClientConfiguration: (TopologyRuntimeEmailClientConfiguration) -> Void
    let onSendEmail: (TopologyRuntimeEmailMessage) -> Void
    let onRetrieveEmail: () -> Void
    let onDeleteEmailMessages: (TopologyRuntimeEmailClientFolder, [UInt64]) -> Void
    let onSaveEmailServerConfiguration: (TopologyRuntimeEmailServerConfiguration) -> Void
    let onStartEmailServer: (TopologyRuntimeEmailServerConfiguration) -> Void
    let onStopEmailServer: () -> Void
    let onSaveGnutellaConfiguration: (TopologyRuntimeGnutellaConfiguration) -> Void
    let onGnutellaJoin: (String) -> Void
    let onGnutellaResetNetwork: () -> Void
    let onGnutellaSearch: (String) -> Void
    let onGnutellaClearSearchResults: () -> Void
    let onGnutellaDownload: (TopologyGnutellaSearchResult) -> Void
    let onFileExplorerSelectEntry: (String) -> Void
    let onImageViewerSelectImage: (String) -> Void
    let onTextEditorSelectFile: (String) -> Void
    let onTextEditorUpdateDraft: (String) -> Void
    let onTextEditorSaveDraft: () -> Void
    let onTextEditorResetDraft: () -> Void
    let onFileSystemCreateDirectory: (String) -> Void
    let onFileSystemCreateTextFile: (String, String) -> Void
    let onFileSystemCopyItem: (String, String) -> Void
    let onFileSystemMoveItem: (String, String) -> Void
    let onFileSystemRenameItem: (String, String) -> Void
    let onFileSystemDeleteItem: (String, Bool) -> Void
    let onClose: () -> Void

    @State private var command: String
    @State private var dhcpLeaseIPAddress: String
    @State private var dhcpLeaseSubnetMask: String
    @State private var dnsHostname: String
    @State private var dnsTarget: String
    @State private var dnsRecordType: TopologyDNSRecordType
    @State private var dnsTTL: String
    @State private var dnsLookupHostname: String
    @State private var dnsLookupRecordType: TopologyDNSRecordType
    @State private var dnsForwarder: String
    @State private var dnsRecursionEnabled: Bool
    @State private var webPort: String
    @State private var webDocumentRoot: String
    @State private var virtualHostID: String
    @State private var selectedVirtualHostID: String?
    @State private var selectedDefaultVirtualHostID: String?
    @State private var virtualHostHostname: String
    @State private var virtualHostPort: String
    @State private var virtualHostDocumentRoot: String
    @State private var virtualHostEnabled = true
    @State private var webConfigurationError: String?
    @State private var adminPort: String
    @State private var adminNetworkAddress: String
    @State private var adminSubnetMask: String
    @State private var adminAllowedNetworks: [TopologyRuntimeWebAdministrationIPv4Network]
    @State private var adminEnabled: Bool
    @State private var adminConfigurationError: String?
    @State private var browserAddress: String
    @State private var echoPort: String
    @State private var simpleClientDestination: String
    @State private var simpleClientPort: String
    @State private var simpleClientProtocol: TopologyRuntimeTransportProtocol
    @State private var simpleClientMessage: String
    @State private var protocolClientDestination: String
    @State private var selectedProtocolTemplateID: UUID?
    @State private var personalFirewallProtocol: TopologyFirewallProtocol = .tcp
    @State private var personalFirewallPort = ""
    @State private var personalFirewallSameNetwork = false
    @State private var selectedFileEntryID: String
    @State private var selectedImageID: String
    @State private var fileExplorerDirectoryPath: String
    @State private var imageViewerDirectoryPath: String
    @State private var isRuntimeNetworkInfoExpanded = false
    @State private var textEditorDraftInput: String
    @State private var isTextEditorFileMenuExpanded = false
    @State private var newFileSystemPath = "/home/new-file.txt"
    @State private var newTextFileContents = ""
    @State private var destinationFileSystemPath = "/home/copy.txt"
    @State private var renamedFileSystemName = "renamed.txt"
    @State private var installerExpanded = false
    @State private var isDHCPConfigurationPresented = false
    @State private var isFirewallConfigurationPresented = false
    @State private var isNATTablePresented = false
    @State private var isPortForwardingPresented = false
    @State private var isPacketExchangePresented = false

    init(
        nodeID: UUID,
        nodeKind: TopologyNodeKind,
        configuration: TopologyRuntimeDeviceConfiguration?,
        interfaceConfigurations: [TopologyRuntimeInterfaceConfigurationItem],
        manualRoutes: [TopologyRuntimeManualRoute],
        ripEnabled: Bool,
        dhcpClientConfiguration: TopologyDHCPClientConfiguration,
        dhcpServerConfiguration: TopologyDHCPServerConfiguration,
        firewallConfiguration: TopologyFirewallConfiguration,
        firewallDecisions: [TopologyRuntimeFirewallDecision],
        switchConfiguration: TopologySwitchConfiguration?,
        remoteLinkConfiguration: TopologyRemoteLinkConfiguration?,
        remoteLinkStatus: TopologyRemoteLinkRuntimeStatus?,
        switchSATEntries: [TopologySwitchSATEntry],
        natMappings: [TopologyRuntimeNATMapping],
        portForwardingRows: [TopologyGatewayPortForwardingRow],
        packetCaptureTabs: [TopologyPacketCaptureTab],
        packetMessageRows: [TopologyPacketMessageRow],
        packetLayerPath: @escaping (TopologyPacketCaptureIdentity, Bool) -> TopologyPacketLayerPath,
        installedPrograms: Set<TopologyRuntimeInstallableProgram>,
        activeProgram: TopologyRuntimeInstallableProgram?,
        protocolApplicationsEnabled: Bool,
        protocolApplicationDefinitions: [TopologyProtocolApplicationDefinition],
        installedProtocolApplicationIDs: Set<UUID>,
        activeProtocolApplicationID: UUID?,
        activeProtocolClientState: TopologyProtocolApplicationClientState?,
        activeProtocolServerState: TopologyProtocolApplicationServerState?,
        consoleEntries: [String],
        terminalWorkingDirectory: String,
        dhcpLease: TopologyRuntimeDeviceConfiguration?,
        dnsRecords: [TopologyDNSResourceRecord],
        dnsRecursiveResolutionEnabled: Bool,
        dnsForwardingServerIPAddress: String?,
        dnsServerState: TopologyRuntimeServiceProcessState?,
        webServerState: TopologyRuntimeServiceProcessState?,
        webServerConfiguration: TopologyRuntimeWebServerConfiguration,
        webServerRequestLogs: [TopologyRuntimeWebServerRequestLogEntry],
        webAdministrationConfiguration: TopologyRuntimeWebAdministrationConfiguration,
        webAdministrationRunning: Bool,
        webBrowserConfiguration: TopologyRuntimeWebBrowserConfiguration,
        webBrowserState: TopologyRuntimeWebBrowserState?,
        echoServerState: TopologyRuntimeServiceProcessState?,
        virtualFileSystem: TopologyVirtualFileSystem,
        simpleClientState: TopologyRuntimeSimpleClientState?,
        emailClientConfiguration: TopologyRuntimeEmailClientConfiguration,
        emailClientState: TopologyRuntimeEmailClientState,
        emailServerConfiguration: TopologyRuntimeEmailServerConfiguration,
        emailServerProcessState: TopologyRuntimeEmailServerProcessState,
        gnutellaConfiguration: TopologyRuntimeGnutellaConfiguration,
        gnutellaSessionState: TopologyRuntimeGnutellaSessionState,
        fileExplorerSelection: String?,
        imageViewerSelection: String?,
        textEditorSelection: String?,
        textEditorDraft: String?,
        onSaveInterfaceConfiguration: @escaping (UUID, String, String) -> Void,
        onSaveManualRoutes: @escaping ([TopologyRuntimeManualRoute]) -> Void,
        onSetRIPEnabled: @escaping (Bool) -> Void,
        onSetDHCPClientEnabled: @escaping (Bool) -> Void,
        onSaveDHCPServerConfiguration: @escaping (TopologyDHCPServerConfiguration) -> Void,
        onSaveFirewallConfiguration: @escaping (TopologyFirewallConfiguration) -> Void,
        onClearSwitchSAT: @escaping () -> Void,
        onResetNATTable: @escaping () -> Void,
        onSavePortForwardingRows: @escaping ([TopologyGatewayPortForwardingRow]) -> Void,
        onResetPacketCapture: @escaping () -> Void,
        onExportPacketCapture: @escaping (UUID?) -> Void,
        onInstallProgram: @escaping (TopologyRuntimeInstallableProgram) -> Void,
        onUninstallProgram: @escaping (TopologyRuntimeInstallableProgram) -> Void,
        onLaunchProgram: @escaping (TopologyRuntimeInstallableProgram) -> Void,
        onCloseProgram: @escaping () -> Void,
        onInstallProtocolApplication: @escaping (UUID) -> Void,
        onLaunchProtocolApplication: @escaping (UUID) -> Void,
        onCloseProtocolApplication: @escaping () -> Void,
        onStartProtocolServer: @escaping (UUID) -> Void,
        onStopProtocolServer: @escaping (UUID) -> Void,
        onSendProtocolClientMessage: @escaping (UUID, String, UUID) -> Void,
        onExecuteCommand: @escaping (String) -> Void,
        onDHCPLease: @escaping (String, String) -> Void,
        onDHCPRelease: @escaping () -> Void,
        onDNSAddTypedRecord: @escaping (String, TopologyDNSRecordType, String, UInt32) -> Void,
        onDNSRemoveTypedRecord: @escaping (TopologyDNSResourceRecord) -> Void,
        onDNSResolveTypedRecord: @escaping (String, TopologyDNSRecordType) -> Void,
        onDNSSetRecursion: @escaping (Bool, String) -> Void,
        onDNSStart: @escaping () -> Void,
        onDNSStop: @escaping () -> Void,
        onSaveWebServerConfiguration: @escaping (TopologyRuntimeWebServerConfiguration) -> Void,
        onSaveWebAdministrationConfiguration: @escaping (TopologyRuntimeWebAdministrationConfiguration) -> Void,
        onWebAdministrationStart: @escaping (String) -> Void,
        onWebAdministrationStop: @escaping () -> Void,
        onWebStart: @escaping (String) -> Void,
        onWebStop: @escaping () -> Void,
        onWebRestart: @escaping (String) -> Void,
        onWebBrowserNavigate: @escaping (String) -> Void,
        onWebBrowserBack: @escaping () -> Void,
        onWebBrowserForward: @escaping () -> Void,
        onWebBrowserReset: @escaping () -> Void,
        onEchoStart: @escaping (String) -> Void,
        onEchoStop: @escaping () -> Void,
        onSimpleClientConnect: @escaping (String, String, TopologyRuntimeTransportProtocol) -> Void,
        onSimpleClientSend: @escaping (String) -> Void,
        onSimpleClientDisconnect: @escaping () -> Void,
        onSaveEmailClientConfiguration: @escaping (TopologyRuntimeEmailClientConfiguration) -> Void,
        onSendEmail: @escaping (TopologyRuntimeEmailMessage) -> Void,
        onRetrieveEmail: @escaping () -> Void,
        onDeleteEmailMessages: @escaping (TopologyRuntimeEmailClientFolder, [UInt64]) -> Void,
        onSaveEmailServerConfiguration: @escaping (TopologyRuntimeEmailServerConfiguration) -> Void,
        onStartEmailServer: @escaping (TopologyRuntimeEmailServerConfiguration) -> Void,
        onStopEmailServer: @escaping () -> Void,
        onSaveGnutellaConfiguration: @escaping (TopologyRuntimeGnutellaConfiguration) -> Void,
        onGnutellaJoin: @escaping (String) -> Void,
        onGnutellaResetNetwork: @escaping () -> Void,
        onGnutellaSearch: @escaping (String) -> Void,
        onGnutellaClearSearchResults: @escaping () -> Void,
        onGnutellaDownload: @escaping (TopologyGnutellaSearchResult) -> Void,
        onFileExplorerSelectEntry: @escaping (String) -> Void,
        onImageViewerSelectImage: @escaping (String) -> Void,
        onTextEditorSelectFile: @escaping (String) -> Void,
        onTextEditorUpdateDraft: @escaping (String) -> Void,
        onTextEditorSaveDraft: @escaping () -> Void,
        onTextEditorResetDraft: @escaping () -> Void,
        onFileSystemCreateDirectory: @escaping (String) -> Void,
        onFileSystemCreateTextFile: @escaping (String, String) -> Void,
        onFileSystemCopyItem: @escaping (String, String) -> Void,
        onFileSystemMoveItem: @escaping (String, String) -> Void,
        onFileSystemRenameItem: @escaping (String, String) -> Void,
        onFileSystemDeleteItem: @escaping (String, Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.nodeID = nodeID
        self.nodeKind = nodeKind
        self.configuration = configuration
        self.interfaceConfigurations = interfaceConfigurations
        self.manualRoutes = manualRoutes
        self.ripEnabled = ripEnabled
        self.dhcpClientConfiguration = dhcpClientConfiguration
        self.dhcpServerConfiguration = dhcpServerConfiguration
        self.firewallConfiguration = firewallConfiguration
        self.firewallDecisions = firewallDecisions
        self.switchConfiguration = switchConfiguration
        self.remoteLinkConfiguration = remoteLinkConfiguration
        self.remoteLinkStatus = remoteLinkStatus
        self.switchSATEntries = switchSATEntries
        self.natMappings = natMappings
        self.portForwardingRows = portForwardingRows
        self.packetCaptureTabs = packetCaptureTabs
        self.packetMessageRows = packetMessageRows
        self.packetLayerPath = packetLayerPath
        self.installedPrograms = installedPrograms
        self.activeProgram = activeProgram
        self.protocolApplicationsEnabled = protocolApplicationsEnabled
        self.protocolApplicationDefinitions = protocolApplicationDefinitions
        self.installedProtocolApplicationIDs = installedProtocolApplicationIDs
        self.activeProtocolApplicationID = activeProtocolApplicationID
        self.activeProtocolClientState = activeProtocolClientState
        self.activeProtocolServerState = activeProtocolServerState
        self.consoleEntries = consoleEntries
        self.terminalWorkingDirectory = terminalWorkingDirectory
        self.dhcpLease = dhcpLease
        self.dnsRecords = dnsRecords
        self.dnsRecursiveResolutionEnabled = dnsRecursiveResolutionEnabled
        self.dnsForwardingServerIPAddress = dnsForwardingServerIPAddress
        self.dnsServerState = dnsServerState
        self.webServerState = webServerState
        self.webServerConfiguration = webServerConfiguration
        self.webServerRequestLogs = webServerRequestLogs
        self.webAdministrationConfiguration = webAdministrationConfiguration
        self.webAdministrationRunning = webAdministrationRunning
        self.webBrowserConfiguration = webBrowserConfiguration
        self.webBrowserState = webBrowserState
        self.echoServerState = echoServerState
        self.virtualFileSystem = virtualFileSystem
        self.simpleClientState = simpleClientState
        self.emailClientConfiguration = emailClientConfiguration
        self.emailClientState = emailClientState
        self.emailServerConfiguration = emailServerConfiguration
        self.emailServerProcessState = emailServerProcessState
        self.gnutellaConfiguration = gnutellaConfiguration
        self.gnutellaSessionState = gnutellaSessionState
        self.fileExplorerSelection = fileExplorerSelection
        self.imageViewerSelection = imageViewerSelection
        self.textEditorSelection = textEditorSelection
        self.textEditorDraft = textEditorDraft
        self.onSaveInterfaceConfiguration = onSaveInterfaceConfiguration
        self.onSaveManualRoutes = onSaveManualRoutes
        self.onSetRIPEnabled = onSetRIPEnabled
        self.onSetDHCPClientEnabled = onSetDHCPClientEnabled
        self.onSaveDHCPServerConfiguration = onSaveDHCPServerConfiguration
        self.onSaveFirewallConfiguration = onSaveFirewallConfiguration
        self.onClearSwitchSAT = onClearSwitchSAT
        self.onResetNATTable = onResetNATTable
        self.onSavePortForwardingRows = onSavePortForwardingRows
        self.onResetPacketCapture = onResetPacketCapture
        self.onExportPacketCapture = onExportPacketCapture
        self.onInstallProgram = onInstallProgram
        self.onUninstallProgram = onUninstallProgram
        self.onLaunchProgram = onLaunchProgram
        self.onCloseProgram = onCloseProgram
        self.onInstallProtocolApplication = onInstallProtocolApplication
        self.onLaunchProtocolApplication = onLaunchProtocolApplication
        self.onCloseProtocolApplication = onCloseProtocolApplication
        self.onStartProtocolServer = onStartProtocolServer
        self.onStopProtocolServer = onStopProtocolServer
        self.onSendProtocolClientMessage = onSendProtocolClientMessage
        self.onExecuteCommand = onExecuteCommand
        self.onDHCPLease = onDHCPLease
        self.onDHCPRelease = onDHCPRelease
        self.onDNSAddTypedRecord = onDNSAddTypedRecord
        self.onDNSRemoveTypedRecord = onDNSRemoveTypedRecord
        self.onDNSResolveTypedRecord = onDNSResolveTypedRecord
        self.onDNSSetRecursion = onDNSSetRecursion
        self.onDNSStart = onDNSStart
        self.onDNSStop = onDNSStop
        self.onSaveWebServerConfiguration = onSaveWebServerConfiguration
        self.onSaveWebAdministrationConfiguration = onSaveWebAdministrationConfiguration
        self.onWebAdministrationStart = onWebAdministrationStart
        self.onWebAdministrationStop = onWebAdministrationStop
        self.onWebStart = onWebStart
        self.onWebStop = onWebStop
        self.onWebRestart = onWebRestart
        self.onWebBrowserNavigate = onWebBrowserNavigate
        self.onWebBrowserBack = onWebBrowserBack
        self.onWebBrowserForward = onWebBrowserForward
        self.onWebBrowserReset = onWebBrowserReset
        self.onEchoStart = onEchoStart
        self.onEchoStop = onEchoStop
        self.onSimpleClientConnect = onSimpleClientConnect
        self.onSimpleClientSend = onSimpleClientSend
        self.onSimpleClientDisconnect = onSimpleClientDisconnect
        self.onSaveEmailClientConfiguration = onSaveEmailClientConfiguration
        self.onSendEmail = onSendEmail
        self.onRetrieveEmail = onRetrieveEmail
        self.onDeleteEmailMessages = onDeleteEmailMessages
        self.onSaveEmailServerConfiguration = onSaveEmailServerConfiguration
        self.onStartEmailServer = onStartEmailServer
        self.onStopEmailServer = onStopEmailServer
        self.onSaveGnutellaConfiguration = onSaveGnutellaConfiguration
        self.onGnutellaJoin = onGnutellaJoin
        self.onGnutellaResetNetwork = onGnutellaResetNetwork
        self.onGnutellaSearch = onGnutellaSearch
        self.onGnutellaClearSearchResults = onGnutellaClearSearchResults
        self.onGnutellaDownload = onGnutellaDownload
        self.onFileExplorerSelectEntry = onFileExplorerSelectEntry
        self.onImageViewerSelectImage = onImageViewerSelectImage
        self.onTextEditorSelectFile = onTextEditorSelectFile
        self.onTextEditorUpdateDraft = onTextEditorUpdateDraft
        self.onTextEditorSaveDraft = onTextEditorSaveDraft
        self.onTextEditorResetDraft = onTextEditorResetDraft
        self.onFileSystemCreateDirectory = onFileSystemCreateDirectory
        self.onFileSystemCreateTextFile = onFileSystemCreateTextFile
        self.onFileSystemCopyItem = onFileSystemCopyItem
        self.onFileSystemMoveItem = onFileSystemMoveItem
        self.onFileSystemRenameItem = onFileSystemRenameItem
        self.onFileSystemDeleteItem = onFileSystemDeleteItem
        self.onClose = onClose

        _command = State(initialValue: "")
        _dhcpLeaseIPAddress = State(initialValue: dhcpLease?.ipAddress ?? "")
        _dhcpLeaseSubnetMask = State(initialValue: dhcpLease?.subnetMask ?? "")
        _dnsHostname = State(initialValue: "")
        _dnsTarget = State(initialValue: "")
        _dnsRecordType = State(initialValue: .address)
        _dnsTTL = State(initialValue: String(TopologyDNSResourceRecord.defaultTTLSeconds))
        _dnsLookupHostname = State(initialValue: "")
        _dnsLookupRecordType = State(initialValue: .address)
        _dnsForwarder = State(initialValue: dnsForwardingServerIPAddress ?? "")
        _dnsRecursionEnabled = State(initialValue: dnsRecursiveResolutionEnabled)
        _webPort = State(initialValue: String(webServerState?.port ?? webServerConfiguration.port))
        _webDocumentRoot = State(initialValue: webServerConfiguration.documentRoot)
        let initialVirtualHost = webServerConfiguration.virtualHostConfiguration?.hosts.first
        _virtualHostID = State(initialValue: initialVirtualHost?.id ?? "default")
        _selectedVirtualHostID = State(initialValue: initialVirtualHost?.id)
        _selectedDefaultVirtualHostID = State(
            initialValue: webServerConfiguration.virtualHostConfiguration?.defaultHostID
        )
        _virtualHostHostname = State(initialValue: initialVirtualHost?.authority.hostname ?? "")
        _virtualHostPort = State(initialValue: initialVirtualHost?.authority.port.map(String.init) ?? "")
        _virtualHostDocumentRoot = State(initialValue: initialVirtualHost?.documentRoot ?? webServerConfiguration.documentRoot)
        _virtualHostEnabled = State(initialValue: initialVirtualHost?.isEnabled ?? true)
        _webConfigurationError = State(initialValue: nil)
        _adminConfigurationError = State(initialValue: nil)
        _adminPort = State(initialValue: String(webAdministrationConfiguration.port))
        _adminNetworkAddress = State(initialValue: "")
        _adminSubnetMask = State(initialValue: "255.255.255.0")
        _adminAllowedNetworks = State(initialValue: webAdministrationConfiguration.accessPolicy.allowedSourceNetworks)
        _adminEnabled = State(initialValue: webAdministrationConfiguration.accessPolicy.isEnabled)
        _browserAddress = State(initialValue: webBrowserState?.address ?? (webBrowserConfiguration.lastHost.isEmpty ? "" : "http://\(webBrowserConfiguration.lastHost):\(webBrowserConfiguration.lastPort)\(webBrowserConfiguration.lastPath)"))
        _echoPort = State(initialValue: String(echoServerState?.port ?? 55555))
        _simpleClientDestination = State(initialValue: simpleClientState?.destinationIPAddress ?? "")
        _simpleClientPort = State(initialValue: String(simpleClientState?.destinationPort ?? 55555))
        _simpleClientProtocol = State(initialValue: simpleClientState?.protocolKind ?? .tcp)
        _simpleClientMessage = State(initialValue: "")
        _protocolClientDestination = State(initialValue: activeProtocolClientState?.destinationIPAddress ?? "")
        let activeDefinition = protocolApplicationDefinitions.first { $0.id == activeProtocolApplicationID }
        _selectedProtocolTemplateID = State(initialValue: activeDefinition?.clientMessageTemplates.first?.id)
        let files = virtualFileSystem.allEntries().filter { $0.content.isFile }
        let images = files.filter { $0.content.isImage }
        let initialFileSelection = fileExplorerSelection ?? files.first?.path ?? ""
        let initialImageSelection = imageViewerSelection ?? images.first?.path ?? ""
        _selectedFileEntryID = State(initialValue: initialFileSelection)
        _selectedImageID = State(initialValue: initialImageSelection)
        _fileExplorerDirectoryPath = State(initialValue: Self.initialDirectoryPath(
            for: initialFileSelection,
            in: virtualFileSystem
        ))
        _imageViewerDirectoryPath = State(initialValue: Self.initialDirectoryPath(
            for: initialImageSelection,
            in: virtualFileSystem
        ))
        _textEditorDraftInput = State(initialValue: textEditorDraft ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if isDesktopRuntimeNode {
                    runtimeDesktopWorkspaceSection
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            runtimeHeader
                            runtimeInfrastructureContent

                            if nodeKind != .unsupported {
                                packetExchangeDestinationLink
                            }
                        }
                        .padding(16)
                    }
                    .accessibilityIdentifier("runtime.device.scroll")
                }
            }
            .background(FiliusExperienceTokens.runtimeWindowSurface)
            .navigationTitle(FiliusLocalization.t("ui.10e5fb22ae76"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isDesktopRuntimeNode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(FiliusLocalization.t("ui.e9b450d14bc2"), action: onClose)
                            .accessibilityIdentifier("runtime.device.close")
                    }
                }
            }
            .toolbar(isDesktopRuntimeNode ? .hidden : .visible, for: .navigationBar)
        }
        .sheet(isPresented: $isDHCPConfigurationPresented) {
            TopologyDHCPConfigurationView(
                nodeKind: nodeKind,
                configuration: dhcpServerConfiguration,
                subnetMask: dhcpServerSubnetMask,
                gatewayIPAddress: dhcpServerGatewayIPAddress,
                dnsServerIPAddress: dhcpServerDNSServerIPAddress,
                onSave: onSaveDHCPServerConfiguration
            )
            .presentationDetents([.height(380), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isFirewallConfigurationPresented) {
            TopologyFirewallConfigurationView(
                configuration: firewallConfiguration,
                onSave: onSaveFirewallConfiguration
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isNATTablePresented) {
            TopologyNATTableView(
                mappings: natMappings,
                onReset: onResetNATTable
            )
            .presentationDetents([.height(240), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isPortForwardingPresented) {
            TopologyPortForwardingView(
                rows: portForwardingRows,
                onSave: onSavePortForwardingRows
            )
            .presentationDetents([.height(420), .large])
            .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("runtime.device.sheet")
        .preferredColorScheme(.light)
        .onChange(of: nodeID) {
            synchronizeServiceFields()
            synchronizeDesktopSuiteFields()
            fileExplorerDirectoryPath = Self.initialDirectoryPath(
                for: selectedFileEntryID,
                in: virtualFileSystem
            )
            imageViewerDirectoryPath = Self.initialDirectoryPath(
                for: selectedImageID,
                in: virtualFileSystem
            )
            command = ""
            installerExpanded = false
            isRuntimeNetworkInfoExpanded = false
        }
        .onChange(of: dhcpLease) {
            synchronizeServiceFields()
        }
        .onChange(of: webServerState) {
            synchronizeServiceFields()
        }
        .onChange(of: echoServerState) {
            synchronizeServiceFields()
        }
        .onChange(of: simpleClientState) {
            synchronizeServiceFields()
        }
        .onChange(of: activeProtocolApplicationID) { _, newValue in
            guard let definition = protocolApplicationDefinitions.first(where: { $0.id == newValue }) else {
                selectedProtocolTemplateID = nil
                return
            }
            selectedProtocolTemplateID = definition.clientMessageTemplates.first?.id
            protocolClientDestination = activeProtocolClientState?.destinationIPAddress ?? ""
        }
        .onChange(of: installedPrograms) {
            if !hasCommandPromptInstalled {
                command = ""
            }
        }
        .onChange(of: fileExplorerSelection) { _, newValue in
            synchronizeDesktopSuiteFields()
            if let newValue {
                selectedFileEntryID = newValue
                fileExplorerDirectoryPath = Self.initialDirectoryPath(for: newValue, in: virtualFileSystem)
            }
        }
        .onChange(of: imageViewerSelection) { _, newValue in
            synchronizeDesktopSuiteFields()
            if let newValue {
                selectedImageID = newValue
                imageViewerDirectoryPath = Self.initialDirectoryPath(for: newValue, in: virtualFileSystem)
            }
        }
        .onChange(of: textEditorSelection) { _, _ in
            textEditorDraftInput = textEditorDraft ?? ""
        }
        .onChange(of: virtualFileSystem) {
            synchronizeDesktopSuiteFields()
        }
        .onChange(of: textEditorDraft) { _, newValue in
            textEditorDraftInput = newValue ?? ""
        }
    }

    private var remoteLinkInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(FiliusLocalization.t("ui.30b8b5ee6804"))
                .font(.headline)

            LabeledContent(
                FiliusLocalization.t("ui.bae7d5be7082"),
                value: remoteLinkStatusDescription
            )
            .accessibilityIdentifier("runtime.device.remote-link.status")

            if let configuration = remoteLinkConfiguration {
                LabeledContent(
                    FiliusLocalization.t("runtime.remote.transport"),
                    value: configuration.transportMode == .localNetwork
                        ? FiliusLocalization.t("remoteLink.transport.localNetwork")
                        : FiliusLocalization.t("remoteLink.transport.inProject")
                )
                if configuration.transportMode == .localNetwork {
                    LabeledContent(
                        FiliusLocalization.t("runtime.remote.role"),
                        value: configuration.lanRole == .host
                            ? FiliusLocalization.t("remoteLink.role.host")
                            : FiliusLocalization.t("remoteLink.role.join")
                    )
                }
            }

            LabeledContent(
                FiliusLocalization.t("editor.field.pairID"),
                value: remoteLinkConfiguration?.pairIdentifier.ifEmpty("—") ?? "—"
            )
            .accessibilityIdentifier("runtime.device.remote-link.pair-id")

            LabeledContent(
                FiliusLocalization.t("runtime.remote.deterministicLatency"),
                value: remoteLinkConfiguration.map { FiliusLocalization.t("runtime.milliseconds", $0.latencyMilliseconds) } ?? "—"
            )
            .accessibilityIdentifier("runtime.device.remote-link.latency-ms")

            LabeledContent(
                FiliusLocalization.t("runtime.remote.partner"),
                value: remoteLinkPartnerDescription
            )
            .accessibilityIdentifier("runtime.device.remote-link.peer")

            LabeledContent(
                FiliusLocalization.t("runtime.remote.localPort"),
                value: remoteLinkStatus?.isLocalPortAttached == true
                    ? FiliusLocalization.t("runtime.remote.connected")
                    : FiliusLocalization.t("runtime.remote.notConnected")
            )
            .accessibilityIdentifier("runtime.device.remote-link.local-port")

            Text(FiliusLocalization.t("ui.6440aa7db31b"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.remote-link.compatibility")

            Button(FiliusLocalization.t("ui.9ee985560b45")) {
                isPacketExchangePresented = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.remote-link.packet-exchange.show")

            Text(FiliusLocalization.t("runtime.packetRows", packetMessageRows.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.remote-link.packet-count")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.remote-link")
    }

    private var remoteLinkStatusDescription: String {
        guard let condition = remoteLinkStatus?.condition else {
            return remoteLinkConfiguration?.isEnabled == true ? FiliusLocalization.t("runtime.remote.waitSimulation") : FiliusLocalization.t("runtime.remote.disabled")
        }
        switch condition {
        case .stopped:
            return FiliusLocalization.t("runtime.remote.stopped")
        case .missingConfiguration:
            return FiliusLocalization.t("runtime.remote.missingConfig")
        case .disabled:
            return FiliusLocalization.t("runtime.remote.disabled")
        case .unpaired:
            return FiliusLocalization.t("runtime.remote.waitPartner")
        case let .ambiguous(enabledNodeCount):
            return FiliusLocalization.t("runtime.remote.ambiguous", enabledNodeCount)
        case .detached, .detachedLAN:
            return FiliusLocalization.t("runtime.remote.detached")
        case .waitingForPeer:
            return FiliusLocalization.t("runtime.remote.waitPartner")
        case .connecting:
            return FiliusLocalization.t("runtime.remote.connecting")
        case let .connectionFailed(message):
            return FiliusLocalization.t("runtime.remote.failed", message)
        case .active, .activeLAN:
            return FiliusLocalization.t("runtime.remote.active")
        }
    }

    private var remoteLinkPartnerDescription: String {
        guard let condition = remoteLinkStatus?.condition else { return FiliusLocalization.t("runtime.remote.noPartner") }
        switch condition {
        case let .active(partnerNodeID), let .detached(partnerNodeID):
            return partnerNodeID.uuidString
        case let .activeLAN(peerName):
            return peerName
        default:
            break
        }
        return FiliusLocalization.t("runtime.remote.noPartner")
    }

    private var hasCommandPromptInstalled: Bool {
        installedPrograms.contains(.commandPrompt)
    }

    private var openedRuntimeProgram: TopologyRuntimeInstallableProgram? {
        guard let activeProgram,
              installedPrograms.contains(activeProgram)
        else {
            return nil
        }

        return activeProgram
    }

    private var openedProtocolApplication: TopologyProtocolApplicationDefinition? {
        guard protocolApplicationsEnabled,
              activeProgram == nil,
              let activeProtocolApplicationID,
              installedProtocolApplicationIDs.contains(activeProtocolApplicationID) else { return nil }
        return protocolApplicationDefinitions.first { $0.id == activeProtocolApplicationID }
    }

    private var runtimeWorkspaceDestination: RuntimeWorkspaceDestination {
        if let openedRuntimeProgram {
            return .runtimeProgram(openedRuntimeProgram)
        }
        if let openedProtocolApplication {
            return .protocolApplication(openedProtocolApplication)
        }
        if installerExpanded {
            return .softwareManager
        }
        return .desktop
    }

    private var isDesktopRuntimeNode: Bool {
        nodeKind == .pc || nodeKind == .notebook
    }

    @ViewBuilder
    private var runtimeInfrastructureContent: some View {
        switch nodeKind {
        case .pc, .notebook:
            EmptyView()

        case .networkSwitch:
            switchInfoSection

        case .router:
            infrastructureConfigurationSection(
                title: FiliusLocalization.t("runtime.router.configuration.title"),
                detail: FiliusLocalization.t("runtime.router.configuration.detail"),
                identifierPrefix: "runtime.device.router"
            )

            Toggle(
                FiliusLocalization.t("runtime.router.automaticRouting"),
                isOn: Binding(get: { ripEnabled }, set: onSetRIPEnabled)
            )
            .accessibilityIdentifier("runtime.device.router.ripEnabled")

            TopologyJavaRouteTableView(
                interfaces: interfaceConfigurations,
                manualRoutes: manualRoutes,
                defaultGateway: configuration?.defaultGateway,
                onSaveManualRoutes: onSaveManualRoutes
            )
            .disabled(ripEnabled)

            Button(FiliusLocalization.t("ui.7a49d1c1b2fb")) {
                isFirewallConfigurationPresented = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.router.firewall.configure")

            webAdministrationControlsSection

        case .gateway:
            infrastructureConfigurationSection(
                title: FiliusLocalization.t("runtime.gateway.configuration.title"),
                detail: FiliusLocalization.t("runtime.gateway.configuration.detail"),
                identifierPrefix: "runtime.device.gateway"
            )

            dhcpControlsSection

            HStack(spacing: 10) {
                Button(FiliusLocalization.t("ui.7a49d1c1b2fb")) {
                    isFirewallConfigurationPresented = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.gateway.firewall.configure")

                Button(FiliusLocalization.t("ui.a050267328c5")) {
                    isNATTablePresented = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.gateway.nat.show")

                Button(FiliusLocalization.t("ui.cfba2f20d168")) {
                    isPortForwardingPresented = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.gateway.port-forwarding.configure")
            }

            webAdministrationControlsSection

        case .remoteLink:
            remoteLinkInfoSection

        case .unsupported:
            unsupportedInfoSection
        }
    }

    private var webAdministrationControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("runtime.webAdministration.title"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.web-administration.title")
            Text(FiliusLocalization.t("runtime.webAdministration.detail"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                FiliusLocalization.t("runtime.webAdministration.enabled"),
                isOn: $adminEnabled
            )
            .accessibilityIdentifier("runtime.device.web-administration.enabled")

            TextField(FiliusLocalization.t("runtime.webAdministration.port"), text: $adminPort)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.web-administration.port")
            TextField(FiliusLocalization.t("runtime.webAdministration.sourceNetwork"), text: $adminNetworkAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.web-administration.network")
            TextField(FiliusLocalization.t("runtime.webAdministration.sourceSubnetMask"), text: $adminSubnetMask)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.web-administration.mask")

            Button(FiliusLocalization.t("runtime.webAdministration.addNetwork")) {
                addWebAdministrationNetwork()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.device.web-administration.add-network")

            if adminAllowedNetworks.isEmpty {
                Text(FiliusLocalization.t("runtime.webAdministration.noNetworks"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runtime.device.web-administration.networks.empty")
            } else {
                ForEach(adminAllowedNetworks, id: \.self) { network in
                    HStack(spacing: 8) {
                        Text("\(network.networkAddress) / \(network.subnetMask)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            removeWebAdministrationNetwork(network)
                        } label: {
                            Label(
                                FiliusLocalization.t("runtime.webAdministration.removeNetwork"),
                                systemImage: "trash"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel(FiliusLocalization.t("runtime.webAdministration.removeNetwork"))
                        .accessibilityIdentifier("runtime.device.web-administration.remove-network.\(network.networkAddress).\(network.subnetMask)")
                    }
                }
            }

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("runtime.webAdministration.save")) {
                    _ = saveWebAdministrationPolicy()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.web-administration.save")

                Button(
                    webAdministrationRunning
                        ? FiliusLocalization.t("runtime.webAdministration.stop")
                        : FiliusLocalization.t("runtime.webAdministration.start")
                ) {
                    if webAdministrationRunning {
                        onWebAdministrationStop()
                    } else if !adminEnabled {
                        adminConfigurationError = FiliusLocalization.t("runtime.webAdministration.enableRequired")
                    } else if saveWebAdministrationPolicy() {
                        onWebAdministrationStart(adminPort)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("runtime.device.web-administration.toggle")
            }

            Text(
                FiliusLocalization.t(
                    "runtime.webAdministration.status",
                    webAdministrationRunning
                        ? FiliusLocalization.t("runtime.status.running")
                        : FiliusLocalization.t("runtime.status.stopped")
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("runtime.device.web-administration.status")

            if let adminConfigurationError {
                Text(adminConfigurationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("runtime.device.web-administration.error")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.web-administration")
    }

    @discardableResult
    private func saveWebAdministrationPolicy() -> Bool {
        guard !adminEnabled || !adminAllowedNetworks.isEmpty else {
            adminConfigurationError = FiliusLocalization.t("runtime.webAdministration.networkRequired")
            return false
        }
        guard let port = Int(adminPort.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(port)
        else {
            adminConfigurationError = FiliusLocalization.t("runtime.webAdministration.invalidPort")
            return false
        }
        adminPort = String(port)
        adminConfigurationError = nil
        onSaveWebAdministrationConfiguration(
            TopologyRuntimeWebAdministrationConfiguration(
                port: port,
                accessPolicy: TopologyRuntimeWebAdministrationAccessPolicy(
                    isEnabled: adminEnabled,
                    allowedSourceNetworks: adminAllowedNetworks
                )
            )
        )
        return true
    }

    private func addWebAdministrationNetwork() {
        let networkText = adminNetworkAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let maskText = adminSubnetMask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let network = try? TopologyRuntimeWebAdministrationIPv4Network(
            networkAddress: networkText,
            subnetMask: maskText
        ) else {
            adminConfigurationError = FiliusLocalization.t("runtime.webAdministration.invalidNetwork")
            return
        }
        adminAllowedNetworks = TopologyRuntimeWebAdministrationAccessPolicy(
            isEnabled: adminEnabled,
            allowedSourceNetworks: adminAllowedNetworks + [network]
        ).allowedSourceNetworks
        adminNetworkAddress = ""
        adminConfigurationError = nil
    }

    private func removeWebAdministrationNetwork(
        _ network: TopologyRuntimeWebAdministrationIPv4Network
    ) {
        adminAllowedNetworks.removeAll { $0 == network }
        if adminEnabled && adminAllowedNetworks.isEmpty {
            adminConfigurationError = FiliusLocalization.t("runtime.webAdministration.networkRequired")
        } else {
            adminConfigurationError = nil
        }
    }

    private var runtimeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FiliusLocalization.t("runtime.device", deviceTitle))
                .font(.headline)
                .accessibilityIdentifier("runtime.device.sheet.title")

            Text(FiliusLocalization.t("runtime.nodeID", nodeID.uuidString))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("runtime.device.sheet.nodeID")
        }
    }

    private var installedProtocolDefinitions: [TopologyProtocolApplicationDefinition] {
        guard protocolApplicationsEnabled else { return [] }
        return protocolApplicationDefinitions
            .filter { installedProtocolApplicationIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var installedApplicationNames: [String] {
        (installedPrograms.map(\.desktopName) + installedProtocolDefinitions.map(\.name)).sorted()
    }

    private var isRuntimeDesktopVisible: Bool {
        if case .desktop = runtimeWorkspaceDestination { return true }
        return false
    }

    private var runtimeDesktopWorkspaceSection: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            let horizontalWindowInset: CGFloat = compact ? 6 : 14
            let verticalWindowInset: CGFloat = compact ? 54 : 58

            ZStack(alignment: .topLeading) {
                RuntimeDesktopBackgroundView()

                if isRuntimeDesktopVisible {
                    runtimeDesktopIconGrid
                        .padding(.top, compact ? 66 : 76)
                        .padding(.horizontal, compact ? 12 : 18)
                        .padding(.bottom, 78)
                        .transition(.opacity)
                }

                if !isRuntimeDesktopVisible {
                    runtimeDesktopWorkspaceContent
                        .padding(.horizontal, horizontalWindowInset)
                        .padding(.top, verticalWindowInset)
                        .padding(.bottom, 72)
                        .transition(.scale(scale: 0.985).combined(with: .opacity))
                        .zIndex(2)
                }

                runtimeDesktopDeviceBar
                    .padding(10)
                    .zIndex(3)

                if isRuntimeDesktopVisible && !isRuntimeNetworkInfoExpanded {
                    desktopCommandHintSection
                        .frame(maxWidth: compact ? 300 : 380)
                        .padding(.leading, 12)
                        .padding(.bottom, 72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(3)
                }

                if isRuntimeDesktopVisible && isRuntimeNetworkInfoExpanded {
                    runtimeNetworkInfoPanel
                        .frame(maxWidth: compact ? 330 : 390)
                        .padding(.trailing, 12)
                        .padding(.bottom, 72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(4)
                }

                runtimeDesktopTaskbar
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(5)
            }
            .animation(.snappy(duration: 0.24), value: runtimeWorkspaceAnimationKey)
            .animation(.snappy(duration: 0.2), value: isRuntimeNetworkInfoExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.desktop")
    }

    private var runtimeWorkspaceAnimationKey: Int {
        switch runtimeWorkspaceDestination {
        case .desktop:
            return 0
        case .softwareManager:
            return 1
        case let .runtimeProgram(program):
            return 100 + (TopologyRuntimeInstallableProgram.allCases.firstIndex(of: program) ?? 0)
        case let .protocolApplication(definition):
            return 1_000 + (protocolApplicationDefinitions.firstIndex(where: { $0.id == definition.id }) ?? 0)
        }
    }

    private var runtimeDesktopDeviceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: nodeKind == .notebook ? "laptopcomputer" : "desktopcomputer")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(FiliusLocalization.t("runtime.device", deviceTitle))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("runtime.device.sheet.title")

                Text(FiliusLocalization.t("runtime.nodeID", nodeID.uuidString))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("runtime.device.sheet.nodeID")
            }

            Spacer(minLength: 8)

            Text(runtimeNetworkStatusLabel)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.28), in: Circle())
            }
            .buttonStyle(RuntimeDesktopIconButtonStyle())
            .accessibilityLabel(FiliusLocalization.t("ui.e9b450d14bc2"))
            .accessibilityIdentifier("runtime.device.close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.deviceBar")
    }

    @ViewBuilder
    private var runtimeDesktopWorkspaceContent: some View {
        switch runtimeWorkspaceDestination {
        case .desktop:
            EmptyView()

        case .softwareManager:
            runtimeApplicationWindow {
                runtimeApplicationChrome(
                    title: FiliusLocalization.t("softwareManager.title"),
                    systemImage: "shippingbox",
                    status: nil,
                    onBack: { installerExpanded = false }
                )
            } content: {
                installerSection
            }

        case let .runtimeProgram(program):
            if program == .commandPrompt {
                runtimeCommandPromptWindow
            } else {
                runtimeApplicationWindow {
                    runtimeApplicationChrome(
                        title: program.desktopName,
                        program: program,
                        status: runtimeServiceStatus(for: program),
                        backIdentifier: "runtime.device.app.close",
                        onBack: onCloseProgram
                    )
                } content: {
                    appShellSection(for: program)
                }
            }

        case let .protocolApplication(definition):
            runtimeApplicationWindow {
                runtimeApplicationChrome(
                    title: definition.name,
                    systemImage: "network",
                    status: protocolServiceStatus(for: definition),
                    onBack: onCloseProtocolApplication
                )
            } content: {
                protocolApplicationShell(definition: definition)
            }
        }
    }

    private var runtimeDesktopIconGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], alignment: .leading, spacing: 12) {
                ForEach(TopologyRuntimeInstallableProgram.allCases.filter { installedPrograms.contains($0) }, id: \.self) { program in
                    Button {
                        onLaunchProgram(program)
                    } label: {
                        RuntimeDesktopProgramIcon(program: program)
                    }
                    .buttonStyle(RuntimeDesktopIconButtonStyle())
                    .accessibilityIdentifier("runtime.device.launch.\(program.rawValue)")
                }
                ForEach(installedProtocolDefinitions) { definition in
                    Button {
                        onLaunchProtocolApplication(definition.id)
                    } label: {
                        RuntimeDesktopProtocolApplicationIcon(definition: definition)
                    }
                    .buttonStyle(RuntimeDesktopIconButtonStyle())
                    .accessibilityIdentifier("runtime.device.launch.protocol.\(definition.id.uuidString)")
                }
                RuntimeDesktopInstallerIcon(isExpanded: installerExpanded) {
                    installerExpanded.toggle()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(FiliusLocalization.t(
                "runtime.installed",
                installedApplicationNames.joined(separator: ", ").ifEmpty(FiliusLocalization.t("ui.fallback.none"))
            ))
            .font(.caption)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.2), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func runtimeApplicationWindow<Chrome: View, Content: View>(
        @ViewBuilder chrome: () -> Chrome,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            chrome()
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            ScrollView {
                content()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .accessibilityIdentifier("runtime.workspace.contentScroll")
            .scrollIndicators(.visible)
            .background(Color(uiColor: .systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.36), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.window")
    }

    private var runtimeCommandPromptWindow: some View {
        VStack(spacing: 0) {
            runtimeCommandPromptChrome
            commandPromptShell
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.48), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.window")
    }

    private var runtimeCommandPromptChrome: some View {
        HStack(spacing: 9) {
            Image(systemName: "terminal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            VStack(alignment: .leading, spacing: 1) {
                Text(FiliusLocalization.t("runtime.cmd.windowTitle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityIdentifier("runtime.workspace.title")

                Text(terminalPrompt)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onCloseProgram) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 28)
                    .background(Color.red.opacity(0.78), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(RuntimeDesktopIconButtonStyle())
            .accessibilityLabel(FiliusLocalization.t("runtime.workspace.backToDesktop"))
            .accessibilityIdentifier("runtime.device.app.close")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .background(Color(red: 0.105, green: 0.105, blue: 0.12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.chrome")
    }

    private var commandPromptShell: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        Text(FiliusLocalization.t("runtime.cmd.banner"))
                            .fontWeight(.semibold)
                        Text(String(repeating: "=", count: 74))
                        Text(FiliusLocalization.t("runtime.cmd.helpHint"))
                            .accessibilityLabel(
                                "\(TopologyRuntimeCommandCatalog.helpSummary) \(TopologyRuntimeCommandCatalog.substitutionBoundarySummary)"
                            )
                            .accessibilityIdentifier("runtime.device.command.help")
                        Text("")

                        ForEach(Array(consoleEntries.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .accessibilityIdentifier("runtime.device.console.line.\(index)")
                        }

                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("runtime.command.bottom")
                    }
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(red: 0.88, green: 0.88, blue: 0.88))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
                .accessibilityIdentifier("runtime.device.console.list")
                .onAppear {
                    reader.scrollTo("runtime.command.bottom", anchor: .bottom)
                }
                .onChange(of: consoleEntries.count) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        reader.scrollTo("runtime.command.bottom", anchor: .bottom)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 6) {
                Text(terminalPrompt)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(red: 0.88, green: 0.88, blue: 0.88))
                    .lineLimit(1)
                    .accessibilityIdentifier("runtime.device.command.prompt")

                TextField(
                    "",
                    text: $command,
                    prompt: Text(FiliusLocalization.t("runtime.field.commandPrompt"))
                        .foregroundStyle(Color.white.opacity(0.28))
                )
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(red: 0.93, green: 0.93, blue: 0.93))
                    .tint(Color(red: 0.35, green: 0.95, blue: 0.48))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.return)
                    .textFieldStyle(.plain)
                    .onSubmit(executeTerminalCommand)
                    .accessibilityIdentifier("runtime.device.command")

                Button(action: executeTerminalCommand) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.95, blue: 0.48))
                        .frame(width: 38, height: 32)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(RuntimeDesktopIconButtonStyle())
                .accessibilityLabel(FiliusLocalization.t("ui.6ea36ce8d494"))
                .accessibilityIdentifier("runtime.device.execute")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.appShell.commandPrompt")
    }

    private var terminalPrompt: String {
        "\(terminalWorkingDirectory.ifEmpty("/"))>"
    }

    private func executeTerminalCommand() {
        let submittedCommand = command
        onExecuteCommand(submittedCommand)
        command = ""
    }

    private var runtimeDesktopTaskbar: some View {
        HStack(spacing: 8) {
            Button(action: returnToRuntimeDesktop) {
                Label(FiliusLocalization.t("runtime.workspace.applications"), systemImage: "square.grid.2x2.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(isRuntimeDesktopVisible ? Color.gray : Color.accentColor)
            .accessibilityIdentifier("runtime.workspace.applications")

            packetExchangeDestinationLink

            Spacer(minLength: 6)

            Button {
                isRuntimeNetworkInfoExpanded.toggle()
            } label: {
                Label(runtimeNetworkStatusLabel, systemImage: "network")
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.workspace.network")
        }
        .padding(7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.taskbar")
    }

    private var packetExchangeDestinationLink: some View {
        NavigationLink {
            TopologyPacketExchangeDestination(
                tabs: packetCaptureTabs,
                rows: packetMessageRows,
                packetLayerPath: packetLayerPath,
                onReset: onResetPacketCapture,
                onExport: onExportPacketCapture
            )
        } label: {
            Label(FiliusLocalization.t("ui.69c4593fb91f"), systemImage: "arrow.left.arrow.right")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("runtime.device.packet-exchange.show")
    }

    private var runtimeNetworkStatusLabel: String {
        let ipAddress = configuration?.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ipAddress.isEmpty || ipAddress == "0.0.0.0"
            ? FiliusLocalization.t("runtime.workspace.network")
            : ipAddress
    }

    private var runtimeNetworkInfoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(FiliusLocalization.t("runtime.workspace.networkInformation"), systemImage: "network")
                .font(.subheadline.weight(.semibold))

            LabeledContent(
                FiliusLocalization.t("editor.field.ipAddress"),
                value: configuration?.ipAddress.ifEmpty("—") ?? "—"
            )
            .accessibilityIdentifier("runtime.workspace.network.ip")
            LabeledContent(
                FiliusLocalization.t("editor.field.subnetMask"),
                value: configuration?.subnetMask.ifEmpty("—") ?? "—"
            )
            .accessibilityIdentifier("runtime.workspace.network.subnet")
            LabeledContent(
                FiliusLocalization.t("editor.field.gatewayOptional"),
                value: configuration?.defaultGateway.ifEmpty("—") ?? "—"
            )
            .accessibilityIdentifier("runtime.workspace.network.gateway")

            Text(FiliusLocalization.t("runtime.workspace.networkConfiguredInDesign"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            dhcpControlsSection
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.network.info")
    }

    private func returnToRuntimeDesktop() {
        isRuntimeNetworkInfoExpanded = false
        switch runtimeWorkspaceDestination {
        case .desktop:
            break
        case .softwareManager:
            installerExpanded = false
        case .runtimeProgram:
            onCloseProgram()
        case .protocolApplication:
            onCloseProtocolApplication()
        }
    }

    private var installerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            softwareManagerSectionTitle(FiliusLocalization.t("softwareManager.installed"))
            if installedPrograms.isEmpty {
                Text(FiliusLocalization.t("softwareManager.noneInstalled"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(TopologyRuntimeInstallableProgram.allCases.filter { installedPrograms.contains($0) }, id: \.self) { program in
                    softwareManagerRow(program: program, isInstalled: true)
                }
            }

            Divider()
            softwareManagerSectionTitle(FiliusLocalization.t("softwareManager.available"))
            ForEach(TopologyRuntimeInstallableProgram.allCases.filter { !installedPrograms.contains($0) }, id: \.self) { program in
                softwareManagerRow(program: program, isInstalled: false)
            }
            if protocolApplicationsEnabled {
                ForEach(protocolApplicationDefinitions.filter { !installedProtocolApplicationIDs.contains($0.id) }) { definition in
                    HStack(spacing: 10) {
                        RuntimeDesktopProtocolApplicationIcon(definition: definition, compact: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.name).font(.subheadline.weight(.semibold))
                            Text(FiliusLocalization.t(
                                "protocol.installer.description",
                                localizedProtocolRole(definition.role),
                                definition.transport.displayName,
                                Int(definition.port)
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(FiliusLocalization.t("ui.fd6c3ebf7bef")) {
                            onInstallProtocolApplication(definition.id)
                            installerExpanded = false
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("runtime.device.install.protocol.\(definition.id.uuidString)")
                    }
                }
            }

            Text(FiliusLocalization.t("softwareManager.dataPreserved"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.installer")
    }

    private func softwareManagerSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func softwareManagerRow(program: TopologyRuntimeInstallableProgram, isInstalled: Bool) -> some View {
        HStack(spacing: 10) {
            RuntimeDesktopProgramIcon(program: program, compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(program.desktopName).font(.subheadline.weight(.semibold))
                Text(program.desktopDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isInstalled {
                Button(FiliusLocalization.t("softwareManager.uninstall"), role: .destructive) {
                    onUninstallProgram(program)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("runtime.device.uninstall.\(program.rawValue)")
            } else {
                Button(FiliusLocalization.t("ui.fd6c3ebf7bef")) {
                    onInstallProgram(program)
                    installerExpanded = false
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.install.\(program.rawValue)")
            }
        }
    }

    private func runtimeApplicationChrome(
        title: String,
        program: TopologyRuntimeInstallableProgram? = nil,
        systemImage: String = "app",
        status: String?,
        backIdentifier: String = "runtime.workspace.back",
        onBack: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            if let program {
                RuntimeDesktopProgramIcon(program: program, compact: true)
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("runtime.workspace.title")
                if let status {
                    Label(
                        status,
                        systemImage: status == FiliusLocalization.t("runtime.workspace.running")
                            ? "circle.fill"
                            : "circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        status == FiliusLocalization.t("runtime.workspace.running")
                            ? Color.green
                            : Color.secondary
                    )
                }
            }

            Spacer(minLength: 8)

            Button(action: onBack) {
                Label(FiliusLocalization.t("runtime.workspace.backToDesktop"), systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier(backIdentifier)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.workspace.chrome")
    }

    private func runtimeServiceStatus(for program: TopologyRuntimeInstallableProgram) -> String? {
        let isRunning: Bool
        switch program {
        case .webServer: isRunning = webServerState != nil
        case .echoServer: isRunning = echoServerState != nil
        case .dnsServer: isRunning = dnsServerState != nil
        case .emailServer: isRunning = emailServerProcessState.isRunning
        case .gnutella: isRunning = gnutellaSessionState.isRunning
        default: return nil
        }
        return isRunning ? FiliusLocalization.t("runtime.workspace.running") : FiliusLocalization.t("runtime.workspace.stopped")
    }

    private func protocolServiceStatus(for definition: TopologyProtocolApplicationDefinition) -> String? {
        guard definition.role == .server else { return nil }
        return activeProtocolServerState == nil
            ? FiliusLocalization.t("runtime.workspace.stopped")
            : FiliusLocalization.t("runtime.workspace.running")
    }

    private func localizedProtocolRole(_ role: TopologyProtocolApplicationRole) -> String {
        FiliusLocalization.t(role == .client ? "protocol.role.client" : "protocol.role.server")
    }

    private func protocolApplicationShell(definition: TopologyProtocolApplicationDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(FiliusLocalization.t(
                "protocol.builder.summary",
                localizedProtocolRole(definition.role),
                definition.transport.displayName,
                Int(definition.port)
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            if definition.role == .server {
                Text(activeProtocolServerState == nil
                    ? FiliusLocalization.t("protocol.runtime.server.stopped")
                    : FiliusLocalization.t("protocol.runtime.server.running"))
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Button(FiliusLocalization.t("protocol.runtime.start")) {
                        onStartProtocolServer(definition.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(activeProtocolServerState != nil)
                    Button(FiliusLocalization.t("protocol.runtime.stop")) {
                        onStopProtocolServer(definition.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(activeProtocolServerState == nil)
                }
                Text(FiliusLocalization.t("protocol.runtime.firstMatch", definition.responseRules.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                protocolRuntimeLog(activeProtocolServerState?.logs ?? [])
            } else {
                TextField(FiliusLocalization.t("protocol.runtime.destination"), text: $protocolClientDestination)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("runtime.device.protocol.destination")
                Picker(FiliusLocalization.t("protocol.runtime.message"), selection: $selectedProtocolTemplateID) {
                    ForEach(definition.clientMessageTemplates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("runtime.device.protocol.message")
                Button(FiliusLocalization.t("protocol.runtime.send")) {
                    guard let selectedProtocolTemplateID else { return }
                    onSendProtocolClientMessage(definition.id, protocolClientDestination, selectedProtocolTemplateID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProtocolTemplateID == nil || protocolClientDestination.isEmpty)
                .accessibilityIdentifier("runtime.device.protocol.send")
                protocolRuntimeLog(activeProtocolClientState?.logs ?? [])
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityIdentifier("runtime.device.protocol.appShell")
    }

    private func localizedProtocolRuntimeDirection(_ direction: String) -> String {
        switch direction {
        case "system": return FiliusLocalization.t("protocol.runtime.direction.system")
        case "outbound": return FiliusLocalization.t("protocol.runtime.direction.outbound")
        case "inbound": return FiliusLocalization.t("protocol.runtime.direction.inbound")
        case "error": return FiliusLocalization.t("protocol.runtime.direction.error")
        case "timeout": return FiliusLocalization.t("protocol.runtime.direction.timeout")
        case "unmatched": return FiliusLocalization.t("protocol.runtime.direction.unmatched")
        default: return direction
        }
    }

    private func protocolRuntimeLog(_ entries: [TopologyProtocolApplicationRuntimeLogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FiliusLocalization.t("protocol.runtime.log")).font(.caption.weight(.semibold))
            if entries.isEmpty {
                Text(FiliusLocalization.t("protocol.runtime.log.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries.suffix(20)) { entry in
                    Text(FiliusLocalization.t(
                        "protocol.runtime.log.entry",
                        entry.timestampMilliseconds,
                        localizedProtocolRuntimeDirection(entry.direction),
                        entry.message
                    ))
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func appShellSection(for program: TopologyRuntimeInstallableProgram) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch program {
            case .commandPrompt:
                EmptyView()

            case .fileExplorer:
                fileExplorerShell
                consoleSection

            case .imageViewer:
                imageViewerShell
                consoleSection

            case .textEditor:
                textEditorShell
                consoleSection

            case .dnsServer:
                dnsServiceShell
                consoleSection

            case .dhcpServer:
                dhcpServiceShell
                consoleSection

            case .webServer:
                webServerShell
                consoleSection

            case .webBrowser:
                webBrowserShell
                consoleSection

            case .echoServer:
                echoServerShell
                consoleSection

            case .simpleClient:
                simpleClientShell
                consoleSection

            case .firewall:
                personalFirewallShell

            case .emailClient:
                emailClientShell
                consoleSection

            case .emailServer:
                emailServerShell
                consoleSection

            case .gnutella:
                gnutellaShell
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.appShell.\(program.rawValue)")
    }

    private var gnutellaShell: some View {
        TopologyRuntimeGnutellaView(
            configuration: gnutellaConfiguration,
            session: gnutellaSessionState,
            fileSystem: virtualFileSystem,
            onSaveConfiguration: onSaveGnutellaConfiguration,
            onJoin: onGnutellaJoin,
            onResetNetwork: onGnutellaResetNetwork,
            onSearch: onGnutellaSearch,
            onClearSearchResults: onGnutellaClearSearchResults,
            onDownload: onGnutellaDownload
        )
    }

    private var emailClientShell: some View {
        TopologyRuntimeEmailReplyDeletionView(
            configuration: emailClientConfiguration,
            state: emailClientState,
            onSaveConfiguration: onSaveEmailClientConfiguration,
            onSend: onSendEmail,
            onRetrieve: onRetrieveEmail,
            onDeleteMessages: onDeleteEmailMessages
        )
    }

    private var emailServerShell: some View {
        TopologyRuntimeEmailServerView(
            configuration: emailServerConfiguration,
            processState: emailServerProcessState,
            configurationFields: { configuration in
                TopologyRuntimeEmailServerView.ConfigurationFields(
                    domain: configuration.domain,
                    smtpPort: String(TopologyRuntimeEmailServerConfiguration.smtpPort),
                    pop3Port: String(configuration.pop3Port)
                )
            },
            accounts: { $0.accounts },
            accountFields: { account in
                let names = splitEmailAccountName(account.name)
                return TopologyRuntimeEmailServerView.AccountFields(
                    id: account.username.lowercased(),
                    username: account.username,
                    password: account.password,
                    firstName: names.first,
                    lastName: names.last,
                    mailboxCount: account.mailbox.count
                )
            },
            stateFields: { process in
                TopologyRuntimeEmailServerView.StateFields(
                    isRunning: process.isRunning,
                    statusLocalizationKey: process.isRunning ? "email.server.status.running" : "email.server.status.stopped"
                )
            },
            logs: { $0.logs },
            logFields: { entry in
                TopologyRuntimeEmailServerView.LogFields(
                    id: String(entry.id),
                    timestamp: String(entry.timestampMilliseconds),
                    message: FiliusLocalization.t("email.logs.entry", entry.protocolName, entry.direction, entry.message)
                )
            },
            onSaveConfiguration: { fields in
                let pop3Port = Int(fields.pop3Port) ?? 0
                var configuration = emailServerConfiguration
                configuration.domain = fields.domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                configuration.pop3Port = pop3Port
                onSaveEmailServerConfiguration(configuration)
            },
            onAddAccount: { draft in
                var configuration = emailServerConfiguration
                configuration.accounts.append(emailServerAccount(from: draft, mailbox: []))
                onSaveEmailServerConfiguration(configuration)
            },
            onUpdateAccount: { accountID, draft in
                var configuration = emailServerConfiguration
                guard let index = configuration.accounts.firstIndex(where: { $0.username.lowercased() == accountID.lowercased() })
                else { return }
                configuration.accounts[index] = emailServerAccount(from: draft, mailbox: configuration.accounts[index].mailbox)
                onSaveEmailServerConfiguration(configuration)
            },
            onDeleteAccount: { accountID in
                var configuration = emailServerConfiguration
                configuration.accounts.removeAll { $0.username.lowercased() == accountID.lowercased() }
                onSaveEmailServerConfiguration(configuration)
            },
            onMoveAccount: { accountID, destinationIndex in
                var configuration = emailServerConfiguration
                guard let sourceIndex = configuration.accounts.firstIndex(where: { $0.username.lowercased() == accountID.lowercased() }),
                      configuration.accounts.indices.contains(destinationIndex)
                else { return }
                let account = configuration.accounts.remove(at: sourceIndex)
                configuration.accounts.insert(account, at: destinationIndex)
                onSaveEmailServerConfiguration(configuration)
            },
            onStart: { fields in
                let pop3Port = Int(fields.pop3Port) ?? 0
                var configuration = emailServerConfiguration
                configuration.domain = fields.domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                configuration.pop3Port = pop3Port
                onStartEmailServer(configuration)
            },
            onStop: onStopEmailServer
        )
    }

    private func parsedEmailAddresses(_ rawValue: String) -> [TopologyRuntimeEmailAddress] {
        rawValue
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { token in
                let value = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
                return TopologyRuntimeEmailAddress(javaString: value)
                    ?? TopologyRuntimeEmailAddress(mailAddress: value)
            }
    }

    private func splitEmailAccountName(_ name: String) -> (first: String, last: String) {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = parts.first else { return ("", "") }
        return (first, parts.dropFirst().joined(separator: " "))
    }

    private func emailServerAccount(
        from draft: TopologyRuntimeEmailServerView.AccountDraft,
        mailbox: [TopologyRuntimeEmailMessage]
    ) -> TopologyRuntimeEmailServerAccount {
        TopologyRuntimeEmailServerAccount(
            username: draft.username,
            password: draft.password,
            name: [draft.firstName, draft.lastName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            mailbox: mailbox
        )
    }

    private var personalFirewallShell: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                FiliusLocalization.t("runtime.firewall.enabled"),
                isOn: Binding(
                    get: { firewallConfiguration.isActive },
                    set: { value in updatePersonalFirewall { $0.isActive = value } }
                )
            )
            .accessibilityIdentifier("runtime.device.app.firewall.enabled")

            Toggle(
                FiliusLocalization.t("runtime.firewall.allowICMP"),
                isOn: Binding(
                    get: { !firewallConfiguration.dropICMP },
                    set: { value in updatePersonalFirewall { $0.dropICMP = !value } }
                )
            )
            .disabled(!firewallConfiguration.isActive)
            .accessibilityIdentifier("runtime.device.app.firewall.allowICMP")

            Toggle(
                FiliusLocalization.t("runtime.firewall.filterUDP"),
                isOn: Binding(
                    get: { firewallConfiguration.filterUDP },
                    set: { value in updatePersonalFirewall { $0.filterUDP = value } }
                )
            )
            .disabled(!firewallConfiguration.isActive)
            .accessibilityIdentifier("runtime.device.app.firewall.filterUDP")

            Divider()

            Text(FiliusLocalization.t("runtime.firewall.allowRules"))
                .font(.subheadline.weight(.semibold))

            Picker(FiliusLocalization.t("runtime.firewall.protocol"), selection: $personalFirewallProtocol) {
                Text("TCP").tag(TopologyFirewallProtocol.tcp)
                Text("UDP").tag(TopologyFirewallProtocol.udp)
                Text(FiliusLocalization.t("runtime.firewall.protocol.all")).tag(TopologyFirewallProtocol.all)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("runtime.device.app.firewall.protocol")

            TextField(FiliusLocalization.t("runtime.firewall.port"), text: $personalFirewallPort)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.firewall.port")

            Toggle(FiliusLocalization.t("runtime.firewall.sameNetwork"), isOn: $personalFirewallSameNetwork)
                .accessibilityIdentifier("runtime.device.app.firewall.sameNetwork")

            Button(FiliusLocalization.t("runtime.firewall.addRule")) {
                guard let port = personalFirewallPortValue else { return }
                updatePersonalFirewall { configuration in
                    configuration.rules.append(
                        TopologyFirewallRule(
                            sourceIPAddress: personalFirewallSameNetwork
                                ? TopologyFirewallRule.directlyConnectedSourceMarker : "",
                            port: port,
                            protocolType: personalFirewallProtocol,
                            action: .accept
                        )
                    )
                }
                personalFirewallPort = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(personalFirewallPortValue == nil)
            .accessibilityIdentifier("runtime.device.app.firewall.addRule")

            if firewallConfiguration.rules.isEmpty {
                Text(FiliusLocalization.t("runtime.firewall.noRules"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(firewallConfiguration.rules.enumerated()), id: \.offset) { index, rule in
                    HStack(spacing: 8) {
                        Text(personalFirewallRuleLabel(rule))
                            .font(.caption.monospaced())
                        Spacer(minLength: 8)
                        Button(FiliusLocalization.t("runtime.firewall.deleteRule"), role: .destructive) {
                            updatePersonalFirewall { configuration in
                                guard configuration.rules.indices.contains(index) else { return }
                                configuration.rules.remove(at: index)
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("runtime.device.app.firewall.deleteRule.\(index)")
                    }
                }
            }

            Divider()

            Text(FiliusLocalization.t("runtime.firewall.decisionLog"))
                .font(.subheadline.weight(.semibold))
            if firewallDecisions.isEmpty {
                Text(FiliusLocalization.t("runtime.firewall.noDecisions"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(firewallDecisions.suffix(40).reversed().enumerated()), id: \.offset) { _, decision in
                    Text(FiliusLocalization.t(
                        "runtime.firewall.decision",
                        String(decision.packetIdentity),
                        decision.accepted
                            ? FiliusLocalization.t("runtime.firewall.accepted")
                            : FiliusLocalization.t("runtime.firewall.dropped"),
                        decision.ruleIndex.map { String($0 + 1) } ?? "â€”"
                    ))
                    .font(.caption.monospaced())
                    .foregroundStyle(decision.accepted ? Color.secondary : Color.red)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.firewall.shell")
    }

    private var personalFirewallPortValue: Int? {
        guard let value = Int(personalFirewallPort), (0...65_535).contains(value) else { return nil }
        return value
    }

    private func updatePersonalFirewall(_ update: (inout TopologyFirewallConfiguration) -> Void) {
        onSaveFirewallConfiguration(
            updatingPersonalFirewallConfiguration(firewallConfiguration, update: update)
        )
    }

    private func personalFirewallRuleLabel(_ rule: TopologyFirewallRule) -> String {
        FiliusLocalization.t(
            "runtime.firewall.rule",
            rule.protocolType.javaLabel,
            String(rule.port),
            rule.sourceIPAddress == TopologyFirewallRule.directlyConnectedSourceMarker
                ? FiliusLocalization.t("runtime.firewall.scope.sameNetwork")
                : FiliusLocalization.t("runtime.firewall.scope.allSenders")
        )
    }

    private var dnsServiceRecords: [TopologyDNSResourceRecord] {
        dnsRecords.sorted(by: TopologyDNSResourceRecord.deterministicOrder)
    }

    private static func initialDirectoryPath(
        for selectedPath: String,
        in fileSystem: TopologyVirtualFileSystem
    ) -> String {
        guard !selectedPath.isEmpty,
              let selectedEntry = try? fileSystem.entry(at: selectedPath)
        else { return "/" }
        return selectedEntry.content.isDirectory ? selectedEntry.path : selectedEntry.parentPath
    }

    private func existingDirectoryPath(_ path: String) -> String {
        guard let entry = try? virtualFileSystem.entry(at: path), entry.content.isDirectory else {
            return "/"
        }
        return entry.path
    }

    private var fileExplorerCurrentDirectoryPath: String {
        existingDirectoryPath(fileExplorerDirectoryPath)
    }

    private var imageViewerCurrentDirectoryPath: String {
        existingDirectoryPath(imageViewerDirectoryPath)
    }

    private var fileExplorerEntries: [TopologyVirtualFileEntry] {
        (try? virtualFileSystem.entries(in: fileExplorerCurrentDirectoryPath)) ?? []
    }

    private var imageViewerEntries: [TopologyVirtualFileEntry] {
        ((try? virtualFileSystem.entries(in: imageViewerCurrentDirectoryPath)) ?? []).filter {
            $0.content.isDirectory || $0.content.isImage
        }
    }

    private var textEditorEntries: [TopologyVirtualFileEntry] {
        virtualFileSystem.allEntries().filter {
            if case .text = $0.content { return true }
            return false
        }
    }

    private func runtimeDirectoryNavigationBar(
        currentPath: String,
        backIdentifier: String,
        pathIdentifier: String,
        onBack: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Label(FiliusLocalization.t("runtime.workspace.parentFolder"), systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(currentPath == "/")
            .accessibilityLabel(FiliusLocalization.t("runtime.workspace.parentFolder"))
            .accessibilityIdentifier(backIdentifier)

            Label(currentPath, systemImage: "folder.fill")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(FiliusLocalization.t("runtime.workspace.currentFolder", currentPath))
                .accessibilityIdentifier(pathIdentifier)
        }
    }

    private var fileExplorerShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.700869dc5e37"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.file.title")

            Text(FiliusLocalization.t("ui.61393f28c0fd"))
                .font(.caption)
                .foregroundStyle(.secondary)

            runtimeDirectoryNavigationBar(
                currentPath: fileExplorerCurrentDirectoryPath,
                backIdentifier: "runtime.device.app.file.back",
                pathIdentifier: "runtime.device.app.file.path",
                onBack: {
                    fileExplorerDirectoryPath = TopologyVirtualFileSystem.parentPath(
                        ofNormalizedPath: fileExplorerCurrentDirectoryPath
                    )
                }
            )

            Text(FiliusLocalization.plural(
                "runtime.files",
                count: fileExplorerEntries.filter { $0.content.isFile }.count
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("runtime.device.app.file.count")

            ForEach(fileExplorerEntries) { entry in
                if entry.content.isDirectory {
                    Button {
                        fileExplorerDirectoryPath = entry.path
                    } label: {
                        runtimeFileEntryLabel(entry, selected: false)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(FiliusLocalization.t("runtime.workspace.openFolder", entry.name))
                    .accessibilityIdentifier("runtime.device.app.file.open.\(entry.path)")
                } else {
                    Button {
                        selectedFileEntryID = entry.path
                        onFileExplorerSelectEntry(entry.path)
                    } label: {
                        runtimeFileEntryLabel(entry, selected: selectedFileEntryID == entry.path)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.file.select.\(entry.path)")
                }
            }

            if fileExplorerEntries.isEmpty {
                Text(FiliusLocalization.t("runtime.workspace.folderEmpty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            TextField(FiliusLocalization.t("runtime.field.absolutePath"), text: $newFileSystemPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.file.newPath")
            TextField(FiliusLocalization.t("runtime.field.textFileContents"), text: $newTextFileContents)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.file.newText")
            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.d8eddd700a83")) { onFileSystemCreateDirectory(newFileSystemPath) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.file.createDirectory")
                Button(FiliusLocalization.t("ui.97492ab50012")) { onFileSystemCreateTextFile(newFileSystemPath, newTextFileContents) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.file.createTextFile")
            }

            TextField(FiliusLocalization.t("runtime.field.copyMoveDestination"), text: $destinationFileSystemPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.file.destination")
            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.af74f7c5362a")) { onFileSystemCopyItem(selectedFileEntryID, destinationFileSystemPath) }
                    .buttonStyle(.bordered)
                    .disabled(selectedFileEntryID.isEmpty)
                Button(FiliusLocalization.t("ui.76cdb9507216")) { onFileSystemMoveItem(selectedFileEntryID, destinationFileSystemPath) }
                    .buttonStyle(.bordered)
                    .disabled(selectedFileEntryID.isEmpty)
            }

            TextField(FiliusLocalization.t("runtime.field.newName"), text: $renamedFileSystemName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.file.rename")
            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.d3f4cb898fbe")) { onFileSystemRenameItem(selectedFileEntryID, renamedFileSystemName) }
                    .buttonStyle(.bordered)
                    .disabled(selectedFileEntryID.isEmpty)
                Button(FiliusLocalization.t("ui.f6fdbe48dc54"), role: .destructive) { onFileSystemDeleteItem(selectedFileEntryID, true) }
                    .buttonStyle(.bordered)
                    .disabled(selectedFileEntryID.isEmpty)
            }

            Text(FiliusLocalization.t("runtime.selected", selectedFileEntryID.ifEmpty(FiliusLocalization.t("ui.fallback.none"))))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.app.file.selected")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.file.shell")
    }

    private func runtimeFileEntryLabel(
        _ entry: TopologyVirtualFileEntry,
        selected: Bool
    ) -> some View {
        HStack {
            Image(systemName: fileSystemIcon(for: entry, selected: selected))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.caption.monospaced())
                Text(entry.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if entry.content.isDirectory {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var imageViewerShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.6b84bca7ebef"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.image.title")

            runtimeDirectoryNavigationBar(
                currentPath: imageViewerCurrentDirectoryPath,
                backIdentifier: "runtime.device.app.image.back",
                pathIdentifier: "runtime.device.app.image.path",
                onBack: {
                    imageViewerDirectoryPath = TopologyVirtualFileSystem.parentPath(
                        ofNormalizedPath: imageViewerCurrentDirectoryPath
                    )
                }
            )

            ForEach(imageViewerEntries) { entry in
                if entry.content.isDirectory {
                    Button {
                        imageViewerDirectoryPath = entry.path
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text(entry.name)
                                .font(.caption.monospaced())
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(FiliusLocalization.t("runtime.workspace.openFolder", entry.name))
                    .accessibilityIdentifier("runtime.device.app.image.open.\(entry.path)")
                } else {
                    Button {
                        selectedImageID = entry.path
                        onImageViewerSelectImage(entry.path)
                    } label: {
                        HStack {
                            Image(systemName: selectedImageID == entry.path ? "photo.fill" : "photo")
                            Text(entry.name)
                                .font(.caption.monospaced())
                            Spacer(minLength: 8)
                            if selectedImageID == entry.path {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.image.select.\(entry.path)")
                }
            }

            if let image = selectedVirtualImage {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .accessibilityLabel(FiliusLocalization.t("runtime.virtualImage", selectedImageID))
                    .accessibilityIdentifier("runtime.device.app.image.preview")
            } else if imageViewerEntries.isEmpty {
                Text(FiliusLocalization.t("runtime.workspace.folderHasNoImages"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(FiliusLocalization.t("runtime.viewing", selectedImageID.ifEmpty(FiliusLocalization.t("ui.fallback.none"))))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.app.image.selected")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.image.shell")
    }

    private var textEditorShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.35b97fcdedac"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.text.title")

            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("ui.ee3d21a8808c"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    isTextEditorFileMenuExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedTextEditorPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Image(systemName: isTextEditorFileMenuExpanded ? "chevron.up" : "chevron.down")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("runtime.device.app.text.file")

                if isTextEditorFileMenuExpanded {
                    VStack(spacing: 0) {
                        ForEach(textEditorEntries) { entry in
                            Button {
                                isTextEditorFileMenuExpanded = false
                                guard entry.path != textEditorSelection else { return }
                                onTextEditorSelectFile(entry.path)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: entry.path == selectedTextEditorPath ? "checkmark" : "circle")
                                        .opacity(entry.path == selectedTextEditorPath ? 1 : 0)
                                    Text(entry.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 8)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("runtime.device.app.text.file.option.\(entry.path)")

                            if entry.id != textEditorEntries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                }
            }

            TextEditor(text: $textEditorDraftInput)
                .font(.caption.monospaced())
                .frame(minHeight: 130)
                .padding(4)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("runtime.device.app.text.input")

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.b63f828f806f")) { onTextEditorUpdateDraft(textEditorDraftInput) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("runtime.device.app.text.apply")
                Button(FiliusLocalization.t("ui.437f4cef0fbb")) { onTextEditorSaveDraft() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.text.save")
                Button(FiliusLocalization.t("ui.cce7155371fc")) {
                    onTextEditorResetDraft()
                    textEditorDraftInput = textEditorDraft ?? ""
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.text.reset")
            }

            Text(textEditorStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.app.text.status")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.text.shell")
        .onAppear(perform: synchronizeDesktopSuiteFields)
        .onDisappear { isTextEditorFileMenuExpanded = false }
    }

    private var selectedTextEditorPath: String {
        textEditorSelection ?? textEditorEntries.first?.path ?? ""
    }

    private var selectedVirtualImage: UIImage? {
        guard let entry = try? virtualFileSystem.entry(at: selectedImageID),
              case let .image(data, _) = entry.content
        else { return nil }
        return UIImage(data: data)
    }

    private func fileSystemIcon(for entry: TopologyVirtualFileEntry, selected: Bool) -> String {
        if entry.content.isDirectory { return selected ? "folder.fill" : "folder" }
        if entry.content.isImage { return selected ? "photo.fill" : "photo" }
        if case .text = entry.content { return selected ? "doc.text.fill" : "doc.text" }
        return selected ? "doc.fill" : "doc"
    }

    private var dnsServiceShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.f8e963997a67"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.dns.title")

            HStack(spacing: 8) {
                Text(dnsServerState == nil ? FiliusLocalization.t("runtime.workspace.stopped") : FiliusLocalization.t("runtime.dnsStatus"))
                    .font(.caption)
                    .foregroundStyle(dnsServerState == nil ? Color.secondary : Color.green)
                    .accessibilityIdentifier("runtime.device.app.dns.status")
                Button(dnsServerState == nil ? FiliusLocalization.t("runtime.dns.start") : FiliusLocalization.t("runtime.dns.stop")) {
                    if dnsServerState == nil { onDNSStart() } else { onDNSStop() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.app.dns.lifecycle")
            }

            Toggle(FiliusLocalization.t("runtime.dns.recursive"), isOn: $dnsRecursionEnabled)
                .accessibilityIdentifier("runtime.device.app.dns.recursive")

            TextField(FiliusLocalization.t("runtime.dns.forwarder"), text: $dnsForwarder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.dns.forwarder")

            Button(FiliusLocalization.t("common.save")) {
                onDNSSetRecursion(dnsRecursionEnabled, dnsForwarder)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.device.app.dns.recursion.save")

            Text(FiliusLocalization.t("runtime.dns.recordType"))
                .font(.caption.weight(.semibold))
            Picker(FiliusLocalization.t("runtime.dns.recordType"), selection: $dnsRecordType) {
                ForEach(TopologyDNSRecordType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("runtime.device.app.dns.recordType")

            TextField(FiliusLocalization.t("runtime.field.hostname"), text: $dnsHostname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.dns.hostname")

            TextField(dnsRecordType == .address ? FiliusLocalization.t("runtime.field.ipv4Target") : FiliusLocalization.t("runtime.dns.target"), text: $dnsTarget)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(dnsRecordType == .address ? .numbersAndPunctuation : .URL)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.dns.target")

            TextField(FiliusLocalization.t("runtime.dns.ttl"), text: $dnsTTL)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.dns.ttl")

            Button(FiliusLocalization.t("ui.26e7da5e099a")) {
                guard let ttl = UInt32(dnsTTL.trimmingCharacters(in: .whitespacesAndNewlines)), ttl > 0 else { return }
                onDNSAddTypedRecord(dnsHostname, dnsRecordType, dnsTarget, ttl)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.app.dns.add")

            Text(FiliusLocalization.t("runtime.field.resolveHostname"))
                .font(.caption.weight(.semibold))
            Picker(FiliusLocalization.t("runtime.dns.lookupType"), selection: $dnsLookupRecordType) {
                ForEach(TopologyDNSRecordType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("runtime.device.app.dns.lookupType")

            TextField(FiliusLocalization.t("runtime.field.resolveHostname"), text: $dnsLookupHostname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.dns.lookupHost")

            Button(FiliusLocalization.t("ui.ac7f958cc028")) {
                onDNSResolveTypedRecord(dnsLookupHostname, dnsLookupRecordType)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.device.app.dns.resolve")

            if dnsServiceRecords.isEmpty {
                Text(FiliusLocalization.t("ui.76d7149eb0f6"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runtime.device.app.dns.records.empty")
            } else {
                ForEach(dnsServiceRecords, id: \.self) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(record.name.absoluteString) \(record.type.rawValue) \(record.ttlSeconds) \(record.target)")
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(role: .destructive) {
                            onDNSRemoveTypedRecord(record)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(FiliusLocalization.t("ui.27ce64c41ff2"))
                    }
                    .accessibilityIdentifier("runtime.device.app.dns.record.\(record.name.rawValue).\(record.type.rawValue).\(record.target)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.dns.shell")
    }

    private var dhcpServiceShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.d0284a352f15"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.dhcp.title")

            Text(FiliusLocalization.t("ui.9e3ed80b507e"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(FiliusLocalization.t("ui.713eb4ed21ce")) {
                isDHCPConfigurationPresented = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.app.dhcp.configure")

            Text(dhcpLeaseSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.app.dhcp.status")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.dhcp.shell")
    }

    private var webServerShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.a030328790b9"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.web.title")

            TextField(FiliusLocalization.t("runtime.field.port"), text: $webPort)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.web.port")
            TextField(FiliusLocalization.t("runtime.web.documentRoot"), text: $webDocumentRoot)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.web.document-root")

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("runtime.web.saveConfiguration")) {
                    saveWebServerConfiguration()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("runtime.device.app.web.save")
                Button(FiliusLocalization.t("ui.952f375412e8")) { onWebStart(webPort) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("runtime.device.app.web.start")
                Button(FiliusLocalization.t("ui.9e253470c876")) { onWebStop() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.web.stop")
                Button(FiliusLocalization.t("runtime.web.restartAction")) { onWebRestart(webPort) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.web.restart")
            }

            Text(FiliusLocalization.t("runtime.web.virtualHosts"))
                .font(.caption.weight(.semibold))
            TextField(FiliusLocalization.t("runtime.web.virtualHostID"), text: $virtualHostID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.web.virtual-host.id")
            TextField(FiliusLocalization.t("runtime.web.virtualHostName"), text: $virtualHostHostname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.web.virtual-host.hostname")
            HStack(spacing: 8) {
                TextField(FiliusLocalization.t("runtime.web.virtualHostPort"), text: $virtualHostPort)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("runtime.device.app.web.virtual-host.port")
                TextField(FiliusLocalization.t("runtime.web.virtualHostRoot"), text: $virtualHostDocumentRoot)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("runtime.device.app.web.virtual-host.root")
            }
            Toggle(FiliusLocalization.t("runtime.web.virtualHostEnabled"), isOn: $virtualHostEnabled)
                .accessibilityIdentifier("runtime.device.app.web.virtual-host.enabled")
            HStack(spacing: 8) {
                Button(FiliusLocalization.t("runtime.web.virtualHostSave")) { saveVirtualHost() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.web.virtual-host.save")
                Button(FiliusLocalization.t("ui.8955ab6bc1d4")) { clearVirtualHostEditor() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.web.virtual-host.new")
                if webServerConfiguration.virtualHostConfiguration != nil {
                    Button(FiliusLocalization.t("runtime.web.virtualHostClear")) {
                        onSaveWebServerConfiguration(
                            TopologyRuntimeWebServerConfiguration(
                                port: Int(webPort) ?? webServerConfiguration.port,
                                documentRoot: webDocumentRoot,
                                virtualHostConfiguration: nil
                            )
                        )
                        selectedVirtualHostID = nil
                        selectedDefaultVirtualHostID = nil
                        clearVirtualHostEditor()
                        webConfigurationError = nil
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("runtime.device.app.web.virtual-host.clear")
                }
            }
            if let configuration = webServerConfiguration.virtualHostConfiguration {
                Picker(
                    FiliusLocalization.t("runtime.web.virtualHostDefault"),
                    selection: Binding(
                        get: { selectedDefaultVirtualHostID ?? configuration.defaultHostID },
                        set: { setDefaultVirtualHost($0) }
                    )
                ) {
                    ForEach(configuration.hosts.filter(\.isEnabled)) { host in
                        Text(host.id).tag(host.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("runtime.device.app.web.virtual-host.default")

                ForEach(configuration.hosts) { host in
                    HStack {
                        Button { selectVirtualHost(host) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(host.id) · \(host.authority.hostname)\(host.authority.port.map { ":\($0)" } ?? "")")
                                    .font(.caption.monospaced())
                                Text(host.documentRoot)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("runtime.device.app.web.virtual-host.edit.\(host.id)")
                        if host.id == configuration.defaultHostID {
                            Text(FiliusLocalization.t("runtime.web.virtualHostDefault"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) { removeVirtualHost(host) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("runtime.device.app.web.virtual-host.delete.\(host.id)")
                    }
                    .padding(6)
                    .background(
                        selectedVirtualHostID == host.id ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("runtime.device.app.web.virtual-host.\(host.id)")
                }
            }
            if let webConfigurationError {
                Text(webConfigurationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("runtime.device.app.web.error")
            }

            Text(webServerSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.app.web.status")

            if !webServerRequestLogs.isEmpty {
                Text(FiliusLocalization.t("runtime.web.requestLog"))
                    .font(.caption.weight(.semibold))
                ForEach(webServerRequestLogs.suffix(8)) { entry in
                    Text("\(entry.method) \(entry.path) → \(entry.statusCode) (\(entry.remoteIPAddress))")
                        .font(.caption2.monospaced())
                        .accessibilityIdentifier("runtime.device.app.web.log.\(entry.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.web.shell")
    }

    private func saveWebServerConfiguration() {
        guard let port = Int(webPort), (1...65_535).contains(port) else {
            webConfigurationError = FiliusLocalization.t("runtime.web.invalidPort")
            return
        }
        let configuration = TopologyRuntimeWebServerConfiguration(
            port: port,
            documentRoot: webDocumentRoot,
            virtualHostConfiguration: webServerConfiguration.virtualHostConfiguration
        )
        do {
            try configuration.validate()
        } catch {
            webConfigurationError = error.localizedDescription
            return
        }
        onSaveWebServerConfiguration(configuration)
        webConfigurationError = nil
    }

    private func saveVirtualHost() {
        guard let port = virtualHostPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : UInt16(virtualHostPort),
            virtualHostPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || port != 0,
            !virtualHostID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !virtualHostHostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            webConfigurationError = FiliusLocalization.t("runtime.web.invalidVirtualHost")
            return
        }
        guard let host = try? TopologyRuntimeWebVirtualHost(
            id: virtualHostID,
            hostname: virtualHostHostname,
            port: port,
            documentRoot: virtualHostDocumentRoot,
            isEnabled: virtualHostEnabled
        ) else {
            webConfigurationError = FiliusLocalization.t("runtime.web.invalidVirtualHost")
            return
        }
        let configuration: TopologyRuntimeWebVirtualHostConfiguration
        do {
            configuration = try TopologyRuntimeVirtualHostEditor.saving(
                host,
                selectedHostID: selectedVirtualHostID,
                selectedDefaultHostID: selectedDefaultVirtualHostID,
                in: webServerConfiguration.virtualHostConfiguration
            )
        } catch {
            webConfigurationError = error.localizedDescription
            return
        }
        guard let webPortValue = Int(webPort), (1...65_535).contains(webPortValue) else {
            webConfigurationError = FiliusLocalization.t("runtime.web.invalidPort")
            return
        }
        onSaveWebServerConfiguration(
            TopologyRuntimeWebServerConfiguration(
                port: webPortValue,
                documentRoot: webDocumentRoot,
                virtualHostConfiguration: configuration
            )
        )
        selectedVirtualHostID = host.id
        selectedDefaultVirtualHostID = configuration.defaultHostID
        webConfigurationError = nil
    }

    private func selectVirtualHost(_ host: TopologyRuntimeWebVirtualHost) {
        selectedVirtualHostID = host.id
        virtualHostID = host.id
        virtualHostHostname = host.authority.hostname
        virtualHostPort = host.authority.port.map(String.init) ?? ""
        virtualHostDocumentRoot = host.documentRoot
        virtualHostEnabled = host.isEnabled
        webConfigurationError = nil
    }

    private func clearVirtualHostEditor() {
        selectedVirtualHostID = nil
        virtualHostID = ""
        virtualHostHostname = ""
        virtualHostPort = ""
        virtualHostDocumentRoot = webDocumentRoot
        virtualHostEnabled = true
        webConfigurationError = nil
    }

    private func setDefaultVirtualHost(_ hostID: String) {
        guard let existing = webServerConfiguration.virtualHostConfiguration,
              existing.hosts.contains(where: { $0.id == hostID && $0.isEnabled }),
              let configuration = try? TopologyRuntimeWebVirtualHostConfiguration(
                hosts: existing.hosts,
                defaultHostID: hostID
              )
        else {
            webConfigurationError = FiliusLocalization.t("runtime.web.invalidVirtualHost")
            return
        }
        onSaveWebServerConfiguration(
            TopologyRuntimeWebServerConfiguration(
                port: Int(webPort) ?? webServerConfiguration.port,
                documentRoot: webDocumentRoot,
                virtualHostConfiguration: configuration
            )
        )
        selectedDefaultVirtualHostID = hostID
        webConfigurationError = nil
    }

    private func removeVirtualHost(_ host: TopologyRuntimeWebVirtualHost) {
        guard let existing = webServerConfiguration.virtualHostConfiguration else { return }
        let configuration: TopologyRuntimeWebVirtualHostConfiguration?
        do {
            configuration = try TopologyRuntimeVirtualHostEditor.removing(
                hostID: host.id,
                from: existing
            )
        } catch {
            webConfigurationError = error.localizedDescription
            return
        }
        onSaveWebServerConfiguration(
            TopologyRuntimeWebServerConfiguration(
                port: Int(webPort) ?? webServerConfiguration.port,
                documentRoot: webDocumentRoot,
                virtualHostConfiguration: configuration
            )
        )
        selectedDefaultVirtualHostID = configuration?.defaultHostID
        if selectedVirtualHostID == host.id {
            clearVirtualHostEditor()
        }
    }

    private var webBrowserShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("runtime.app.webBrowser"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.browser.title")
            TextField(FiliusLocalization.t("runtime.browser.addressPrompt"), text: $browserAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .onSubmit { onWebBrowserNavigate(browserAddress) }
                .accessibilityIdentifier("runtime.device.app.browser.address")
            HStack(spacing: 8) {
                Button(FiliusLocalization.t("runtime.browser.go")) { onWebBrowserNavigate(browserAddress) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("runtime.device.app.browser.go")
                Button(FiliusLocalization.t("runtime.browser.back")) { onWebBrowserBack() }
                    .buttonStyle(.bordered)
                    .disabled(!(webBrowserState?.canNavigateBack ?? false))
                    .accessibilityIdentifier("runtime.device.app.browser.back")
                Button(FiliusLocalization.t("runtime.browser.forward")) { onWebBrowserForward() }
                    .buttonStyle(.bordered)
                    .disabled(!(webBrowserState?.canNavigateForward ?? false))
                    .accessibilityIdentifier("runtime.device.app.browser.forward")
                Button(FiliusLocalization.t("runtime.browser.clear")) { onWebBrowserReset() }
                    .buttonStyle(.bordered)
            }
            if let webBrowserState {
                Text(webBrowserState.statusCode.map { FiliusLocalization.t("runtime.browser.httpStatus", $0, webBrowserState.contentType ?? "") } ?? (webBrowserState.connectionState == .loading ? FiliusLocalization.t("runtime.browser.loading") : FiliusLocalization.t("runtime.browser.idle")))
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("runtime.device.app.browser.status")
                if let errorMessage = webBrowserState.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("runtime.device.app.browser.error")
                }
                webBrowserBody(webBrowserState)
                .frame(minHeight: 100, maxHeight: 220)
                .background(Color(uiColor: .systemBackground))
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
                .accessibilityIdentifier("runtime.device.app.browser.body")
                if !webBrowserState.history.isEmpty {
                    Text(FiliusLocalization.t("runtime.browser.history", webBrowserState.history.map(\.address).joined(separator: " → ")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.browser.shell")
        .onChange(of: webBrowserState?.address) { _, newAddress in
            browserAddress = newAddress ?? ""
        }
    }

    @ViewBuilder
    private func webBrowserBody(_ state: TopologyRuntimeWebBrowserState) -> some View {
        if state.body.isEmpty {
            ScrollView {
                Text(FiliusLocalization.t("runtime.browser.emptyResponse"))
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        } else if state.shouldRenderBodyAsHTML {
            RuntimeHTMLWebView(
                html: state.body,
                currentAddress: state.address,
                onSimulatedRequest: handleSimulatedBrowserRequest
            )
        } else {
            ScrollView {
                Text(state.body)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    private func handleSimulatedBrowserRequest(_ request: TopologyRuntimeWebBrowserRequest) {
        guard let encodedAddress = request.encodedNavigationAddress else {
            browserAddress = request.address
            return
        }
        onWebBrowserNavigate(encodedAddress)
    }

    private var echoServerShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.28af9abb91ad"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.echo.title")

            TextField(FiliusLocalization.t("runtime.field.port"), text: $echoPort)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.echo.port")

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.952f375412e8")) {
                    onEchoStart(echoPort)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.app.echo.start")

                Button(FiliusLocalization.t("ui.9e253470c876")) {
                    onEchoStop()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("runtime.device.app.echo.stop")
            }

            Text(echoServerSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.app.echo.status")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.echo.shell")
    }

    private var simpleClientShell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.8b3d693eaaf5"))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("runtime.device.app.simple-client.title")

            Picker(FiliusLocalization.t("ui.1ed77c3f7ffc"), selection: $simpleClientProtocol) {
                ForEach(TopologyRuntimeTransportProtocol.allCases, id: \.self) { protocolKind in
                    Text(protocolKind.displayName).tag(protocolKind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("runtime.device.app.simple-client.protocol")

            TextField(FiliusLocalization.t("runtime.field.destinationIPv4"), text: $simpleClientDestination)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.simple-client.destination")

            TextField(FiliusLocalization.t("runtime.field.port"), text: $simpleClientPort)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.simple-client.port")

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.b65463cb6a42")) {
                    onSimpleClientConnect(simpleClientDestination, simpleClientPort, simpleClientProtocol)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("runtime.device.app.simple-client.connect")

                Button(FiliusLocalization.t("ui.ed28e0686e12")) {
                    onSimpleClientDisconnect()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("runtime.device.app.simple-client.disconnect")
            }

            TextField(FiliusLocalization.t("runtime.field.message"), text: $simpleClientMessage)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.app.simple-client.message")

            Button(FiliusLocalization.t("ui.9bc2575c3930")) {
                onSimpleClientSend(simpleClientMessage)
                simpleClientMessage = ""
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.app.simple-client.send")

            if let simpleClientState {
                Text(FiliusLocalization.t("runtime.status", simpleClientState.connectionState.rawValue, simpleClientState.destinationIPAddress, simpleClientState.destinationPort))
                    .font(.caption)
                    .accessibilityIdentifier("runtime.device.app.simple-client.status")
                ForEach(simpleClientState.logs.suffix(12)) { entry in
                    Text(FiliusLocalization.t("runtime.simpleClientEntry", entry.direction, entry.message))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("runtime.device.app.simple-client.log.\(entry.id)")
                }
            } else {
                Text(FiliusLocalization.t("ui.771e05f27b99"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runtime.device.app.simple-client.status")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.device.app.simple-client.shell")
    }

    private var dhcpLeaseSummary: String {
        guard let dhcpLease else {
            return FiliusLocalization.t("runtime.dhcp.noLease")
        }

        return FiliusLocalization.t("runtime.dhcp.activeLease", dhcpLease.ipAddress, dhcpLease.subnetMask)
    }

    private var webServerSummary: String {
        guard let webServerState else {
            return FiliusLocalization.t("runtime.web.stopped")
        }

        return FiliusLocalization.t("runtime.web.running", webServerState.port)
    }

    private var echoServerSummary: String {
        guard let echoServerState else {
            return FiliusLocalization.t("runtime.echo.stopped")
        }

        return FiliusLocalization.t("runtime.echo.running", echoServerState.port)
    }

    private var textEditorStatus: String {
        FiliusLocalization.t(
            "runtime.textEditor.draftStatus",
            (textEditorSelection ?? "").ifEmpty(FiliusLocalization.t("ui.fallback.none")),
            textEditorDraftInput.count
        )
    }

    private var dhcpControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                FiliusLocalization.t("runtime.dhcp.useForConfiguration"),
                isOn: Binding(get: { dhcpClientConfiguration.isEnabled }, set: onSetDHCPClientEnabled)
            )
            .accessibilityIdentifier("runtime.device.dhcp.clientEnabled")

            Button(FiliusLocalization.t("ui.713eb4ed21ce")) {
                isDHCPConfigurationPresented = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.device.dhcp.configureServer")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("runtime.device.dhcp.controls")
    }

    private var dhcpServerSubnetMask: String {
        if nodeKind == .gateway {
            return interfaceConfigurations.indices.contains(1)
                ? interfaceConfigurations[1].configuration?.subnetMask ?? "255.255.255.0"
                : "255.255.255.0"
        }
        return configuration?.subnetMask ?? "255.255.255.0"
    }

    private var dhcpServerGatewayIPAddress: String {
        if nodeKind == .gateway {
            return interfaceConfigurations.indices.contains(1)
                ? interfaceConfigurations[1].configuration?.ipAddress ?? "0.0.0.0"
                : "0.0.0.0"
        }
        return dhcpServerConfiguration.gatewayIPAddress
    }

    private var dhcpServerDNSServerIPAddress: String {
        if nodeKind == .gateway {
            return dhcpServerConfiguration.dnsServerIPAddress
        }
        if dhcpServerConfiguration.useOwnSettings {
            return dhcpServerConfiguration.dnsServerIPAddress
        }
        return configuration?.dnsServer ?? "0.0.0.0"
    }

    private var switchRetentionSeconds: UInt64 {
        (switchConfiguration?.retentionTimeMilliseconds
            ?? TopologySwitchConfiguration.defaultRetentionTimeMilliseconds) / 1_000
    }

    private var switchInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(FiliusLocalization.t("ui.ed75426612fb"))
                .font(.subheadline.weight(.semibold))

            LabeledContent(FiliusLocalization.t("ui.a5eb8edab8ed"), value: switchConfiguration?.ssid ?? "-")
                .accessibilityIdentifier("runtime.device.switch.ssid")
            LabeledContent(FiliusLocalization.t("ui.94385a434bfa"), value: FiliusLocalization.t("runtime.seconds", switchRetentionSeconds))
            .accessibilityIdentifier("runtime.device.switch.retention")

            Divider()

            HStack {
                Text(FiliusLocalization.t("ui.c304503bacaf"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(FiliusLocalization.t("ui.e305b8c66ec3"), action: onClearSwitchSAT)
                    .buttonStyle(.bordered)
                    .disabled(switchSATEntries.isEmpty)
                    .accessibilityIdentifier("runtime.device.switch.sat.clear")
            }

            if switchSATEntries.isEmpty {
                Text(FiliusLocalization.t("ui.5b5f2c96201d"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runtime.device.switch.sat.empty")
            } else {
                ForEach(switchSATEntries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.macAddress)
                            .font(.caption.monospaced().weight(.semibold))
                        HStack {
                            Text(FiliusLocalization.t("runtime.port", entry.portLabel))
                            Spacer()
                            Text(FiliusLocalization.t("runtime.updated", String(entry.updatedAtMilliseconds)))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("runtime.device.switch.sat.entry.\(entry.macAddress)")
                }
            }

            Text(FiliusLocalization.t("ui.5eda88b74509"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("runtime.device.switch.info")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infrastructureConfigurationSection(
        title: String,
        detail: String,
        identifierPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(interfaceConfigurations) { item in
                RuntimeInterfaceConfigurationRow(
                    item: item,
                    identifierPrefix: identifierPrefix,
                    onSave: { ipAddress, subnetMask in
                        onSaveInterfaceConfiguration(item.id, ipAddress, subnetMask)
                    }
                )
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifierPrefix).info")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).configuration")
    }

    private var unsupportedInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.265856ba1562"))
                .font(.subheadline.weight(.semibold))
            Text(FiliusLocalization.t("ui.53f973064fae"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var desktopCommandHintSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.a1f52cdcb3f2"))
                .font(.subheadline.weight(.semibold))

            if hasCommandPromptInstalled {
                Text(FiliusLocalization.t("ui.b86c2d4b2678"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runtime.device.command.desktopHint")
            } else {
                Text(FiliusLocalization.t("ui.7bb2260523d6"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("runtime.device.command.locked")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
    }

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.08e4da4e4f3b"))
                .font(.subheadline.weight(.semibold))

            TextField(FiliusLocalization.t("runtime.field.commandPrompt"), text: $command)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("runtime.device.command")

            VStack(alignment: .leading, spacing: 4) {
                Text(TopologyRuntimeCommandCatalog.helpSummary)
                Text(TopologyRuntimeCommandCatalog.substitutionBoundarySummary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(TopologyRuntimeCommandCatalog.helpSummary) \(TopologyRuntimeCommandCatalog.substitutionBoundarySummary)")
            .accessibilityIdentifier("runtime.device.command.help")

            Button(FiliusLocalization.t("ui.6ea36ce8d494")) {
                onExecuteCommand(command)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("runtime.device.execute")
        }
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.9f3341d3710b"))
                .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if consoleEntries.isEmpty {
                        Text(FiliusLocalization.t("ui.8baa8ea3e7b9"))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("runtime.device.console.empty")
                    } else {
                        ForEach(Array(consoleEntries.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("runtime.device.console.line.\(index)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .accessibilityIdentifier("runtime.device.console.list")
        }
    }

    private var deviceTitle: String {
        topologyRuntimeDeviceTitle(for: nodeKind)
    }

    private func synchronizeServiceFields() {
        dhcpLeaseIPAddress = dhcpLease?.ipAddress ?? ""
        dhcpLeaseSubnetMask = dhcpLease?.subnetMask ?? ""
        webPort = String(webServerState?.port ?? 80)
        echoPort = String(echoServerState?.port ?? 55555)
        simpleClientDestination = simpleClientState?.destinationIPAddress ?? ""
        simpleClientPort = String(simpleClientState?.destinationPort ?? 55555)
        simpleClientProtocol = simpleClientState?.protocolKind ?? .tcp
    }

    private func synchronizeDesktopSuiteFields() {
        let files = virtualFileSystem.allEntries().filter { $0.content.isFile }
        let images = files.filter { $0.content.isImage }
        selectedFileEntryID = fileExplorerSelection ?? files.first?.path ?? ""
        selectedImageID = imageViewerSelection ?? images.first?.path ?? ""
        if existingDirectoryPath(fileExplorerDirectoryPath) != fileExplorerDirectoryPath {
            fileExplorerDirectoryPath = Self.initialDirectoryPath(
                for: selectedFileEntryID,
                in: virtualFileSystem
            )
        }
        if existingDirectoryPath(imageViewerDirectoryPath) != imageViewerDirectoryPath {
            imageViewerDirectoryPath = Self.initialDirectoryPath(
                for: selectedImageID,
                in: virtualFileSystem
            )
        }
        textEditorDraftInput = textEditorDraft ?? ""
    }
}

private struct RuntimeDesktopBackgroundView: View {
    var body: some View {
        GeometryReader { proxy in
            if let image = TopologyParityAssetLoader.load(relativePath: "desktop/hintergrundbild.png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.45, blue: 0.80),
                        Color(red: 0.12, green: 0.30, blue: 0.62)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

private struct RuntimeDesktopInstallerIcon: View {
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                RuntimeDesktopImageView(
                    relativePath: "desktop/icon_softwareinstallation.png",
                    fallbackSystemImage: "shippingbox"
                )
                .frame(width: 42, height: 42)

                HStack(spacing: 2) {
                    Text(FiliusLocalization.t("ui.b32f3008bf03"))

                    if isExpanded {
                        Image(systemName: "chevron.down")
                            .accessibilityHidden(true)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
            }
            .padding(6)
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("runtime.device.install.open")
    }
}

private struct RuntimeInterfaceConfigurationRow: View {
    let item: TopologyRuntimeInterfaceConfigurationItem
    let identifierPrefix: String
    let onSave: (String, String) -> Void

    @State private var ipAddress: String
    @State private var subnetMask: String

    init(
        item: TopologyRuntimeInterfaceConfigurationItem,
        identifierPrefix: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.item = item
        self.identifierPrefix = identifierPrefix
        self.onSave = onSave
        _ipAddress = State(initialValue: item.configuration?.ipAddress ?? "")
        _subnetMask = State(initialValue: item.configuration?.subnetMask ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label.uppercased())
                .font(.caption.weight(.bold))
                .accessibilityIdentifier("\(rowIdentifier).label")

            TextField(FiliusLocalization.t("runtime.field.ipv4Address"), text: $ipAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("\(rowIdentifier).ip")

            TextField(FiliusLocalization.t("runtime.field.subnetMask"), text: $subnetMask)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("\(rowIdentifier).subnet")

            Button(FiliusLocalization.t("runtime.save", item.label.uppercased())) {
                onSave(ipAddress, subnetMask)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("\(rowIdentifier).save")
        }
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rowIdentifier)
        .onChange(of: item.configuration) { _, newConfiguration in
            ipAddress = newConfiguration?.ipAddress ?? ""
            subnetMask = newConfiguration?.subnetMask ?? ""
        }
    }

    private var rowIdentifier: String {
        "\(identifierPrefix).interface.\(item.label.lowercased())"
    }
}

private struct RuntimeDesktopIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(.rect)
    }
}

private struct RuntimeDesktopProtocolApplicationIcon: View {
    let definition: TopologyProtocolApplicationDefinition
    var compact = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: definition.role == .client ? "arrow.left.arrow.right.circle.fill" : "server.rack")
                .font(.system(size: compact ? 24 : 34, weight: .semibold))
                .foregroundStyle(.white, Color.blue)
                .frame(width: compact ? 32 : 42, height: compact ? 32 : 42)
            Text(definition.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(compact ? Color.primary : Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: compact ? 44 : 68)
    }
}

private struct RuntimeDesktopProgramIcon: View {
    let program: TopologyRuntimeInstallableProgram
    var compact = false

    var body: some View {
        VStack(spacing: 4) {
            RuntimeDesktopImageView(
                relativePath: program.desktopIconRelativePath,
                fallbackSystemImage: program.fallbackSystemImage
            )
            .frame(width: compact ? 24 : 42, height: compact ? 24 : 42)

            if !compact {
                Text(program.desktopName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(compact ? 0 : 6)
        .background(compact ? Color.clear : Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RuntimeDesktopImageView: View {
    let relativePath: String
    let fallbackSystemImage: String

    var body: some View {
        if let image = TopologyParityAssetLoader.load(relativePath: relativePath) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        }
    }
}

private struct TopologyDHCPStaticAssignmentDraft: Identifiable, Equatable {
    let id: UUID
    var macAddress: String
    var ipAddress: String
}

private struct TopologyDHCPConfigurationView: View {
    let nodeKind: TopologyNodeKind
    let configuration: TopologyDHCPServerConfiguration
    let subnetMask: String
    let gatewayIPAddress: String
    let dnsServerIPAddress: String
    let onSave: (TopologyDHCPServerConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var isActive: Bool
    @State private var lowerBoundIPAddress: String
    @State private var upperBoundIPAddress: String
    @State private var gatewayIPAddressInput: String
    @State private var dnsServerIPAddressInput: String
    @State private var useOwnSettings: Bool
    @State private var staticAssignments: [TopologyDHCPStaticAssignmentDraft]
    @State private var selectedAssignmentID: UUID?
    @State private var newMACAddress = ""
    @State private var newIPAddress = ""

    init(
        nodeKind: TopologyNodeKind,
        configuration: TopologyDHCPServerConfiguration,
        subnetMask: String,
        gatewayIPAddress: String,
        dnsServerIPAddress: String,
        onSave: @escaping (TopologyDHCPServerConfiguration) -> Void
    ) {
        self.nodeKind = nodeKind
        self.configuration = configuration
        self.subnetMask = subnetMask
        self.gatewayIPAddress = gatewayIPAddress
        self.dnsServerIPAddress = dnsServerIPAddress
        self.onSave = onSave
        _isActive = State(initialValue: configuration.isActive)
        _lowerBoundIPAddress = State(initialValue: configuration.lowerBoundIPAddress)
        _upperBoundIPAddress = State(initialValue: configuration.upperBoundIPAddress)
        _gatewayIPAddressInput = State(initialValue: gatewayIPAddress)
        _dnsServerIPAddressInput = State(initialValue: dnsServerIPAddress)
        _useOwnSettings = State(initialValue: nodeKind == .gateway ? false : configuration.useOwnSettings)
        _staticAssignments = State(
            initialValue: configuration.staticAssignments.map {
                TopologyDHCPStaticAssignmentDraft(
                    id: $0.id,
                    macAddress: $0.macAddress,
                    ipAddress: $0.ipAddress
                )
            }
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker(FiliusLocalization.t("ui.6f232460c45f"), selection: $selectedTab) {
                Text(FiliusLocalization.t("ui.80363d5ffaba")).tag(0)
                Text(FiliusLocalization.t("ui.7c0dc3b89e65")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .accessibilityIdentifier("runtime.device.dhcp.dialog.tabs")

            Group {
                if selectedTab == 0 {
                    generalSettings
                } else {
                    staticAssignmentSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(FiliusLocalization.t("ui.9ce3bd4224c8")) {
                saveAndDismiss()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("runtime.device.dhcp.dialog.ok")
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .frame(minWidth: 380, idealWidth: 380, minHeight: 380, idealHeight: 380)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("runtime.device.dhcp.dialog")
        .onChange(of: useOwnSettings) { _, enabled in
            guard nodeKind != .gateway else { return }
            if enabled {
                gatewayIPAddressInput = configuration.gatewayIPAddress
                dnsServerIPAddressInput = configuration.dnsServerIPAddress
            } else {
                gatewayIPAddressInput = gatewayIPAddress
                dnsServerIPAddressInput = dnsServerIPAddress
            }
        }
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dhcpField(
                    label: "Adress-Untergrenze",
                    text: $lowerBoundIPAddress,
                    isEditable: true,
                    validator: isValidIPv4Address,
                    identifier: "runtime.device.dhcp.dialog.lowerBound"
                )
                dhcpField(
                    label: "Adress-Obergrenze",
                    text: $upperBoundIPAddress,
                    isEditable: true,
                    validator: isValidIPv4Address,
                    identifier: "runtime.device.dhcp.dialog.upperBound"
                )
                dhcpReadOnlyField(
                    label: "Netzmaske",
                    value: subnetMask,
                    identifier: "runtime.device.dhcp.dialog.subnetMask"
                )

                VStack(alignment: .leading, spacing: 12) {
                    dhcpField(
                        label: "Gateway",
                        text: $gatewayIPAddressInput,
                        isEditable: nodeKind != .gateway && useOwnSettings,
                        validator: isValidIPv4Address,
                        identifier: "runtime.device.dhcp.dialog.gateway"
                    )
                    dhcpField(
                        label: "DNS-Server",
                        text: $dnsServerIPAddressInput,
                        isEditable: nodeKind == .gateway || useOwnSettings,
                        validator: isValidIPv4Address,
                        identifier: "runtime.device.dhcp.dialog.dnsServer"
                    )

                    if nodeKind != .gateway {
                        Toggle(FiliusLocalization.t("ui.05d6665cc493"), isOn: $useOwnSettings)
                            .accessibilityIdentifier("runtime.device.dhcp.dialog.manualSettings")
                    }
                }
                .padding(10)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.gray, lineWidth: 2)
                }

                Toggle(FiliusLocalization.t("ui.b35b19a43eea"), isOn: $isActive)
                    .accessibilityIdentifier("runtime.device.dhcp.dialog.active")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private var staticAssignmentSettings: some View {
        VStack(spacing: 6) {
            dhcpField(
                label: "MAC-Adresse",
                text: $newMACAddress,
                isEditable: true,
                validator: isValidMACAddress,
                emptyIsNeutral: true,
                identifier: "runtime.device.dhcp.dialog.static.mac"
            )
            dhcpField(
                label: "IP-Adresse",
                text: $newIPAddress,
                isEditable: true,
                validator: isValidIPv4Address,
                identifier: "runtime.device.dhcp.dialog.static.ip"
            )

            HStack(spacing: 8) {
                Button(FiliusLocalization.t("ui.f0d37b9d26bb")) {
                    addStaticAssignment()
                }
                .disabled(!isValidMACAddress(newMACAddress) || !isValidIPv4Address(newIPAddress))
                .accessibilityIdentifier("runtime.device.dhcp.dialog.static.add")

                Button(FiliusLocalization.t("ui.f78b6376e028")) {
                    removeSelectedStaticAssignment()
                }
                .disabled(selectedAssignmentID == nil)
                .accessibilityIdentifier("runtime.device.dhcp.dialog.static.remove")
            }
            .buttonStyle(.bordered)

            HStack(spacing: 0) {
                Text(FiliusLocalization.t("ui.7362d72d1ecc"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(FiliusLocalization.t("ui.e866588c6891"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 30)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($staticAssignments) { $assignment in
                        HStack(spacing: 6) {
                            Button {
                                selectedAssignmentID = assignment.id
                            } label: {
                                Image(systemName: selectedAssignmentID == assignment.id
                                    ? "largecircle.fill.circle"
                                    : "circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(FiliusLocalization.t("ui.93cd0e1d27a7"))

                            validatedTextField(
                                text: $assignment.macAddress,
                                validator: isValidMACAddress,
                                emptyIsNeutral: false,
                                identifier: "runtime.device.dhcp.dialog.static.row.\(assignment.id.uuidString).mac"
                            )
                            validatedTextField(
                                text: $assignment.ipAddress,
                                validator: isValidIPv4Address,
                                emptyIsNeutral: false,
                                identifier: "runtime.device.dhcp.dialog.static.row.\(assignment.id.uuidString).ip"
                            )
                        }
                        .frame(height: 30)
                        .padding(.horizontal, 6)
                        .background(selectedAssignmentID == assignment.id ? Color.accentColor.opacity(0.12) : Color.white)
                        .overlay(alignment: .bottom) {
                            Divider()
                        }
                    }
                }
            }
            .background(Color.white)
            .overlay {
                Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1)
            }
            .accessibilityIdentifier("runtime.device.dhcp.dialog.static.table")
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func dhcpField(
        label: String,
        text: Binding<String>,
        isEditable: Bool,
        validator: @escaping (String) -> Bool,
        emptyIsNeutral: Bool = false,
        identifier: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 165, alignment: .leading)
            validatedTextField(
                text: text,
                validator: validator,
                emptyIsNeutral: emptyIsNeutral,
                identifier: identifier
            )
            .frame(width: 150)
            .disabled(!isEditable)
            .opacity(isEditable ? 1 : 0.65)
        }
    }

    private func dhcpReadOnlyField(label: String, value: String, identifier: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 165, alignment: .leading)
            TextField("", text: .constant(value))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150, height: 25)
                .disabled(true)
                .accessibilityIdentifier(identifier)
        }
    }

    private func validatedTextField(
        text: Binding<String>,
        validator: @escaping (String) -> Bool,
        emptyIsNeutral: Bool,
        identifier: String
    ) -> some View {
        let valid = validator(text.wrappedValue)
        let neutral = emptyIsNeutral && text.wrappedValue.isEmpty
        return TextField("", text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.plain)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, minHeight: 25, maxHeight: 25)
            .foregroundStyle(neutral ? Color.primary : (valid ? Color.green : Color.red))
            .background(Color(uiColor: .systemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(neutral || valid ? Color.gray.opacity(0.55) : Color.red, lineWidth: 1)
            }
            .accessibilityIdentifier(identifier)
            .accessibilityValue(valid ? FiliusLocalization.t("runtime.validation.valid") : FiliusLocalization.t("runtime.validation.invalid"))
    }

    private func addStaticAssignment() {
        guard isValidMACAddress(newMACAddress), isValidIPv4Address(newIPAddress) else { return }
        let assignment = TopologyDHCPStaticAssignmentDraft(
            id: UUID(),
            macAddress: newMACAddress,
            ipAddress: newIPAddress
        )
        staticAssignments.append(assignment)
        selectedAssignmentID = assignment.id
        newMACAddress = ""
        newIPAddress = ""
    }

    private func removeSelectedStaticAssignment() {
        guard let selectedAssignmentID else { return }
        staticAssignments.removeAll { $0.id == selectedAssignmentID }
        self.selectedAssignmentID = nil
    }

    private func saveAndDismiss() {
        let validAssignments = staticAssignments.compactMap { assignment -> TopologyDHCPStaticAssignment? in
            guard isValidMACAddress(assignment.macAddress),
                  isValidIPv4Address(assignment.ipAddress) else { return nil }
            return TopologyDHCPStaticAssignment(
                id: assignment.id,
                macAddress: assignment.macAddress,
                ipAddress: assignment.ipAddress
            )
        }
        onSave(
            TopologyDHCPServerConfiguration(
                isActive: isActive,
                lowerBoundIPAddress: lowerBoundIPAddress,
                upperBoundIPAddress: upperBoundIPAddress,
                gatewayIPAddress: gatewayIPAddressInput,
                dnsServerIPAddress: dnsServerIPAddressInput,
                useOwnSettings: nodeKind == .gateway ? false : useOwnSettings,
                staticAssignments: validAssignments
            )
        )
        dismiss()
    }

    private func isValidIPv4Address(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 4 else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy(\.isNumber) && (Int(segment) ?? 256) <= 255
        }
    }

    private func isValidMACAddress(_ value: String) -> Bool {
        let segments = value.split(separator: ":", omittingEmptySubsequences: false)
        return segments.count == 6 && segments.allSatisfy { segment in
            segment.count == 2 && segment.allSatisfy(\.isHexDigit)
        }
    }
}

private struct TopologyFirewallRuleDraft: Identifiable, Equatable {
    let id: UUID
    let originalRule: TopologyFirewallRule
    var sourceIPAddress: String
    var sourceSubnetMask: String
    var destinationIPAddress: String
    var destinationSubnetMask: String
    var port: String
    var protocolType: TopologyFirewallProtocol
    var action: TopologyFirewallAction

    init(rule: TopologyFirewallRule = TopologyFirewallRule()) {
        id = UUID()
        originalRule = rule
        sourceIPAddress = rule.sourceIPAddress
        sourceSubnetMask = rule.sourceSubnetMask
        destinationIPAddress = rule.destinationIPAddress
        destinationSubnetMask = rule.destinationSubnetMask
        port = rule.port == TopologyFirewallRule.allPorts ? "*" : String(rule.port)
        protocolType = rule.protocolType
        action = rule.action
    }
}

private struct TopologyPortForwardingView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: ([TopologyGatewayPortForwardingRow]) -> Void

    @State private var rows: [TopologyGatewayPortForwardingRow]
    @State private var selectedRowIndex: Int?

    private let columnWidths: [CGFloat] = [80, 60, 130, 60]

    init(
        rows: [TopologyGatewayPortForwardingRow],
        onSave: @escaping ([TopologyGatewayPortForwardingRow]) -> Void
    ) {
        self.onSave = onSave
        _rows = State(initialValue: rows)
        _selectedRowIndex = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width) {
                    compactForwardingContent
                } else {
                    regularForwardingContent
                }
            }
            .padding(12)
            .navigationTitle(FiliusLocalization.t("ui.cfba2f20d168"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(FiliusLocalization.t("ui.44424b18700e")) {
                        onSave(rows)
                        dismiss()
                    }
                    .accessibilityIdentifier("runtime.port-forwarding.close")
                }
            }
        }
        .frame(minHeight: 380)
        .accessibilityIdentifier("runtime.port-forwarding.dialog")
    }

    private var regularForwardingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        headerCell(FiliusLocalization.t("runtime.header.protocol"), width: columnWidths[0])
                        headerCell(FiliusLocalization.t("runtime.header.portForwarding"), width: columnWidths[1])
                        headerCell(FiliusLocalization.t("runtime.header.lanAddress"), width: columnWidths[2])
                        headerCell(FiliusLocalization.t("runtime.header.lanPort"), width: columnWidths[3])
                    }
                    ForEach(Array(rows.indices), id: \.self) { index in
                        forwardingTableRow(index: index)
                    }
                }
            }
            .frame(minHeight: 300)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.55), lineWidth: 1))
            forwardingActions
        }
    }

    private var compactForwardingContent: some View {
        VStack(spacing: 8) {
            ScrollView(.vertical) {
            LazyVStack(spacing: 8) {
                ForEach(Array(rows.indices), id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            selectedRowIndex = index
                        } label: {
                            HStack {
                                Text(FiliusLocalization.t("runtime.rowNumber", index + 1))
                                    .font(.headline)
                                Spacer()
                                Image(systemName: selectedRowIndex == index
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .foregroundStyle(selectedRowIndex == index ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedRowIndex == index ? .isSelected : [])
                        .accessibilityIdentifier("runtime.port-forwarding.row.\(index).select")
                        Picker(FiliusLocalization.t("runtime.header.protocol"), selection: Binding(
                            get: { rows[index].runtimeProtocol == .udp ? "UDP" : "TCP" },
                            set: { rows[index].protocolValue = $0 }
                        )) {
                            Text(FiliusLocalization.t("ui.f544fb304c83")).tag("TCP")
                            Text(FiliusLocalization.t("ui.e9a6f622e340")).tag("UDP")
                        }
                        .accessibilityIdentifier("runtime.port-forwarding.row.\(index).protocol")
                        compactForwardingField(
                            title: FiliusLocalization.t("runtime.header.portForwarding"),
                            text: binding(index: index, keyPath: \.publicPortValue),
                            valid: rows[index].runtimePublicPort != nil,
                            identifier: "runtime.port-forwarding.row.\(index).public-port"
                        )
                        compactForwardingField(
                            title: FiliusLocalization.t("runtime.header.lanAddress"),
                            text: binding(index: index, keyPath: \.lanIPAddress),
                            valid: isValidIPv4(rows[index].lanIPAddress),
                            identifier: "runtime.port-forwarding.row.\(index).lan-address"
                        )
                        compactForwardingField(
                            title: FiliusLocalization.t("runtime.header.lanPort"),
                            text: binding(index: index, keyPath: \.lanPortValue),
                            valid: rows[index].runtimeLANPort != nil,
                            identifier: "runtime.port-forwarding.row.\(index).lan-port"
                        )
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        selectedRowIndex == index
                            ? Color.accentColor.opacity(0.18)
                            : Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("runtime.port-forwarding.row.\(index)")
                }
            }
            .padding(4)
        }
            .overlay(Rectangle().stroke(Color.gray.opacity(0.55), lineWidth: 1))
            forwardingActions
        }
    }

    private var forwardingActions: some View {
        HStack(spacing: 8) {
            Button(FiliusLocalization.t("ui.8955ab6bc1d4")) {
                rows.append(TopologyGatewayPortForwardingRow())
                selectedRowIndex = rows.indices.last
            }
            .accessibilityIdentifier("runtime.port-forwarding.add")
            Button(FiliusLocalization.t("ui.bcab7673e6e5")) {
                guard let selectedRowIndex, rows.indices.contains(selectedRowIndex) else { return }
                rows.remove(at: selectedRowIndex)
                self.selectedRowIndex = rows.indices.contains(selectedRowIndex)
                    ? selectedRowIndex
                    : rows.indices.last
            }
            .disabled(selectedRowIndex == nil)
            .accessibilityIdentifier("runtime.port-forwarding.delete")
        }
        .buttonStyle(.bordered)
    }

    private func forwardingTableRow(index: Int) -> some View {
        HStack(spacing: 0) {
            protocolCell(index: index)
            textCell(
                text: binding(index: index, keyPath: \.publicPortValue),
                valid: rows[index].runtimePublicPort != nil,
                width: columnWidths[1],
                identifier: "runtime.port-forwarding.row.\(index).public-port"
            )
            textCell(
                text: binding(index: index, keyPath: \.lanIPAddress),
                valid: isValidIPv4(rows[index].lanIPAddress),
                width: columnWidths[2],
                identifier: "runtime.port-forwarding.row.\(index).lan-address"
            )
            textCell(
                text: binding(index: index, keyPath: \.lanPortValue),
                valid: rows[index].runtimeLANPort != nil,
                width: columnWidths[3],
                identifier: "runtime.port-forwarding.row.\(index).lan-port"
            )
        }
        .frame(height: 30)
        .background(selectedRowIndex == index ? Color.accentColor.opacity(0.2) : Color.white)
        .contentShape(Rectangle())
        .onTapGesture { selectedRowIndex = index }
    }

    private func compactForwardingField(
        title: String,
        text: Binding<String>,
        valid: Bool,
        identifier: String
    ) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(valid ? Color.primary : Color.red)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(valid ? FiliusLocalization.t("runtime.validation.valid") : FiliusLocalization.t("runtime.validation.invalid"))
    }

    private func protocolCell(index: Int) -> some View {
        Picker("", selection: Binding(
            get: { rows[index].runtimeProtocol == .udp ? "UDP" : "TCP" },
            set: { rows[index].protocolValue = $0 }
        )) {
            Text(FiliusLocalization.t("ui.f544fb304c83")).tag("TCP")
            Text(FiliusLocalization.t("ui.e9a6f622e340")).tag("UDP")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(rows[index].runtimeProtocol == nil ? .red : .green)
        .frame(width: columnWidths[0], height: 30)
        .overlay(Rectangle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
        .accessibilityIdentifier("runtime.port-forwarding.row.\(index).protocol")
        .accessibilityValue(rows[index].runtimeProtocol == nil ? FiliusLocalization.t("runtime.validation.invalid") : FiliusLocalization.t("runtime.validation.valid"))
    }

    private func textCell(
        text: Binding<String>,
        valid: Bool,
        width: CGFloat,
        identifier: String
    ) -> some View {
        TextField("", text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.plain)
            .padding(.horizontal, 4)
            .foregroundStyle(valid ? Color.green : Color.red)
            .frame(width: width, height: 30)
            .overlay(Rectangle().stroke(valid ? Color.green.opacity(0.45) : Color.red, lineWidth: 0.75))
            .accessibilityIdentifier(identifier)
            .accessibilityValue(valid ? FiliusLocalization.t("runtime.validation.valid") : FiliusLocalization.t("runtime.validation.invalid"))
    }

    private func binding(
        index: Int,
        keyPath: WritableKeyPath<TopologyGatewayPortForwardingRow, String>
    ) -> Binding<String> {
        Binding(
            get: { rows[index][keyPath: keyPath] },
            set: { rows[index][keyPath: keyPath] = $0 }
        )
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .frame(width: width, height: 30, alignment: .leading)
            .padding(.horizontal, 4)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(Rectangle().stroke(Color.gray.opacity(0.45), lineWidth: 0.5))
    }

    private func isValidIPv4(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count == 4 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy(\.isNumber) && UInt8(String(segment)) != nil
        }
    }
}
private struct TopologyNATTableView: View {
    let mappings: [TopologyRuntimeNATMapping]
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let columnWidths: [CGFloat] = [90, 130, 160, 160, 130, 160]

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width) {
                    compactNATContent
                } else {
                    regularNATContent
                }
            }
            .padding(8)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(FiliusLocalization.t("ui.f0d184ae54b4"), action: onReset)
                        .accessibilityIdentifier("runtime.nat.table.reset")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(FiliusLocalization.t("ui.44424b18700e")) { dismiss() }
                        .accessibilityIdentifier("runtime.nat.table.close")
                }
            }
            .navigationTitle(FiliusLocalization.t("ui.cfb4277a48c0"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(minHeight: 240)
        .preferredColorScheme(.light)
        .accessibilityIdentifier("runtime.nat.table.viewer")
    }

    private var regularNATContent: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    headerCell(FiliusLocalization.t("runtime.header.protocol"), width: columnWidths[0])
                    headerCell(FiliusLocalization.t("runtime.header.portForwarding"), width: columnWidths[1])
                    headerCell(FiliusLocalization.t("runtime.header.wanAddress"), width: columnWidths[2])
                    headerCell(FiliusLocalization.t("runtime.header.lanAddress"), width: columnWidths[3])
                    headerCell(FiliusLocalization.t("runtime.header.lanPort"), width: columnWidths[4])
                    headerCell(FiliusLocalization.t("runtime.header.lastUpdated"), width: columnWidths[5])
                }
                ForEach(mappings) { mapping in
                    HStack(spacing: 0) {
                        valueCell(protocolLabel(mapping.protocolNumber), width: columnWidths[0])
                        valueCell(portLabel(mapping.translatedPortOrIdentifier, protocolNumber: mapping.protocolNumber), width: columnWidths[1])
                        valueCell(mapping.remoteIPAddress, width: columnWidths[2])
                        valueCell(mapping.lanIPAddress, width: columnWidths[3])
                        valueCell(portLabel(mapping.lanPortOrIdentifier, protocolNumber: mapping.protocolNumber), width: columnWidths[4])
                        valueCell(lastUpdateLabel(mapping), width: columnWidths[5])
                    }
                    .frame(height: 24)
                    .contextMenu {
                        Button(FiliusLocalization.t("ui.f0d184ae54b4"), action: onReset)
                    }
                }
            }
        }
        .background(Color.white)
        .overlay(Rectangle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
        .accessibilityIdentifier("runtime.nat.table.regular")
    }

    private var compactNATContent: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 8) {
                ForEach(mappings) { mapping in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(protocolLabel(mapping.protocolNumber))
                                .font(.headline)
                            Spacer()
                            Text(lastUpdateLabel(mapping))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        natDetail(
                            FiliusLocalization.t("runtime.header.portForwarding"),
                            portLabel(mapping.translatedPortOrIdentifier, protocolNumber: mapping.protocolNumber)
                        )
                        natDetail(FiliusLocalization.t("runtime.header.wanAddress"), mapping.remoteIPAddress)
                        natDetail(FiliusLocalization.t("runtime.header.lanAddress"), mapping.lanIPAddress)
                        natDetail(
                            FiliusLocalization.t("runtime.header.lanPort"),
                            portLabel(mapping.lanPortOrIdentifier, protocolNumber: mapping.protocolNumber)
                        )
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .contextMenu {
                        Button(FiliusLocalization.t("ui.f0d184ae54b4"), action: onReset)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("runtime.nat.mapping.\(mapping.id.uuidString)")
                }
                if mappings.isEmpty {
                    ContentUnavailableView(
                        FiliusLocalization.t("runtime.nat.empty.title"),
                        systemImage: "arrow.left.arrow.right",
                        description: Text(FiliusLocalization.t("runtime.nat.empty.description"))
                    )
                }
            }
            .padding(4)
        }
        .accessibilityIdentifier("runtime.nat.table.compact")
    }

    private func natDetail(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.caption.monospacedDigit())
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .frame(width: width, height: 28, alignment: .leading)
            .padding(.horizontal, 4)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5))
    }

    private func valueCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .frame(width: width, height: 24, alignment: .leading)
            .padding(.horizontal, 4)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.25), lineWidth: 0.5))
    }

    private func protocolLabel(_ protocolNumber: TopologyIPv4Protocol) -> String {
        switch protocolNumber {
        case .tcp: return "TCP"
        case .udp: return "UDP"
        case .icmp: return "ICMP"
        }
    }

    private func portLabel(_ port: UInt16, protocolNumber: TopologyIPv4Protocol) -> String {
        protocolNumber == .icmp ? "0 (Identifier: \(port))" : String(port)
    }

    private func lastUpdateLabel(_ mapping: TopologyRuntimeNATMapping) -> String {
        guard mapping.type != .staticEntry else { return "-" }
        let seconds = (mapping.updatedAtMilliseconds / 1_000) % 86_400
        return String(
            format: "%02llu:%02llu:%02llu",
            seconds / 3_600,
            (seconds / 60) % 60,
            seconds % 60
        )
    }
}
private struct TopologyFirewallConfigurationView: View {
    @Environment(\.dismiss) private var dismiss

    let originalConfiguration: TopologyFirewallConfiguration
    let onSave: (TopologyFirewallConfiguration) -> Void

    @State private var selectedTab = 0
    @State private var isActive: Bool
    @State private var defaultPolicy: TopologyFirewallAction
    @State private var dropICMP: Bool
    @State private var filterSYNSegmentsOnly: Bool
    @State private var filterUDP: Bool
    @State private var rules: [TopologyFirewallRuleDraft]
    @State private var selectedRuleIndex: Int?

    init(
        configuration: TopologyFirewallConfiguration,
        onSave: @escaping (TopologyFirewallConfiguration) -> Void
    ) {
        originalConfiguration = configuration
        self.onSave = onSave
        _isActive = State(initialValue: configuration.isActive)
        _defaultPolicy = State(initialValue: configuration.defaultPolicy)
        _dropICMP = State(initialValue: configuration.dropICMP)
        _filterSYNSegmentsOnly = State(initialValue: configuration.filterSYNSegmentsOnly)
        _filterUDP = State(initialValue: configuration.filterUDP)
        _rules = State(initialValue: configuration.rules.map { TopologyFirewallRuleDraft(rule: $0) })
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 10) {
                    Picker(FiliusLocalization.t("ui.7a3ac9a3d52d"), selection: $selectedTab) {
                        Text(FiliusLocalization.t("ui.21a7b4ecae6d")).tag(0)
                        Text(FiliusLocalization.t("ui.740fb09eb641")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("runtime.firewall.tabs")

                    if selectedTab == 0 {
                        generalSettings
                    } else if TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width) {
                        compactRuleSettings
                    } else {
                        ruleSettings
                    }
                }
                .padding(10)
            }
            .navigationTitle(FiliusLocalization.t("ui.574f7fc12c95"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FiliusLocalization.t("ui.07af7cb30fca")) { dismiss() }
                        .accessibilityIdentifier("runtime.firewall.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(FiliusLocalization.t("ui.9ce3bd4224c8")) {
                        save()
                        dismiss()
                    }
                    .accessibilityIdentifier("runtime.firewall.ok")
                }
            }
        }
        .frame(minHeight: 500)
        .preferredColorScheme(.light)
        .accessibilityIdentifier("runtime.firewall.dialog")
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                firewallToggle(
                    title: FiliusLocalization.t("runtime.firewall.active.title"),
                    explanation: FiliusLocalization.t("runtime.firewall.active.explanation"),
                    isOn: $isActive,
                    identifier: "runtime.firewall.active"
                )
                firewallToggle(
                    title: FiliusLocalization.t("runtime.firewall.icmp.title"),
                    explanation: FiliusLocalization.t("runtime.firewall.icmp.explanation"),
                    isOn: $dropICMP,
                    identifier: "runtime.firewall.dropICMP"
                )
                firewallToggle(
                    title: FiliusLocalization.t("runtime.firewall.syn.title"),
                    explanation: FiliusLocalization.t("runtime.firewall.syn.explanation"),
                    isOn: $filterSYNSegmentsOnly,
                    identifier: "runtime.firewall.synOnly"
                )
                Toggle(FiliusLocalization.t("ui.770f0631f0e6"), isOn: $filterUDP)
                    .accessibilityIdentifier("runtime.firewall.filterUDP")
            }
            .padding(10)
        }
    }

    private var compactRuleSettings: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                Text(FiliusLocalization.t("ui.f76f012cfe1a"))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(FiliusLocalization.t("ui.697a489744b8"), selection: $defaultPolicy) {
                    Text(TopologyFirewallAction.accept.javaLabel).tag(TopologyFirewallAction.accept)
                    Text(TopologyFirewallAction.drop.javaLabel).tag(TopologyFirewallAction.drop)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("runtime.firewall.defaultPolicy")
                ForEach(Array(rules.indices), id: \.self) { index in
                    compactFirewallRuleCard(index: index)
                }
                compactRuleActions
            }
        }
        .accessibilityIdentifier("runtime.firewall.compactRules")
    }

    private func compactFirewallRuleCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                selectedRuleIndex = index
            } label: {
                HStack {
                    Text(FiliusLocalization.t("runtime.firewall.id") + " \(index + 1)")
                        .font(.headline)
                    Spacer()
                    Image(systemName: selectedRuleIndex == index
                        ? "checkmark.circle.fill"
                        : "circle")
                        .foregroundStyle(selectedRuleIndex == index ? Color.accentColor : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedRuleIndex == index ? .isSelected : [])
            .accessibilityIdentifier("runtime.firewall.compactRule.\(index).select")
            compactFirewallField(FiliusLocalization.t("runtime.firewall.sourceIP"), text: $rules[index].sourceIPAddress, valid: sourceIPValid(rules[index]))
            compactFirewallField(FiliusLocalization.t("runtime.firewall.subnetMask"), text: $rules[index].sourceSubnetMask, valid: maskValid(rules[index].sourceSubnetMask))
            compactFirewallField(FiliusLocalization.t("runtime.firewall.destinationIP"), text: $rules[index].destinationIPAddress, valid: destinationIPValid(rules[index]))
            compactFirewallField(FiliusLocalization.t("runtime.firewall.subnetMask"), text: $rules[index].destinationSubnetMask, valid: maskValid(rules[index].destinationSubnetMask))
            Picker(FiliusLocalization.t("ui.440c156b2409"), selection: $rules[index].protocolType) {
                ForEach(TopologyFirewallProtocol.allCases, id: \.rawValue) { protocolType in
                    Text(protocolType.javaLabel).tag(protocolType)
                }
            }
            .accessibilityIdentifier("runtime.firewall.rule.\(index).protocol")
            compactFirewallField(FiliusLocalization.t("runtime.field.port"), text: $rules[index].port, valid: portValid(rules[index].port))
            Picker(FiliusLocalization.t("ui.276e2316b951"), selection: $rules[index].action) {
                Text(TopologyFirewallAction.accept.javaLabel).tag(TopologyFirewallAction.accept)
                Text(TopologyFirewallAction.drop.javaLabel).tag(TopologyFirewallAction.drop)
            }
            .accessibilityIdentifier("runtime.firewall.rule.\(index).action")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selectedRuleIndex == index
                ? Color.accentColor.opacity(0.18)
                : Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runtime.firewall.compactRule.\(index)")
    }

    private var compactRuleActions: some View {
        HStack(spacing: 8) {
            Button(FiliusLocalization.t("ui.b6fc7490a035"), action: moveSelectedRuleUp)
                .disabled(selectedRuleIndex == nil || selectedRuleIndex == 0)
            Button(FiliusLocalization.t("ui.81b9787bb8ea"), action: moveSelectedRuleDown)
                .disabled(selectedRuleIndex == nil || selectedRuleIndex == rules.indices.last)
            Button(FiliusLocalization.t("ui.62315e248ca5")) {
                rules.append(TopologyFirewallRuleDraft())
                selectedRuleIndex = rules.count - 1
            }
            .accessibilityIdentifier("runtime.firewall.rule.add")
            Button(FiliusLocalization.t("ui.25d28b7485ab")) {
                guard let selectedRuleIndex, rules.indices.contains(selectedRuleIndex) else { return }
                rules.remove(at: selectedRuleIndex)
                self.selectedRuleIndex = rules.isEmpty ? nil : min(selectedRuleIndex, rules.count - 1)
            }
            .disabled(selectedRuleIndex == nil)
            .accessibilityIdentifier("runtime.firewall.rule.delete")
        }
        .buttonStyle(.bordered)
        .font(.caption)
    }

    private func compactFirewallField(_ title: String, text: Binding<String>, valid: Bool) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.numbersAndPunctuation)
            .foregroundStyle(valid ? Color.primary : Color.red)
            .accessibilityValue(
                valid
                    ? FiliusLocalization.t("runtime.validation.valid")
                    : FiliusLocalization.t("runtime.validation.invalid")
            )
    }

    private var ruleSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(FiliusLocalization.t("ui.f76f012cfe1a"))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(FiliusLocalization.t("ui.697a489744b8"))
                Picker(FiliusLocalization.t("ui.64cbec25518b"), selection: $defaultPolicy) {
                    Text(TopologyFirewallAction.accept.javaLabel).tag(TopologyFirewallAction.accept)
                    Text(TopologyFirewallAction.drop.javaLabel).tag(TopologyFirewallAction.drop)
                }
                .labelsHidden()
                .frame(width: 140)
                Spacer()
            }

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    firewallHeaderRow
                    ForEach(Array(rules.indices), id: \.self) { index in
                        firewallRuleRow(index: index)
                    }
                }
                .frame(minWidth: 790, alignment: .leading)
            }
            .frame(minHeight: 300)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.55), lineWidth: 1))

            HStack(spacing: 10) {
                Button(FiliusLocalization.t("ui.b6fc7490a035"), action: moveSelectedRuleUp)
                    .disabled(selectedRuleIndex == nil || selectedRuleIndex == 0)
                    .accessibilityIdentifier("runtime.firewall.rule.up")
                Button(FiliusLocalization.t("ui.81b9787bb8ea"), action: moveSelectedRuleDown)
                    .disabled(selectedRuleIndex == nil || selectedRuleIndex == rules.indices.last)
                    .accessibilityIdentifier("runtime.firewall.rule.down")
                Spacer().frame(width: 20)
                Button(FiliusLocalization.t("ui.62315e248ca5")) {
                    rules.append(TopologyFirewallRuleDraft())
                    selectedRuleIndex = rules.count - 1
                }
                .accessibilityIdentifier("runtime.firewall.rule.add")
                Button(FiliusLocalization.t("ui.25d28b7485ab")) {
                    guard let selectedRuleIndex, rules.indices.contains(selectedRuleIndex) else { return }
                    rules.remove(at: selectedRuleIndex)
                    self.selectedRuleIndex = rules.isEmpty ? nil : min(selectedRuleIndex, rules.count - 1)
                }
                .disabled(selectedRuleIndex == nil)
                .accessibilityIdentifier("runtime.firewall.rule.delete")
            }
        }
    }

    // Java UI anchors retained for the parity contract: Firewall-Regeln; Firewall aktivieren; ICMP-Pakete filtern; nur SYN-Pakete verwerfen; "DHCP zur Konfiguration verwenden"; "Automatisches Routing"; TextField("Default gateway", text: $defaultGateway).
    private var firewallHeaderRow: some View {
        HStack(spacing: 0) {
            firewallHeader(FiliusLocalization.t("runtime.firewall.id"), width: 30)
            firewallHeader(FiliusLocalization.t("runtime.firewall.sourceIP"), width: 130)
            firewallHeader(FiliusLocalization.t("runtime.firewall.subnetMask"), width: 130)
            firewallHeader(FiliusLocalization.t("runtime.firewall.destinationIP"), width: 130)
            firewallHeader(FiliusLocalization.t("runtime.firewall.subnetMask"), width: 130)
            firewallHeader(FiliusLocalization.t("runtime.header.protocol"), width: 80)
            firewallHeader(FiliusLocalization.t("runtime.field.port"), width: 60)
            firewallHeader(FiliusLocalization.t("runtime.firewall.action"), width: 80)
        }
        .frame(height: 30)
        .background(Color(white: 0.86))
    }

    private func firewallRuleRow(index: Int) -> some View {
        HStack(spacing: 0) {
            Text(String(index + 1))
                .frame(width: 30, height: 30)
            firewallTextField($rules[index].sourceIPAddress, width: 130, valid: sourceIPValid(rules[index]))
            firewallTextField($rules[index].sourceSubnetMask, width: 130, valid: maskValid(rules[index].sourceSubnetMask))
            firewallTextField($rules[index].destinationIPAddress, width: 130, valid: destinationIPValid(rules[index]))
            firewallTextField($rules[index].destinationSubnetMask, width: 130, valid: maskValid(rules[index].destinationSubnetMask))
            Picker(FiliusLocalization.t("ui.440c156b2409"), selection: $rules[index].protocolType) {
                ForEach(TopologyFirewallProtocol.allCases, id: \.rawValue) { protocolType in
                    Text(protocolType.javaLabel).tag(protocolType)
                }
            }
            .labelsHidden()
            .frame(width: 80, height: 30)
            firewallTextField($rules[index].port, width: 60, valid: portValid(rules[index].port))
            Picker(FiliusLocalization.t("ui.276e2316b951"), selection: $rules[index].action) {
                Text(TopologyFirewallAction.accept.javaLabel).tag(TopologyFirewallAction.accept)
                Text(TopologyFirewallAction.drop.javaLabel).tag(TopologyFirewallAction.drop)
            }
            .labelsHidden()
            .frame(width: 80, height: 30)
        }
        .frame(height: 30)
        .background(selectedRuleIndex == index ? Color.accentColor.opacity(0.18) : Color.white)
        .contentShape(Rectangle())
        .onTapGesture { selectedRuleIndex = index }
        .accessibilityIdentifier("runtime.firewall.rule.\(index)")
    }

    private func firewallToggle(
        title: String,
        explanation: String,
        isOn: Binding<Bool>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: isOn)
                .accessibilityIdentifier(identifier)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            Divider()
        }
    }

    private func firewallHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .frame(width: width, height: 30)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.45), lineWidth: 0.5))
    }

    private func firewallTextField(_ text: Binding<String>, width: CGFloat, valid: Bool) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 3)
            .frame(width: width, height: 30)
            .background(valid ? Color.green.opacity(0.12) : Color.red.opacity(0.18))
            .overlay(Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5))
    }

    private func moveSelectedRuleUp() {
        guard let selectedRuleIndex, selectedRuleIndex > 0 else { return }
        rules.swapAt(selectedRuleIndex, selectedRuleIndex - 1)
        self.selectedRuleIndex = selectedRuleIndex - 1
    }

    private func moveSelectedRuleDown() {
        guard let selectedRuleIndex, selectedRuleIndex + 1 < rules.count else { return }
        rules.swapAt(selectedRuleIndex, selectedRuleIndex + 1)
        self.selectedRuleIndex = selectedRuleIndex + 1
    }

    private func save() {
        let persistedRules = rules.map { draft in
            normalizedRule(draft) ?? draft.originalRule
        }
        onSave(TopologyFirewallConfiguration(
            isActive: isActive,
            defaultPolicy: defaultPolicy,
            dropICMP: dropICMP,
            filterSYNSegmentsOnly: filterSYNSegmentsOnly,
            filterUDP: filterUDP,
            rules: persistedRules
        ))
    }

    private func normalizedRule(_ draft: TopologyFirewallRuleDraft) -> TopologyFirewallRule? {
        guard sourceIPValid(draft), destinationIPValid(draft),
              maskValid(draft.sourceSubnetMask), maskValid(draft.destinationSubnetMask),
              portValid(draft.port) else { return nil }
        let source = draft.sourceIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = draft.destinationIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceMask = draft.sourceSubnetMask.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationMask = draft.destinationSubnetMask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source == TopologyFirewallRule.directlyConnectedSourceMarker || source.isEmpty || !sourceMask.isEmpty,
              destination.isEmpty || !destinationMask.isEmpty else { return nil }
        let port = draft.port == "*" || draft.port.isEmpty
            ? TopologyFirewallRule.allPorts : Int(draft.port) ?? -2
        return TopologyFirewallRule(
            sourceIPAddress: source,
            sourceSubnetMask: sourceMask,
            destinationIPAddress: destination,
            destinationSubnetMask: destinationMask,
            port: port,
            protocolType: draft.protocolType,
            action: draft.action
        )
    }

    private func sourceIPValid(_ draft: TopologyFirewallRuleDraft) -> Bool {
        let value = draft.sourceIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value == TopologyFirewallRule.directlyConnectedSourceMarker || isValidIPv4(value)
    }

    private func destinationIPValid(_ draft: TopologyFirewallRuleDraft) -> Bool {
        let value = draft.destinationIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || isValidIPv4(value)
    }

    private func maskValid(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        guard isValidIPv4(value) else { return false }
        let octets = value.split(separator: ".").compactMap { UInt8($0) }
        let mask = octets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let inverted = ~mask
        return (inverted & (inverted &+ 1)) == 0
    }

    private func portValid(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "*" { return true }
        guard let port = Int(value) else { return false }
        return (1...65_535).contains(port)
    }

    private func isValidIPv4(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count == 4 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy(\.isNumber) && UInt8(String(segment)) != nil
        }
    }
}

private extension TopologyRuntimeInstallableProgram {
    var desktopName: String {
        switch self {
        case .commandPrompt:
            return FiliusLocalization.t("runtime.app.cmd")
        case .fileExplorer:
            return FiliusLocalization.t("runtime.app.fileExplorer")
        case .imageViewer:
            return FiliusLocalization.t("runtime.app.imageViewer")
        case .textEditor:
            return FiliusLocalization.t("runtime.app.textEditor")
        case .webServer:
            return FiliusLocalization.t("runtime.app.webServer")
        case .webBrowser:
            return FiliusLocalization.t("runtime.app.webBrowser")
        case .echoServer:
            return FiliusLocalization.t("runtime.app.echoServer")
        case .simpleClient:
            return FiliusLocalization.t("runtime.app.simpleClient")
        case .dnsServer:
            return FiliusLocalization.t("runtime.app.dnsServer")
        case .dhcpServer:
            return FiliusLocalization.t("runtime.app.dhcpServer")
        case .firewall:
            return FiliusLocalization.t("runtime.app.firewall")
        case .emailClient:
            return FiliusLocalization.t("runtime.app.emailClient")
        case .emailServer:
            return FiliusLocalization.t("runtime.app.emailServer")
        case .gnutella:
            return FiliusLocalization.t("runtime.app.gnutella")
        }
    }

    var desktopDescription: String {
        switch self {
        case .commandPrompt:
            return FiliusLocalization.t("runtime.app.cmd.description")
        case .fileExplorer:
            return FiliusLocalization.t("runtime.app.fileExplorer.description")
        case .imageViewer:
            return FiliusLocalization.t("runtime.app.imageViewer.description")
        case .textEditor:
            return FiliusLocalization.t("runtime.app.textEditor.description")
        case .webServer:
            return FiliusLocalization.t("runtime.app.webServer.description")
        case .webBrowser:
            return FiliusLocalization.t("runtime.app.webBrowser.description")
        case .echoServer:
            return FiliusLocalization.t("runtime.app.echoServer.description")
        case .simpleClient:
            return FiliusLocalization.t("runtime.app.simpleClient.description")
        case .dnsServer:
            return FiliusLocalization.t("runtime.app.dnsServer.description")
        case .dhcpServer:
            return FiliusLocalization.t("runtime.app.dhcpServer.description")
        case .firewall:
            return FiliusLocalization.t("runtime.app.firewall.description")
        case .emailClient:
            return FiliusLocalization.t("runtime.app.emailClient.description")
        case .emailServer:
            return FiliusLocalization.t("runtime.app.emailServer.description")
        case .gnutella:
            return FiliusLocalization.t("runtime.app.gnutella.description")
        }
    }

    var desktopIconRelativePath: String {
        switch self {
        case .commandPrompt:
            return "desktop/icon_terminal.png"
        case .fileExplorer:
            return "desktop/icon_filebrowser.png"
        case .imageViewer:
            return "desktop/icon_imageviewer.png"
        case .textEditor:
            return "desktop/icon_texteditor.png"
        case .webServer:
            return "desktop/icon_webserver.png"
        case .webBrowser:
            return "desktop/icon_browser.png"
        case .echoServer:
            return "desktop/icon_serverbaustein.png"
        case .simpleClient:
            return "desktop/icon_clientbaustein.png"
        case .dnsServer:
            return "desktop/icon_dns.png"
        case .dhcpServer:
            return "desktop/icon_serverbaustein.png"
        case .firewall:
            return "desktop/icon_firewall.png"
        case .emailClient:
            return "desktop/icon_emailprogramm.png"
        case .emailServer:
            return "desktop/icon_emailserver.png"
        case .gnutella:
            return "desktop/icon_peertopeer.png"
        }
    }

    var fallbackSystemImage: String {
        switch self {
        case .commandPrompt:
            return "terminal"
        case .fileExplorer:
            return "folder"
        case .imageViewer:
            return "photo"
        case .textEditor:
            return "text.alignleft"
        case .webServer:
            return "network"
        case .webBrowser:
            return "safari"
        case .echoServer:
            return "dot.radiowaves.left.and.right"
        case .simpleClient:
            return "arrow.left.arrow.right.circle"
        case .dnsServer:
            return "globe"
        case .dhcpServer:
            return "server.rack"
        case .firewall:
            return "shield"
        case .emailClient:
            return "envelope"
        case .emailServer:
            return "mail.stack"
        case .gnutella:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}


// MARK: - Java packet, message, and layer-path viewers

private struct TopologyPresentedLayerPath: Identifiable {
    let id = UUID()
    let title: String
    let path: TopologyPacketLayerPath
}

private struct TopologyPacketExchangeDestination: View {
    let tabs: [TopologyPacketCaptureTab]
    let rows: [TopologyPacketMessageRow]
    let packetLayerPath: (TopologyPacketCaptureIdentity, Bool) -> TopologyPacketLayerPath
    let onReset: () -> Void
    let onExport: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TopologyLayeredExchangeWindow(
            tabs: tabs,
            rows: rows,
            packetLayerPath: packetLayerPath,
            onReset: onReset,
            onExport: onExport,
            onClose: { dismiss() }
        )
        .padding(16)
        .background(FiliusExperienceTokens.runtimeWindowSurface)
        .navigationBarBackButtonHidden()
        .accessibilityIdentifier("runtime.packet-exchange.destination")
    }
}

enum TopologyDenseLayoutPolicy {
    static func usesCompactPresentation(width: CGFloat) -> Bool {
        width < 760
    }
}

private struct TopologyLayeredExchangeWindow: View {
    let tabs: [TopologyPacketCaptureTab]
    let rows: [TopologyPacketMessageRow]
    let packetLayerPath: (TopologyPacketCaptureIdentity, Bool) -> TopologyPacketLayerPath
    let onReset: () -> Void
    let onExport: (UUID?) -> Void
    let onClose: () -> Void

    @State private var selectedInterfaceID: UUID?
    @State private var selectedRowID: UInt64?
    @State private var showsNetworkAccess = true
    @State private var showsNetwork = true
    @State private var showsTransport = true
    @State private var showsApplication = true
    @State private var autoscroll = true
    @State private var presentedLayerPath: TopologyPresentedLayerPath?

    init(
        tabs: [TopologyPacketCaptureTab],
        rows: [TopologyPacketMessageRow],
        packetLayerPath: @escaping (TopologyPacketCaptureIdentity, Bool) -> TopologyPacketLayerPath,
        onReset: @escaping () -> Void,
        onExport: @escaping (UUID?) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.tabs = tabs
        self.rows = rows
        self.packetLayerPath = packetLayerPath
        self.onReset = onReset
        self.onExport = onExport
        self.onClose = onClose
        _selectedInterfaceID = State(initialValue: tabs.first?.interfaceID)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width)
            VStack(spacing: 0) {
                packetToolbar(compact: compact)

                if tabs.isEmpty {
                    ContentUnavailableView(
                        FiliusLocalization.t("packet.exchange.empty"),
                        systemImage: "network.slash",
                        description: Text(FiliusLocalization.t("ui.8b89cad34fa9"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.2))
                } else {
                    tabStrip
                    if compact {
                        VStack(spacing: 0) {
                            compactMessageList
                            Divider()
                            messageDetails
                                .frame(maxHeight: 240)
                        }
                    } else {
                        HStack(spacing: 0) {
                            messageTable
                            Divider()
                            messageDetails
                                .frame(width: 290)
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.black.opacity(0.55), lineWidth: 1)
        }
        .shadow(radius: 8, y: 3)
        .accessibilityIdentifier("runtime.packet-exchange.window")
        .sheet(item: $presentedLayerPath) { presentation in
            TopologyLayerPathView(title: presentation.title, path: presentation.path)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: tabs.map(\.interfaceID)) { _, interfaceIDs in
            if selectedInterfaceID == nil || !interfaceIDs.contains(selectedInterfaceID!) {
                selectedInterfaceID = interfaceIDs.first
                selectedRowID = nil
            }
        }
    }

    @ViewBuilder
    private func packetToolbar(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(FiliusLocalization.t("ui.69c4593fb91f"))
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(FiliusLocalization.t("ui.44424b18700e"))
                        .accessibilityIdentifier("runtime.packet-exchange.close")
                }
                HStack(spacing: 8) {
                    layerMenu
                    Toggle(FiliusLocalization.t("ui.76b972ba949f"), isOn: $autoscroll)
                        .font(.caption)
                        .accessibilityIdentifier("runtime.packet-exchange.autoscroll")
                    Spacer()
                    exportButton
                    resetButton
                }
            }
            .padding(8)
            .background(Color(uiColor: .systemBackground))
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("runtime.packet-exchange.compact-toolbar")
            }
        } else {
            HStack(spacing: 8) {
                Text(FiliusLocalization.t("ui.69c4593fb91f"))
                    .font(.headline)
                Spacer()
                layerMenu
                Toggle(FiliusLocalization.t("ui.76b972ba949f"), isOn: $autoscroll)
                    .font(.caption)
                    .accessibilityIdentifier("runtime.packet-exchange.autoscroll")
                exportButton
                resetButton
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(FiliusLocalization.t("ui.44424b18700e"))
                    .accessibilityIdentifier("runtime.packet-exchange.close")
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private var exportButton: some View {
        Button {
            onExport(selectedInterfaceID)
        } label: {
            Label(FiliusLocalization.t("packet.export.action"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
        .disabled(tabs.isEmpty)
        .accessibilityIdentifier("runtime.packet-exchange.export")
    }

    private var resetButton: some View {
        Button(FiliusLocalization.t("ui.14c51ded6297")) {
            selectedRowID = nil
            onReset()
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("runtime.packet-exchange.reset")
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    Button {
                        selectedInterfaceID = tab.interfaceID
                        selectedRowID = nil
                    } label: {
                        HStack(spacing: 5) {
                            Text(tab.title)
                            Text(FiliusLocalization.t("runtime.eventCount", tab.eventCount))
                                .font(.caption2.monospacedDigit())
                                .padding(.horizontal, 5)
                                .background(Color.black.opacity(0.12), in: Capsule())
                        }
                        .font(.caption.weight(selectedInterfaceID == tab.interfaceID ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(selectedInterfaceID == tab.interfaceID ? Color.white : Color(white: 0.82))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("runtime.packet-exchange.tab.\(tab.interfaceID.uuidString)")
                }
            }
        }
        .background(Color(white: 0.72))
        .frame(height: 30)
    }

    private var layerMenu: some View {
        Menu(FiliusLocalization.t("ui.1d9fe9b27d57")) {
            Toggle(FiliusLocalization.t("ui.ea9143ca7b0a"), isOn: $showsNetworkAccess)
            Toggle(FiliusLocalization.t("ui.c67e016dd31c"), isOn: $showsNetwork)
            Toggle(FiliusLocalization.t("ui.59666d91bfaa"), isOn: $showsTransport)
            Toggle(FiliusLocalization.t("ui.b5df59c2ea42"), isOn: $showsApplication)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("runtime.packet-exchange.layer-filter")
    }

    private var selectedRows: [TopologyPacketMessageRow] {
        rows.filter { row in
            guard row.trace.interfaceID == selectedInterfaceID else { return false }
            switch row.trace.layer {
            case .physical, .dataLink: return showsNetworkAccess
            case .network: return showsNetwork
            case .transport: return showsTransport
            case .application: return showsApplication
            }
        }
    }

    private var selectedRow: TopologyPacketMessageRow? {
        selectedRows.first(where: { $0.id == selectedRowID })
    }

    private var messageTable: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(selectedRows) { row in
                            Button {
                                selectedRowID = row.id
                            } label: {
                                packetRow(row)
                            }
                            .buttonStyle(.plain)
                            .id(row.id)
                            .accessibilityIdentifier("runtime.packet-exchange.row.\(row.id)")
                        }
                    } header: {
                        packetHeader
                    }
                }
            }
            .background(Color(uiColor: .darkGray))
            .onChange(of: selectedRows.count) {
                guard autoscroll, let lastID = selectedRows.last?.id else { return }
                withAnimation(.none) { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
        .accessibilityIdentifier("runtime.packet-exchange.table")
    }

    private var compactMessageList: some View {
        ScrollViewReader { proxy in
            List(selectedRows) { row in
                Button {
                    selectedRowID = row.id
                } label: {
                    compactPacketRow(row)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                .listRowBackground(
                    selectedRowID == row.id
                        ? Color.yellow.opacity(0.35)
                        : TopologyPacketViewerColors.colors(for: row.trace.layer).background
                )
                .id(row.id)
                .accessibilityIdentifier("runtime.packet-exchange.compact-row.\(row.id)")
            }
            .listStyle(.plain)
            .onChange(of: selectedRows.count) {
                guard autoscroll, let lastID = selectedRows.last?.id else { return }
                withAnimation(.none) { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("runtime.packet-exchange.compact-list")
        }
    }

    private func compactPacketRow(_ row: TopologyPacketMessageRow) -> some View {
        let colors = TopologyPacketViewerColors.colors(for: row.trace.layer)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(FiliusLocalization.t("runtime.rowNumber", String(row.number)))
                    .font(.caption.monospacedDigit())
                Text(TopologyPacketViewerFormatting.time(row.timeMilliseconds))
                    .font(.caption.monospacedDigit())
                Spacer()
                Label(row.protocolName, systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.foreground)
            }
            Text("\(row.source) → \(row.destination)")
                .font(.subheadline.monospaced())
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline) {
                Text(row.layerName)
                    .font(.caption.weight(.semibold))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var packetHeader: some View {
        HStack(spacing: 0) {
            packetCell(FiliusLocalization.t("packet.column.number"), width: 40, header: true)
            packetCell(FiliusLocalization.t("packet.column.time"), width: 120, header: true)
            packetCell(FiliusLocalization.t("packet.column.source"), width: 180, header: true)
            packetCell(FiliusLocalization.t("packet.column.destination"), width: 180, header: true)
            packetCell(FiliusLocalization.t("packet.column.protocol"), width: 100, header: true)
            packetCell(FiliusLocalization.t("packet.column.layer"), width: 140, header: true)
            packetCell(FiliusLocalization.t("packet.column.details"), width: 500, header: true)
        }
        .background(Color(white: 0.86))
    }

    private func packetRow(_ row: TopologyPacketMessageRow) -> some View {
        let colors = TopologyPacketViewerColors.colors(for: row.trace.layer)
        return HStack(spacing: 0) {
            packetCell(String(row.number), width: 40)
            packetCell(TopologyPacketViewerFormatting.time(row.timeMilliseconds), width: 120)
            packetCell(row.source, width: 180)
            packetCell(row.destination, width: 180)
            packetCell(row.protocolName, width: 100)
            packetCell(row.layerName, width: 140)
            packetCell(row.detail, width: 500)
        }
        .foregroundStyle(colors.foreground)
        .background(selectedRowID == row.id ? Color.yellow.opacity(0.65) : colors.background)
        .frame(height: 25)
    }

    private func packetCell(_ value: String, width: CGFloat, header: Bool = false) -> some View {
        Text(value)
            .font(header ? .caption.weight(.semibold) : .caption.monospaced())
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .frame(width: width, height: header ? 25 : 20, alignment: .leading)
    }

    @ViewBuilder
    private var messageDetails: some View {
        if let row = selectedRow {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(FiliusLocalization.t("ui.9b360268f1d2"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(FiliusLocalization.t("runtime.rowNumber", String(row.number)))
                        .font(.caption.monospacedDigit())
                }
                headerDetails(title: FiliusLocalization.t("packet.headers.before"), fields: row.trace.beforeHeaders)
                headerDetails(
                    title: row.trace.beforeHeaders == row.trace.afterHeaders
                        ? FiliusLocalization.t("packet.headers.header")
                        : FiliusLocalization.t("packet.headers.after"),
                    fields: row.trace.afterHeaders
                )
                Text(FiliusLocalization.t("ui.df82b8ebf9db"))
                    .font(.caption.weight(.semibold))
                Text(row.trace.detail ?? "-")
                    .font(.caption.monospaced())
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack {
                    Button(FiliusLocalization.t("ui.6cfac5f97b7c")) {
                        presentedLayerPath = TopologyPresentedLayerPath(
                            title: FiliusLocalization.t("packet.path.local"),
                            path: packetLayerPath(row.exchangeIdentity, true)
                        )
                    }
                    Button(FiliusLocalization.t("ui.9a6d6e3c67ed")) {
                        presentedLayerPath = TopologyPresentedLayerPath(
                            title: FiliusLocalization.t("packet.path.visualization"),
                            path: packetLayerPath(row.exchangeIdentity, false)
                        )
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
            .padding(8)
            .background(TopologyPacketViewerColors.colors(for: row.trace.layer).background.opacity(0.82))
            .accessibilityIdentifier("runtime.packet-exchange.details")
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.click.2")
                Text(FiliusLocalization.t("ui.d3dd5097b1a1"))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private func headerDetails(title: String, fields: [TopologyPacketHeaderField]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            if fields.isEmpty {
                Text(FiliusLocalization.t("ui.fallback.none"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(fields.map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .lineLimit(4)
            }
        }
    }
}

private struct TopologyLayerPathView: View {
    let title: String
    let path: TopologyPacketLayerPath
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStepID: UInt64?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    layerLegend(compact: TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width))
                    if TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width) {
                        compactPathList
                    } else {
                        regularPathList
                    }
                    if let selected = path.steps.first(where: { $0.id == selectedStepID }) {
                        let compact = TopologyDenseLayoutPolicy.usesCompactPresentation(width: proxy.size.width)
                        layerPathDetails(selected, compact: compact)
                            .frame(maxHeight: compact ? 240 : 150)
                    }
                }
                .background(Color(white: 0.93))
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(FiliusLocalization.t("ui.44424b18700e")) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("runtime.layer-path.dialog")
    }

    private var regularPathList: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 6) {
                ForEach(path.steps) { step in
                    Button {
                        selectedStepID = step.id
                    } label: {
                        pathStep(step)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedStepID == step.id ? .isSelected : [])
                    .accessibilityIdentifier("runtime.layer-path.step.\(step.id)")
                }
            }
            .padding(10)
        }
    }

    private var compactPathList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 8) {
                ForEach(path.steps) { step in
                    Button {
                        selectedStepID = step.id
                    } label: {
                        compactPathStep(step)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedStepID == step.id ? .isSelected : [])
                    .accessibilityIdentifier("runtime.layer-path.step.\(step.id)")
                }
            }
            .padding(10)
        }
    }

    private func layerLegend(compact: Bool) -> some View {
        Group {
            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    legendContent
                        .padding(.horizontal, 10)
                }
            } else {
                legendContent
            }
        }
        .padding(.top, 8)
    }

    private var legendContent: some View {
        HStack(spacing: 8) {
            Text(FiliusLocalization.t("ui.7cb2ae1e5c3e"))
                .font(.caption.weight(.semibold))
            ForEach(TopologyPacketTraceLayer.viewerLayers, id: \.rawValue) { layer in
                Text(TopologyPacketViewerFormatting.layerName(layer))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(TopologyPacketViewerColors.colors(for: layer).background)
                    .foregroundStyle(TopologyPacketViewerColors.colors(for: layer).foreground)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private func compactPathStep(_ step: TopologyPacketLayerPathStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(step.ordinal))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.nodeName)
                        .font(.caption.weight(.semibold))
                    Text(step.interfaceName ?? FiliusLocalization.t("ui.fallback.none"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(TopologyPacketViewerFormatting.layerName(step.layer))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TopologyPacketViewerColors.colors(for: step.layer).background)
                    .foregroundStyle(TopologyPacketViewerColors.colors(for: step.layer).foreground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(TopologyPacketViewerFormatting.operationName(step.operation))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.monospaced())
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedStepID == step.id ? Color.yellow.opacity(0.4) : Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedStepID == step.id ? Color.accentColor : Color.clear, lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if step.beforeHeaders != step.afterHeaders && !step.beforeHeaders.isEmpty && !step.afterHeaders.isEmpty {
                Rectangle().fill(Color.orange).frame(height: 2)
            }
        }
    }

    private func pathStep(_ step: TopologyPacketLayerPathStep) -> some View {
        HStack(spacing: 6) {
            Text(String(step.ordinal))
                .font(.caption.monospacedDigit())
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.nodeName)
                    .font(.caption.weight(.semibold))
                Text(step.interfaceName ?? "lokal")
                    .font(.caption2.monospaced())
            }
            .frame(width: 180, alignment: .leading)

            ForEach(TopologyPacketTraceLayer.viewerLayers, id: \.rawValue) { layer in
                let active = layer.viewerGroup == step.layer.viewerGroup
                Text(active ? TopologyPacketViewerFormatting.operationName(step.operation) : "")
                    .font(.caption2.weight(active ? .semibold : .regular))
                    .frame(width: 135, height: 34)
                    .background(active
                        ? TopologyPacketViewerColors.colors(for: layer).background
                        : Color(white: 0.86))
                    .foregroundStyle(active
                        ? TopologyPacketViewerColors.colors(for: layer).foreground
                        : Color.gray)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(active ? Color.black.opacity(0.35) : Color.gray.opacity(0.22))
                    }
            }
            Text(step.detail ?? "")
                .font(.caption2.monospaced())
                .frame(width: 260, alignment: .leading)
                .lineLimit(2)
        }
        .padding(4)
        .background(selectedStepID == step.id ? Color.yellow.opacity(0.4) : Color.white)
        .overlay(alignment: .bottom) {
            if step.beforeHeaders != step.afterHeaders && !step.beforeHeaders.isEmpty && !step.afterHeaders.isEmpty {
                Rectangle().fill(Color.orange).frame(height: 2)
            }
        }
    }

    private func layerPathDetails(
        _ step: TopologyPacketLayerPathStep,
        compact: Bool
    ) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Text(FiliusLocalization.t("runtime.layerTitle", step.nodeName))
                    .font(.caption.weight(.semibold))
                if compact {
                    headerColumn(FiliusLocalization.t("packet.headers.before"), step.beforeHeaders)
                    Image(systemName: "arrow.down")
                        .foregroundStyle(step.beforeHeaders == step.afterHeaders ? Color.secondary : Color.orange)
                    headerColumn(FiliusLocalization.t("packet.headers.after"), step.afterHeaders)
                    layerPathDetailText(step)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        headerColumn(FiliusLocalization.t("packet.headers.before"), step.beforeHeaders)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(step.beforeHeaders == step.afterHeaders ? Color.secondary : Color.orange)
                        headerColumn(FiliusLocalization.t("packet.headers.after"), step.afterHeaders)
                        layerPathDetailText(step)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("runtime.layer-path.details")
    }

    private func layerPathDetailText(_ step: TopologyPacketLayerPathStep) -> some View {
        VStack(alignment: .leading) {
            Text(FiliusLocalization.t("ui.dd86b1252be2"))
                .font(.caption.weight(.semibold))
            Text(step.detail ?? "—")
                .font(.caption2.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerColumn(_ title: String, _ fields: [TopologyPacketHeaderField]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(fields.isEmpty ? "â€”" : fields.map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
                .font(.caption2.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum TopologyPacketViewerFormatting {
    static func time(_ milliseconds: UInt64) -> String {
        String(format: "%.3f s", Double(milliseconds) / 1_000.0)
    }

    static func layerName(_ layer: TopologyPacketTraceLayer) -> String {
        switch layer.viewerGroup {
        case .dataLink: return FiliusLocalization.t("packet.layer.dataLink")
        case .network: return FiliusLocalization.t("packet.layer.network")
        case .transport: return FiliusLocalization.t("packet.layer.transport")
        case .application: return FiliusLocalization.t("packet.layer.application")
        case .physical: return FiliusLocalization.t("packet.layer.physical")
        }
    }

    static func operationName(_ operation: TopologyPacketTraceOperation) -> String {
        switch operation {
        case .created: return FiliusLocalization.t("packet.operation.created")
        case .sent: return FiliusLocalization.t("packet.operation.sent")
        case .received: return FiliusLocalization.t("packet.operation.received")
        case .forwarded: return FiliusLocalization.t("packet.operation.forwarded")
        case .accepted: return FiliusLocalization.t("packet.operation.accepted")
        case .dropped: return FiliusLocalization.t("packet.operation.dropped")
        case .rewritten: return FiliusLocalization.t("packet.operation.rewritten")
        case .retransmitted: return FiliusLocalization.t("packet.operation.retransmitted")
        case .compatibilityAdapter: return FiliusLocalization.t("packet.operation.compatibilityAdapter")
        }
    }
}

private enum TopologyPacketViewerColors {
    static func colors(for layer: TopologyPacketTraceLayer) -> (foreground: Color, background: Color) {
        switch layer.viewerGroup {
        case .physical, .dataLink:
            return (.black, Color(red: 0.9, green: 0.9, blue: 0.9))
        case .network:
            return (.black, Color(red: 0.3, green: 1.0, blue: 0.3))
        case .transport:
            return (.black, .cyan)
        case .application:
            return (.white, .blue)
        }
    }
}

private extension TopologyPacketTraceLayer {
    static let viewerLayers: [TopologyPacketTraceLayer] = [.dataLink, .network, .transport, .application]

    var viewerGroup: TopologyPacketTraceLayer {
        self == .physical ? .dataLink : self
    }
}

enum RuntimeHTMLDocumentIsolation {
    private static let policy = "default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; font-src data:; media-src data: blob:"

    static func document(containing deliveredHTML: String) -> String {
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"

        if let headStart = deliveredHTML.range(of: "<head", options: .caseInsensitive),
           let headEnd = deliveredHTML.range(
               of: ">",
               range: headStart.lowerBound..<deliveredHTML.endIndex
           ) {
            var document = deliveredHTML
            document.insert(contentsOf: meta, at: headEnd.upperBound)
            return document
        }

        if let htmlStart = deliveredHTML.range(of: "<html", options: .caseInsensitive),
           let htmlEnd = deliveredHTML.range(
               of: ">",
               range: htmlStart.lowerBound..<deliveredHTML.endIndex
           ) {
            var document = deliveredHTML
            document.insert(contentsOf: "<head>\(meta)</head>", at: htmlEnd.upperBound)
            return document
        }

        let document = "<!doctype html><html><head>\(meta)</head><body>\(deliveredHTML)</body></html>"
        return document
    }
}

private struct RuntimeHTMLWebView: UIViewRepresentable {
    let html: String
    let currentAddress: String
    let onSimulatedRequest: (TopologyRuntimeWebBrowserRequest) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSimulatedRequest: onSimulatedRequest)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSimulatedRequest = onSimulatedRequest
        context.coordinator.currentAddress = currentAddress
        guard context.coordinator.loadedHTML != html
            || context.coordinator.loadedAddress != currentAddress
        else { return }

        context.coordinator.loadedHTML = html
        context.coordinator.loadedAddress = currentAddress
        webView.loadHTMLString(
            RuntimeHTMLDocumentIsolation.document(containing: html),
            baseURL: URL(string: currentAddress)
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?
        var loadedAddress: String?
        var currentAddress = ""
        var onSimulatedRequest: (TopologyRuntimeWebBrowserRequest) -> Void

        init(onSimulatedRequest: @escaping (TopologyRuntimeWebBrowserRequest) -> Void) {
            self.onSimulatedRequest = onSimulatedRequest
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.cancel)
                return
            }
            guard url.scheme?.lowercased() != "about" else {
                decisionHandler(.allow)
                return
            }
            guard let address = simulatedAddress(for: url),
                  let request = simulatedRequest(
                    from: navigationAction.request,
                    address: address
                  )
            else {
                decisionHandler(.cancel)
                return
            }
            onSimulatedRequest(request)
            decisionHandler(.cancel)
        }

        private func simulatedAddress(for url: URL) -> String? {
            if url.scheme?.lowercased() == "http" {
                return url.absoluteString
            }
            guard let base = URL(string: currentAddress),
                  let resolved = URL(string: url.relativeString, relativeTo: base)?.absoluteURL,
                  resolved.scheme?.lowercased() == "http"
            else { return nil }
            return resolved.absoluteString
        }

        private func simulatedRequest(
            from request: URLRequest,
            address: String
        ) -> TopologyRuntimeWebBrowserRequest? {
            let method = request.httpMethod?.uppercased() ?? "GET"
            guard method == "GET" || method == "POST" else { return nil }
            guard method == "POST" else {
                return TopologyRuntimeWebBrowserRequest(address: address)
            }
            guard let body = request.httpBody,
                  body.count <= TopologyRuntimeWebBrowserRequest.maximumBodySize
            else { return nil }
            return TopologyRuntimeWebBrowserRequest(
                address: address,
                method: method,
                body: body
            )
        }
    }
}

/// Email client workspace used by the runtime device sheet.
///
/// This local implementation keeps the existing account/compose/mailbox flows in
/// the bounded sheet file while adding the message actions that are backed by the
/// reducer. The pure reply and deletion rules remain in `TopologyEmailActions`.
private struct TopologyRuntimeEmailReplyDeletionView: View {
    private enum MailboxSection: String, CaseIterable, Identifiable {
        case account
        case compose
        case inbox
        case sent
        case logs

        var id: String { rawValue }
        var localizationKey: String { "email.client.section.\(rawValue)" }
    }

    private struct PendingDeletion: Identifiable {
        let folder: TopologyRuntimeEmailClientFolder
        let messageID: UInt64
        let subject: String

        var id: String { "\(folder.rawValue)-\(messageID)" }
    }

    let configuration: TopologyRuntimeEmailClientConfiguration
    let state: TopologyRuntimeEmailClientState
    let onSaveConfiguration: (TopologyRuntimeEmailClientConfiguration) -> Void
    let onSend: (TopologyRuntimeEmailMessage) -> Void
    let onRetrieve: () -> Void
    let onDeleteMessages: (TopologyRuntimeEmailClientFolder, [UInt64]) -> Void

    @State private var selectedSection: MailboxSection = .account
    @State private var name: String
    @State private var email: String
    @State private var username: String
    @State private var password: String
    @State private var smtpHost: String
    @State private var smtpPort: String
    @State private var pop3Host: String
    @State private var pop3Port: String
    @State private var composeTo = ""
    @State private var composeCC = ""
    @State private var composeBCC = ""
    @State private var composeSubject = ""
    @State private var composeBody = ""
    @State private var pendingDeletion: PendingDeletion?
    @State private var actionError: String?

    init(
        configuration: TopologyRuntimeEmailClientConfiguration,
        state: TopologyRuntimeEmailClientState,
        onSaveConfiguration: @escaping (TopologyRuntimeEmailClientConfiguration) -> Void,
        onSend: @escaping (TopologyRuntimeEmailMessage) -> Void,
        onRetrieve: @escaping () -> Void,
        onDeleteMessages: @escaping (TopologyRuntimeEmailClientFolder, [UInt64]) -> Void
    ) {
        self.configuration = configuration
        self.state = state
        self.onSaveConfiguration = onSaveConfiguration
        self.onSend = onSend
        self.onRetrieve = onRetrieve
        self.onDeleteMessages = onDeleteMessages
        _name = State(initialValue: configuration.name)
        _email = State(initialValue: configuration.email)
        _username = State(initialValue: configuration.username)
        _password = State(initialValue: configuration.password)
        _smtpHost = State(initialValue: configuration.smtpHost)
        _smtpPort = State(initialValue: String(configuration.smtpPort))
        _pop3Host = State(initialValue: configuration.pop3Host)
        _pop3Port = State(initialValue: String(configuration.pop3Port))
    }

    var body: some View {
        Form {
            statusSection
            Section {
                Picker(FiliusLocalization.t("email.client.section.label"), selection: $selectedSection) {
                    ForEach(MailboxSection.allCases) { section in
                        Text(FiliusLocalization.t(section.localizationKey)).tag(section)
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: 44)
                .accessibilityIdentifier("email.client.section")
            }
            selectedContent
        }
        .accessibilityIdentifier("email.client.view")
        .confirmationDialog(
            FiliusLocalization.t("email.message.delete.confirm.title"),
            isPresented: deletionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(FiliusLocalization.t("email.message.delete"), role: .destructive) {
                guard let pendingDeletion else { return }
                onDeleteMessages(pendingDeletion.folder, [pendingDeletion.messageID])
                self.pendingDeletion = nil
            }
            Button(FiliusLocalization.t("ui.07af7cb30fca"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(FiliusLocalization.t("email.message.delete.confirm.message"))
        }
        .alert(
            FiliusLocalization.t("email.message.action.failed"),
            isPresented: actionErrorBinding,
            presenting: actionError
        ) { _ in
            Button(FiliusLocalization.t("ui.9ce3bd4224c8"), role: .cancel) {
                actionError = nil
            }
        } message: { error in
            Text(error)
        }
        .onChange(of: configuration) { _, newConfiguration in
            name = newConfiguration.name
            email = newConfiguration.email
            username = newConfiguration.username
            password = newConfiguration.password
            smtpHost = newConfiguration.smtpHost
            smtpPort = String(newConfiguration.smtpPort)
            pop3Host = newConfiguration.pop3Host
            pop3Port = String(newConfiguration.pop3Port)
        }
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented { pendingDeletion = nil }
            }
        )
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { actionError != nil },
            set: { isPresented in
                if !isPresented { actionError = nil }
            }
        )
    }

    @ViewBuilder private var selectedContent: some View {
        switch selectedSection {
        case .account:
            accountSection
        case .compose:
            composeSection
        case .inbox:
            messageSection(
                titleKey: "email.client.inbox.title",
                emptyKey: "email.client.inbox.empty",
                folder: .inbox,
                messages: configuration.inbox,
                identifier: "email.client.inbox"
            )
        case .sent:
            messageSection(
                titleKey: "email.client.sent.title",
                emptyKey: "email.client.sent.empty",
                folder: .sent,
                messages: configuration.sent,
                identifier: "email.client.sent"
            )
        case .logs:
            logsSection
        }
    }

    private var emailStatusLocalizationKey: String {
        if state.lastError != nil {
            return "email.client.status.error"
        }
        if state.activeOperation == "retrieving" {
            return "email.client.status.retrieving"
        }
        if state.isBusy {
            return "email.client.status.sending"
        }
        return "email.client.status.idle"
    }

    private var statusSection: some View {
        Section(FiliusLocalization.t("email.client.status.section")) {
            LabeledContent(
                FiliusLocalization.t("email.status.label"),
                value: FiliusLocalization.t(emailStatusLocalizationKey)
            )
            if let lastError = state.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("email.client.status.detail")
            }
            Button(action: onRetrieve) {
                Label(
                    FiliusLocalization.t("email.client.retrieve"),
                    systemImage: "arrow.down.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: 44)
            .disabled(state.isBusy)
            .accessibilityIdentifier("email.client.retrieve")
        }
    }

    private var accountSection: some View {
        Section(FiliusLocalization.t("email.client.account.title")) {
            emailField("email.client.account.name", text: $name, identifier: "email.client.account.name")
            emailField("email.client.account.address", text: $email, identifier: "email.client.account.address", keyboard: .emailAddress)
            emailField("email.client.account.username", text: $username, identifier: "email.client.account.username")
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("email.client.account.password"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(FiliusLocalization.t("email.client.account.password"), text: $password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("email.client.account.password")
            }
            emailField("email.client.account.smtpHost", text: $smtpHost, identifier: "email.client.account.smtpHost")
            emailField("email.client.account.smtpPort", text: $smtpPort, identifier: "email.client.account.smtpPort", keyboard: .numberPad)
            emailField("email.client.account.pop3Host", text: $pop3Host, identifier: "email.client.account.pop3Host")
            emailField("email.client.account.pop3Port", text: $pop3Port, identifier: "email.client.account.pop3Port", keyboard: .numberPad)
            Button(action: saveConfiguration) {
                Label(
                    FiliusLocalization.t("email.client.account.save"),
                    systemImage: "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: 44)
            .accessibilityIdentifier("email.client.account.save")
        }
    }

    private var composeSection: some View {
        Section(FiliusLocalization.t("email.client.compose.title")) {
            emailField("email.client.compose.to", text: $composeTo, identifier: "email.client.compose.to", keyboard: .emailAddress)
            emailField("email.client.compose.cc", text: $composeCC, identifier: "email.client.compose.cc", keyboard: .emailAddress)
            emailField("email.client.compose.bcc", text: $composeBCC, identifier: "email.client.compose.bcc", keyboard: .emailAddress)
            emailField("email.client.compose.subject", text: $composeSubject, identifier: "email.client.compose.subject")
            VStack(alignment: .leading, spacing: 4) {
                Text(FiliusLocalization.t("email.client.compose.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $composeBody)
                    .frame(minHeight: 160)
                    .accessibilityLabel(FiliusLocalization.t("email.client.compose.body"))
                    .accessibilityIdentifier("email.client.compose.body")
            }
            Button(action: sendComposedMessage) {
                Label(
                    FiliusLocalization.t("email.client.compose.send"),
                    systemImage: "paperplane"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minHeight: 44)
            .disabled(state.isBusy)
            .accessibilityIdentifier("email.client.compose.send")
        }
    }

    private func messageSection(
        titleKey: String,
        emptyKey: String,
        folder: TopologyRuntimeEmailClientFolder,
        messages: [TopologyRuntimeEmailMessage],
        identifier: String
    ) -> some View {
        Section(FiliusLocalization.t(titleKey)) {
            if messages.isEmpty {
                Text(FiliusLocalization.t(emptyKey))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages, id: \.id) { message in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            messageAddressLine("email.message.from", addresses: [message.from])
                            messageAddressLine("email.message.to", addresses: message.to)
                            if !message.cc.isEmpty {
                                messageAddressLine("email.message.cc", addresses: message.cc)
                            }
                            if !message.bcc.isEmpty {
                                messageAddressLine("email.message.bcc", addresses: message.bcc)
                            }
                            Divider()
                            Text(message.body.isEmpty ? FiliusLocalization.t("email.message.emptyBody") : message.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) { messageActionButtons(message, folder: folder) }
                                VStack(spacing: 8) { messageActionButtons(message, folder: folder) }
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(message.subject.isEmpty ? FiliusLocalization.t("email.message.noSubject") : message.subject)
                                .font(.headline)
                            Text(message.from.javaString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let receivedAtMilliseconds = message.receivedAtMilliseconds {
                                Text(String(receivedAtMilliseconds))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("\(identifier).message.\(message.id)")
                }
            }
        }
    }

    @ViewBuilder private func messageActionButtons(
        _ message: TopologyRuntimeEmailMessage,
        folder: TopologyRuntimeEmailClientFolder
    ) -> some View {
        Button {
            prepareReply(to: message, mode: .reply)
        } label: {
            Label(FiliusLocalization.t("email.message.reply"), systemImage: "arrowshape.turn.up.left")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("email.message.\(message.id).reply")

        Button {
            prepareReply(to: message, mode: .replyAll)
        } label: {
            Label(FiliusLocalization.t("email.message.replyAll"), systemImage: "arrowshape.turn.up.left.2")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("email.message.\(message.id).replyAll")

        Button(role: .destructive) {
            pendingDeletion = PendingDeletion(
                folder: folder,
                messageID: message.id,
                subject: message.subject
            )
        } label: {
            Label(FiliusLocalization.t("email.message.delete"), systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("email.message.\(message.id).delete")
    }

    private var logsSection: some View {
        Section(FiliusLocalization.t("email.logs.title")) {
            let entries = Array(state.logs.suffix(50))
            if entries.isEmpty {
                Text(FiliusLocalization.t("email.logs.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(entry.timestampMilliseconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(FiliusLocalization.t(
                            "email.logs.entry",
                            entry.protocolName,
                            entry.direction,
                            entry.message
                        ))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("email.client.log.\(entry.id)")
                }
            }
        }
    }

    private func saveConfiguration() {
        var updated = configuration
        updated.name = name
        updated.email = email
        updated.username = username
        updated.password = password
        updated.smtpHost = smtpHost
        updated.smtpPort = Int(smtpPort) ?? 0
        updated.pop3Host = pop3Host
        updated.pop3Port = Int(pop3Port) ?? 0
        onSaveConfiguration(updated)
    }

    private func sendComposedMessage() {
        let message = TopologyRuntimeEmailMessage(
            from: configuration.address,
            to: parsedEmailAddresses(composeTo),
            cc: parsedEmailAddresses(composeCC),
            bcc: parsedEmailAddresses(composeBCC),
            subject: composeSubject,
            body: composeBody
        )
        onSend(message)
    }

    private func prepareReply(
        to message: TopologyRuntimeEmailMessage,
        mode: TopologyRuntimeEmailReplyMode
    ) {
        do {
            let draft = try TopologyEmailActions.replyDraft(
                to: message,
                from: configuration.address,
                mode: mode
            )
            composeTo = draft.to.map(\.javaString).joined(separator: ", ")
            composeCC = draft.cc.map(\.javaString).joined(separator: ", ")
            composeBCC = ""
            composeSubject = draft.subject
            composeBody = draft.body
            selectedSection = .compose
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func parsedEmailAddresses(_ rawValue: String) -> [TopologyRuntimeEmailAddress] {
        rawValue
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .compactMap { token in
                let value = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
                return TopologyRuntimeEmailAddress(javaString: value)
            }
    }

    private func messageAddressLine(
        _ key: String,
        addresses: [TopologyRuntimeEmailAddress]
    ) -> some View {
        LabeledContent(
            FiliusLocalization.t(key),
            value: addresses.map(\.javaString).joined(separator: ", ")
        )
        .font(.caption)
    }

    private func emailField(
        _ key: String,
        text: Binding<String>,
        identifier: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FiliusLocalization.t(key))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(FiliusLocalization.t(key), text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .accessibilityIdentifier(identifier)
        }
    }
}
