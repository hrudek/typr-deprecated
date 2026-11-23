import Foundation

extension DictationController {
    // MARK: - Speech Engine

    enum SpeechEngineSelection: Equatable {
        case selected
        case alreadySelected
        /// A dictation is being set up, recorded, transcribed or cleaned up.
        case busy
        /// A downloaded engine is not downloaded and verified; nothing is downloaded by selecting it.
        case notInstalled
    }

    enum ModelDeletion: Equatable {
        case deleted
        /// A dictation or another deletion is running.
        case busy
        /// Apple Speech: iOS manages its assets.
        case notDeletable
        case failed(String)
    }

    /// False from the microphone permission request until transcription and cleanup finish, and
    /// while a model is being deleted.
    var canChangeEngine: Bool {
        switch phase {
        case .requestingPermission, .recording, .transcribing:
            return false
        case .modelRequired, .preparingModel, .ready, .failed:
            return activeCapture == nil && pendingCleanupJob == nil && transcribingLog == nil
                && inFlightTranscriptions.isEmpty && inFlightPermissionRequests == 0 && !isDeletingModel
        }
    }

    /// Deletes the engine's model files. A loaded or preparing model of that engine is released
    /// first (ending a warm session); the chosen engine stays chosen and is never replaced.
    @discardableResult
    func deleteModel(_ engine: SpeechEngineChoice) async -> ModelDeletion {
        guard engine.hasDeletableModel else { return .notDeletable }
        guard canChangeEngine else { return .busy }
        isDeletingModel = true
        let preparingEngine = preferredEngine ?? SpeechEngineChoice(displayName: engineName)
        if currentEngine == engine || (!isModelReady && preparingEngine == engine) {
            if keyboardSessionEnabled { endWarmSession() }
            modelPrepGeneration &+= 1
            preparationTask?.cancel()
            modelBackground?.finish(success: false)
            transcriber = UnpreparedTranscriber(displayName: engineName)
            currentEngine = nil
            isModelReady = false
            phase = .modelRequired
        }
        if workingEngine?.engine == engine {
            workingEngine = nil
        }
        // A Core ML load cannot be interrupted, also one superseded by another engine's choice.
        while loadingEngines.values.contains(engine) {
            deletionWaitsForTesting += 1
            await withCheckedContinuation { loadFinishedWaiters.append($0) }
        }
        let result: ModelDeletion
        do {
            try engineProvider.deleteModel(engine)
            result = .deleted
        } catch {
            result = .failed(error.localizedDescription)
        }
        if !isModelReady {
            keyboardBridge.setModelInstalled(
                preferredEngine.map { engineProvider.isInstalled($0) } ?? ParakeetTranscriber.hasCachedModel)
        }
        publishKeyboardSnapshot()
        scheduleModelMaintenance()
        isDeletingModel = false
        fulfillPendingHandoffOrPrepare()
        return result
    }

    /// OS, device, language and install status for the settings section. Starts no model work.
    func engineAvailability(_ engine: SpeechEngineChoice) async -> SpeechEngineAvailability {
        await engineProvider.availability(of: engine, language: dictationLanguage)
    }

    /// The settings section's choice: persisted, then the previous engine is released and the
    /// chosen one prepared while idle. Never falls back to another engine.
    @discardableResult
    func selectEngine(_ engine: SpeechEngineChoice) -> SpeechEngineSelection {
        guard canChangeEngine else { return .busy }
        guard engine != preferredEngine else { return .alreadySelected }
        if engine.requiresExplicitDownload, !engineProvider.isInstalled(engine) {
            return .notInstalled
        }
        preferredEngine = engine
        languageSettings.preferredSpeechEngine = engine
        MultilingualParakeetSettings().isModelReady = false
        multilingualDownload.cancel()
        engineName = engine.displayName
        languageNotice = nil
        // Pinning the automatically ready engine needs no model reload.
        if currentEngine != engine || !isModelReady { prepareModel() }
        return .selected
    }

    func setMicrophone(_ choice: MicrophoneChoice) {
        guard microphone != choice else { return }
        microphone = choice
        keyboardBridge.microphone = choice
        if keyboardSessionEnabled, phase == .ready {
            do { try startWarmInput() }
            catch { endWarmSession() }
        }
    }

    /// Reopening prepares only an installed, explicitly selected downloaded engine, never a
    /// download or a replacement engine. Also used by maintenance: both paths join the same preparation.
    var needsDownloadedModelPreparation: Bool {
        preferredDownloadedEngineIsInstalled && !isModelReady && canChangeEngine
    }

    private var preferredDownloadedEngineIsInstalled: Bool {
        guard let preferredEngine, preferredEngine.requiresExplicitDownload else { return false }
        return engineProvider.isInstalled(preferredEngine)
    }

    func prepareInstalledModelIfNeeded() {
        guard needsDownloadedModelPreparation, phase != .preparingModel else { return }
        prepareModel()
    }

    func scheduleModelMaintenance() {
        modelBackground?.scheduleMaintenance(needed: preferredDownloadedEngineIsInstalled)
    }

    func expireModelPreparation(_ engine: SpeechEngineChoice, generation: UInt64) {
        guard modelPrepGeneration == generation, phase == .preparingModel else { return }
        // Invalidate immediately, but retain the task so a retry waits for any non-interruptible
        // Core ML call to return and release its candidate before allocating another one.
        modelPrepGeneration &+= 1
        preparationTask?.cancel()
        pendingHandoff = nil
        phase = .failed("\(engine.shortName) preparation paused. Open Typr or tap Try again to continue. iOS controls background time.")
        modelPreparation = ModelPreparationProgress(fractionCompleted: nil, detail: "\(engine.shortName) preparation paused")
        publishKeyboardSnapshot()
        scheduleModelMaintenance()
    }

    /// A field inside Typr itself needs no return.
    func maybeAutoReturnAfterActivation(allowed: Bool) {
        guard allowed else { return }
        guard languageSettings[experiment: .typrAutomaticHostReturn], let host = returnHost else {
            autoReturnState = .swipeFallback
            return
        }
        guard host != HostReturnCatalog.typrBundleID else { return }
        triggerAutoReturn(to: host)
    }

    private func triggerAutoReturn(to host: String) {
        autoReturnFallbackTask?.cancel()
        autoReturnState = .attempting
        let returner = hostReturner

        Task {
            let opened = await returner.open(host)
            guard case .attempting = self.autoReturnState else { return }
            if !opened {
                self.autoReturnState = .swipeFallback
                return
            }
            self.autoReturnFallbackTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(950))
                guard !Task.isCancelled, let self else { return }
                if case .attempting = self.autoReturnState {
                    self.autoReturnState = .swipeFallback
                }
            }
        }
    }

    var canReusePreparedModel: Bool {
        isModelReady && !modelNeedsReload && !pendingAppleLanguageChange
    }

    func wireSystemIntentBus() {
        Task {
            await TyprSystemCommandBus.shared.register { [weak self] command in
                guard let self else { return nil }
                return await self.performSystemCommand(command)
            }
        }
    }

    private func performSystemCommand(_ command: TyprSystemCommand) async -> String? {
        switch command {
        case .toggleDictation:
            if phase == .recording {
                finishRecording()
                if let task = transcriptionTask {
                    await task.value
                }
                return transcript
            }
            if phase == .modelRequired || isFailedPhase {
                prepareModel()
            }
            if phase == .preparingModel {
                try? await waitUntilReady(timeoutSeconds: 10)
            }
            guard phase == .ready else { return nil }
            startRecording(copyToPasteboard: true)
            return ""

        case .stopDictation:
            guard phase == .recording else { return transcript }
            finishRecording()
            if let task = transcriptionTask {
                await task.value
            }
            return transcript

        case .cancelDictation:
            cancelCurrentJob()
            return nil

        case .warmSession:
            if !keyboardSessionEnabled {
                if warmDuration == .off {
                    setWarmDuration(.fifteenMinutes)
                }
                requestWarmSession(attemptAutoReturn: false)
            }
            return nil
        }
    }

    private var isFailedPhase: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func waitUntilReady(timeoutSeconds: TimeInterval) async throws {
        let deadline = now() + timeoutSeconds
        while phase == .preparingModel && now() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
