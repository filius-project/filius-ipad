import Foundation
import SwiftUI

@main
struct FiliusPadApp: App {
    @State private var editorState = TopologyEditorState()
    @State private var appPreferences: TopologyAppPreferences
    @State private var autosaveTask: Task<Void, Never>?
    @State private var hasAttemptedLaunchRestore = false
    @State private var persistenceLifecycle = TopologyPersistenceLifecycle()
    @State private var stateReplacementGeneration: UInt64 = 0

    private let launchConfiguration: PersistenceLaunchConfiguration
    private let projectStore: TopologyProjectStore
    private let appPreferencesStore: TopologyAppPreferencesStore
    private let autosaveDebounceNanoseconds: UInt64 = 500_000_000
    private let persistenceSaveCoordinator = TopologyPersistenceSaveCoordinator()

    init() {
        let launchConfiguration = Self.resolvePersistenceLaunchConfiguration()
        let appPreferencesStore = TopologyAppPreferencesStore()
        self.launchConfiguration = launchConfiguration
        self.projectStore = TopologyProjectStore(fileURL: launchConfiguration.autosaveFileURL)
        self.appPreferencesStore = appPreferencesStore
        let loadedPreferences = appPreferencesStore.load()
        FiliusLocalization.activate(loadedPreferences.language)
        _appPreferences = State(initialValue: loadedPreferences)
    }

    init(
        projectStore: TopologyProjectStore,
        appPreferencesStore: TopologyAppPreferencesStore = TopologyAppPreferencesStore()
    ) {
        let launchConfiguration = Self.resolvePersistenceLaunchConfiguration()
        self.launchConfiguration = launchConfiguration
        self.projectStore = projectStore
        self.appPreferencesStore = appPreferencesStore
        let loadedPreferences = appPreferencesStore.load()
        FiliusLocalization.activate(loadedPreferences.language)
        _appPreferences = State(initialValue: loadedPreferences)
    }

    var body: some Scene {
        WindowGroup {
            TopologyEditorView(
                state: $editorState,
                appPreferences: $appPreferences,
                isPersistenceBusy: persistenceLifecycle.isRestoringAutosave,
                stateReplacementGeneration: stateReplacementGeneration,
                onExternalStateReplacement: replaceEditorState,
                onRestoreAppPreferences: restoreAppPreferences
            )
                .preferredColorScheme(.light)
                .environment(\.locale, appPreferences.language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent)
                .onAppear {
                    guard !hasAttemptedLaunchRestore else {
                        return
                    }

                    hasAttemptedLaunchRestore = true
                    let restoreToken = persistenceLifecycle.beginAutosaveRestore()
                    Task {
                        await restoreAutosaveSnapshotOnLaunch(token: restoreToken)
                    }
                }
                .onChange(of: editorState.persistenceRevision) { _, _ in
                    scheduleDebouncedAutosaveIfNeeded()
                }
                .onChange(of: appPreferences) { _, newPreferences in
                    FiliusLocalization.activate(newPreferences.language)
                    _ = appPreferencesStore.persist(newPreferences)
                }
                .onDisappear {
                    autosaveTask?.cancel()
                }
        }
    }

    @MainActor
    private func restoreAppPreferences() {
        appPreferences = appPreferencesStore.restoreFactoryDefaults()
    }

    @MainActor
    private func replaceEditorState(_ replacementState: TopologyEditorState) {
        persistenceLifecycle.invalidateForExternalStateReplacement()
        autosaveTask?.cancel()
        let generation = persistenceSaveCoordinator.advanceGeneration()

        let targetRevision = replacementState.persistenceRevision
        editorState = replacementState

        // Project replacement must reach native autosave immediately. The serial save queue
        // guarantees that any already-running stale save finishes before this replacement save.
        Task {
            await persistReplacementSnapshot(
                replacementState,
                targetRevision: targetRevision,
                generation: generation
            )
        }
    }

    @MainActor
    private func restoreAutosaveSnapshotOnLaunch(token: UInt64) async {
        defer {
            persistenceLifecycle.finishAutosaveRestore(token)
        }

        prepareLaunchAutosaveFixtureIfNeeded()

        do {
            var restoredState = try await loadStateFromStore()
            guard persistenceLifecycle.canApplyAutosaveRestore(token) else {
                return
            }
            restoredState.recordPersistenceLoad()
            restoredState.recordRecoverySuccess(
                message: FiliusLocalization.t("app.recoveredAutosave", restoredState.persistenceRevision)
            )
            autosaveTask?.cancel()
            persistenceSaveCoordinator.advanceGeneration()
            editorState = restoredState
            stateReplacementGeneration = nextGeneration(after: stateReplacementGeneration)
        } catch let persistenceError as TopologyProjectPersistenceError {
            if persistenceError.code == .fileNotFound {
                return
            }
            guard persistenceLifecycle.canApplyAutosaveRestore(token) else {
                return
            }

            let sanitizedDetail = sanitizePersistenceDetail(persistenceError.detail)

            editorState.recordPersistenceFailure(
                operation: persistenceError.operation,
                code: persistenceError.code,
                detail: sanitizedDetail
            )
            editorState.recordRecoveryFailure(
                message: FiliusLocalization.t("app.recoveryFailed", persistenceError.code.rawValue)
            )
        } catch {
            guard persistenceLifecycle.canApplyAutosaveRestore(token) else {
                return
            }
            editorState.recordPersistenceFailure(
                operation: .load,
                code: .malformedPayload,
                detail: FiliusLocalization.t("app.persistenceUnexpected")
            )
            editorState.recordRecoveryFailure(
                message: FiliusLocalization.t("app.recoveryFailed", "malformedPayload")
            )
        }
    }

    @MainActor
    private func scheduleDebouncedAutosaveIfNeeded() {
        autosaveTask?.cancel()

        let targetRevision = editorState.persistenceRevision
        let generation = persistenceSaveCoordinator.currentGeneration
        guard targetRevision > editorState.lastPersistedRevision else {
            return
        }

        autosaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: autosaveDebounceNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            var snapshotToSave: TopologyEditorState?

            await MainActor.run {
                guard persistenceSaveCoordinator.isCurrent(generation),
                      editorState.persistenceRevision == targetRevision,
                      editorState.persistenceRevision > editorState.lastPersistedRevision
                else {
                    return
                }

                snapshotToSave = editorState
            }

            guard let snapshotToSave else {
                return
            }

            do {
                let savedAt = Date()
                guard try await saveStateToStore(
                    snapshotToSave,
                    savedAt: savedAt,
                    generation: generation
                ) else {
                    return
                }
                await MainActor.run {
                    guard persistenceSaveCoordinator.isCurrent(generation),
                          editorState.persistenceRevision == targetRevision
                    else {
                        return
                    }
                    editorState.recordPersistenceSave(revision: targetRevision, at: savedAt)
                }
            } catch let persistenceError as TopologyProjectPersistenceError {
                await MainActor.run {
                    guard persistenceSaveCoordinator.isCurrent(generation),
                          editorState.persistenceRevision == targetRevision
                    else {
                        return
                    }
                    editorState.recordPersistenceFailure(
                        operation: persistenceError.operation,
                        code: persistenceError.code,
                        detail: sanitizePersistenceDetail(persistenceError.detail)
                    )
                }
            } catch {
                await MainActor.run {
                    guard persistenceSaveCoordinator.isCurrent(generation),
                          editorState.persistenceRevision == targetRevision
                    else {
                        return
                    }
                    editorState.recordPersistenceFailure(
                        operation: .save,
                        code: .fileWriteFailed,
                        detail: FiliusLocalization.t("app.saveUnexpected")
                    )
                }
            }
        }
    }

    private func persistReplacementSnapshot(
        _ snapshot: TopologyEditorState,
        targetRevision: UInt64,
        generation: UInt64
    ) async {
        do {
            let savedAt = Date()
            guard try await saveStateToStore(
                snapshot,
                savedAt: savedAt,
                generation: generation
            ) else {
                return
            }
            await MainActor.run {
                guard persistenceSaveCoordinator.isCurrent(generation),
                      editorState.persistenceRevision == targetRevision
                else {
                    return
                }
                editorState.recordPersistenceSave(revision: targetRevision, at: savedAt)
            }
        } catch let persistenceError as TopologyProjectPersistenceError {
            await MainActor.run {
                guard persistenceSaveCoordinator.isCurrent(generation),
                      editorState.persistenceRevision == targetRevision
                else {
                    return
                }
                editorState.recordPersistenceFailure(
                    operation: persistenceError.operation,
                    code: persistenceError.code,
                    detail: sanitizePersistenceDetail(persistenceError.detail)
                )
            }
        } catch {
            await MainActor.run {
                guard persistenceSaveCoordinator.isCurrent(generation),
                      editorState.persistenceRevision == targetRevision
                else {
                    return
                }
                editorState.recordPersistenceFailure(
                    operation: .save,
                    code: .fileWriteFailed,
                    detail: "Unexpected persistence save failure"
                )
            }
        }
    }

    private func loadStateFromStore() async throws -> TopologyEditorState {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let loadedState = try projectStore.load()
                    continuation.resume(returning: loadedState)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func saveStateToStore(
        _ state: TopologyEditorState,
        savedAt: Date,
        generation: UInt64
    ) async throws -> Bool {
        try await persistenceSaveCoordinator.perform(generation: generation) {
            try projectStore.save(state: state, savedAt: savedAt)
        }
    }

    private func nextGeneration(after generation: UInt64) -> UInt64 {
        generation == UInt64.max ? 1 : generation + 1
    }

    private func sanitizePersistenceDetail(_ detail: String) -> String {
        let redacted = detail.replacingOccurrences(
            of: #"((file:\/\/)?[A-Za-z]:\\[^\s]+|\/[A-Za-z0-9._\/-]+)"#,
            with: "<path>",
            options: .regularExpression
        )

        return String(redacted.prefix(280))
    }

    private func prepareLaunchAutosaveFixtureIfNeeded() {
        guard launchConfiguration.shouldInjectMalformedAutosave else {
            return
        }

        do {
            let parentDirectory = projectStore.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
            try Data("{malformed-autosave".utf8).write(to: projectStore.fileURL, options: .atomic)
        } catch {
            editorState.recordPersistenceFailure(
                operation: .save,
                code: .fileWriteFailed,
                detail: "Failed to seed malformed autosave fixture"
            )
        }
    }

    private static func resolvePersistenceLaunchConfiguration() -> PersistenceLaunchConfiguration {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let arguments = Set(processInfo.arguments)

        let isUITesting = arguments.contains("-ui-testing")

        let autosaveFileURL: URL = {
            if let overridePath = environment["FILIUSPAD_AUTOSAVE_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !overridePath.isEmpty {
                return URL(fileURLWithPath: overridePath)
            }

            if isUITesting {
                let filename = "ui-testing-autosave-\(UUID().uuidString).topology.json"
                return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            }

            return defaultAutosaveFileURL
        }()

        let shouldInjectMalformedAutosave = arguments.contains("-inject-malformed-autosave")

        return PersistenceLaunchConfiguration(
            autosaveFileURL: autosaveFileURL,
            shouldInjectMalformedAutosave: shouldInjectMalformedAutosave
        )
    }

    private static var defaultAutosaveFileURL: URL {
        let rootDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return rootDirectory
            .appendingPathComponent("FiliusPad", isDirectory: true)
            .appendingPathComponent("autosave.topology.json", isDirectory: false)
    }
}

private struct PersistenceLaunchConfiguration {
    let autosaveFileURL: URL
    let shouldInjectMalformedAutosave: Bool
}
