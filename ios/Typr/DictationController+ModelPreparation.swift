import Foundation

extension DictationController {
    // MARK: - Model Preparation

    func prepareModel() {
        prepareModel(fallbacksLeft: 2)
    }

    struct WorkingEngine {
        let transcriber: any LocalTranscribing
        let engine: SpeechEngineChoice?
        let languageName: String
    }

    func prepareModel(fallbacksLeft: Int) {
        // This is also called by handoff/intents and tests, not just the settings button.
        guard canChangeEngine else { return }
        pendingAppleLanguageChange = false
        modelNeedsReload = false
        modelPrepGeneration &+= 1
        let prepGen = modelPrepGeneration
        modelBackground?.finish(success: false)
        phase = .preparingModel
        copied = false
        let downloaded = preferredEngine.flatMap { $0.requiresExplicitDownload ? $0 : nil }
        modelPreparation = ModelPreparationProgress(
            fractionCompleted: downloaded == nil ? 0 : nil,
            detail: "Checking model files"
        )
        let preferred = preferredEngine
        let language = dictationLanguage
        let previous = preparationTask
        previous?.cancel()
        if preferred != nil {
            workingEngine = nil
        } else if isModelReady {
            workingEngine = WorkingEngine(transcriber: transcriber, engine: currentEngine, languageName: transcriptionLanguage)
        }
        // Release the previous engine before the next one loads, so two large models are never
        // held together. A running transcription keeps its own snapshot until it ends.
        transcriber = UnpreparedTranscriber(displayName: engineName)
        currentEngine = nil
        isModelReady = false
        keyboardBridge.setModelInstalled(preferred.map { engineProvider.isInstalled($0) } ?? ParakeetTranscriber.hasCachedModel)
        publishKeyboardSnapshot()
        if let downloaded {
            modelBackground?.begin(downloaded) { [weak self] in
                self?.expireModelPreparation(downloaded, generation: prepGen)
            }
        }
        scheduleModelMaintenance()
        preparationFailedInBackground = false
        if downloaded == nil {
            watchPreparation(prepGen)
        }

        preparationTask = Task {
            defer {
                if self.modelPrepGeneration == prepGen, downloaded != nil {
                    self.modelBackground?.finish(success: self.isModelReady)
                }
            }
            // A superseded preparation finishes (and is dropped) before this one creates a model.
            await previous?.value
            guard self.modelPrepGeneration == prepGen else { return }
            do {
                let candidate: any LocalTranscribing
                if let preferred {
                    candidate = try await engineProvider.transcriber(for: preferred, language: language)
                } else if let transcriberFactory {
                    candidate = await transcriberFactory()
                } else {
                    candidate = await engineProvider.automaticTranscriber(language: language)
                }
                guard self.modelPrepGeneration == prepGen else { return }
                if candidate is ParakeetTranscriber, self.workingEngine?.transcriber is ParakeetTranscriber {
                    self.workingEngine = nil
                }
                engineName = candidate.displayName
                loadingEngines[prepGen] = SpeechEngineChoice(displayName: candidate.displayName)
                defer { loadingEngines[prepGen] = nil }
                try await candidate.prepare { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.modelPrepGeneration == prepGen else { return }
                        guard self.phase == .preparingModel else { return }
                        if progress.fractionCompleted != self.modelPreparation.fractionCompleted
                            || progress.detail != self.modelPreparation.detail {
                            self.preparationChangedAt = .now
                            self.preparationReported = true
                        }
                        self.modelPreparation = progress
                        if downloaded != nil { self.modelBackground?.update(progress) }
                    }
                }
                let candidateLanguageName = await candidate.languageName
                guard self.modelPrepGeneration == prepGen else { return }
                // A language change while preparation awaited must not publish the old Apple
                // locale as ready. The replacement waits for this task to release its candidate.
                if candidate.displayName == "Apple Speech", self.dictationLanguage != language {
                    self.pendingAppleLanguageChange = true
                    self.phase = .ready
                    self.preparePendingAppleLanguageIfIdle()
                    return
                }
                self.workingEngine = nil
                self.transcriber = candidate
                self.currentEngine = SpeechEngineChoice(displayName: candidate.displayName)
                self.transcriptionLanguage = candidateLanguageName
                self.keyboardBridge.setModelInstalled(true)
                self.isModelReady = true
                self.phase = .ready
                self.publishKeyboardSnapshot()
                if self.pendingHandoff != nil {
                    self.activateWarmSessionAndRunHandoff()
                }
            } catch {
                guard self.modelPrepGeneration == prepGen else { return }
                if preferred == nil, fallbacksLeft > 0, let notice = Self.switchNotice(for: error) {
                    self.languageNotice = notice
                    self.preparationTask = nil
                    self.prepareModel(fallbacksLeft: fallbacksLeft - 1)
                    return
                }
                if let working = self.workingEngine {
                    self.restore(working, because: error.localizedDescription)
                    return
                }
                self.preparationFailedInBackground = downloaded == nil && self.isInBackground
                    && Self.isDownloadInterruption(error)
                self.keyboardBridge.setModelInstalled(
                    preferred.map { self.engineProvider.isInstalled($0) } ?? ParakeetTranscriber.hasCachedModel)
                self.pendingHandoff = nil
                self.phase = .failed(error.localizedDescription)
                self.publishKeyboardSnapshot()
                self.preparePendingAppleLanguageIfIdle()
            }
        }
    }

    private func restore(_ working: WorkingEngine, because reason: String) {
        workingEngine = nil
        transcriber = working.transcriber
        currentEngine = working.engine
        engineName = working.transcriber.displayName
        transcriptionLanguage = working.languageName
        isModelReady = true
        languageNotice = "\(reason) Typr keeps using \(working.transcriber.displayName)."
        keyboardBridge.setModelInstalled(true)
        phase = .ready
        publishKeyboardSnapshot()
        if pendingHandoff != nil {
            activateWarmSessionAndRunHandoff()
        }
    }

    /// Ends a preparation that has said nothing new for too long, in plain words with Try
    /// again, instead of a bar that never moves: `firstReport` (30 s) before it has said
    /// anything (Apple's speech service or asset store not answering leaves "Checking model
    /// files" up for good, Hex TestFlight build 126), `stall` (120 s) after. Time while iOS had
    /// Typr suspended doesn't count. The work it ends can't always be cancelled (an XPC call
    /// that never returns); its result is dropped, and Try again starts a new one without
    /// waiting for it. Downloaded engines keep Typr's background preparation instead.
    private func watchPreparation(_ prepGen: UInt64) {
        preparationChangedAt = .now
        preparationReported = false
        Task { [weak self] in
            let clock = ContinuousClock()
            var polled = clock.now
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.modelPrepGeneration == prepGen, self.phase == .preparingModel else { return }
                let now = clock.now
                if now - polled > .seconds(5) {
                    self.preparationChangedAt = now
                }
                polled = now
                let limit = self.preparationReported ? self.preparationLimits.stall : self.preparationLimits.firstReport
                guard now - self.preparationChangedAt >= limit else { continue }
                self.modelPrepGeneration &+= 1
                self.preparationTask?.cancel()
                self.preparationTask = nil
                let message = "The speech model isn't ready. Try again."
                if let working = self.workingEngine {
                    self.restore(working, because: message)
                    return
                }
                self.pendingHandoff = nil
                self.keyboardBridge.setModelInstalled(ParakeetTranscriber.hasCachedModel)
                self.phase = .failed(message)
                self.publishKeyboardSnapshot()
                return
            }
        }
    }

    nonisolated static func switchNotice(for error: any Error) -> String? {
        if let unavailable = error as? SpeechModelUnavailable, unavailable.switchedAutomatically {
            return unavailable.errorDescription
        }
        if (error as? ParakeetTranscriber.TranscriberError) == .notEnoughMemory {
            return "Not enough memory for the speech model. Typr is using Apple's on-device speech recognition."
        }
        return nil
    }

    nonisolated static func isDownloadInterruption(_ error: any Error) -> Bool {
        if error is StallWatch.Stalled || error is URLError { return true }
        return (error as? ParakeetTranscriber.TranscriberError) == .downloadFailed
    }
}
