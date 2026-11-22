import Foundation
import UIKit

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

    /// `preset`: Parakeet Ultra taking Parakeet V2's place (`replaceParakeetWithMultilingual`).
    func prepareModel(fallbacksLeft: Int, candidate preset: (any LocalTranscribing)? = nil) {
        // This is also called by handoff/intents and tests, not just the settings button.
        guard canChangeEngine else { return }
        pendingAppleLanguageChange = false
        modelNeedsReload = false
        modelPrepGeneration &+= 1
        let prepGen = modelPrepGeneration
        // A load beside the engine this replaces is dropped; the end of this one decides again.
        multilingualDownload.dropLoad()
        startMultilingualDownloadIfWanted()
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
            var candidateIsUltra = false
            do {
                let candidate: any LocalTranscribing
                if let preset {
                    candidate = preset
                } else if let preferred {
                    candidate = try await engineProvider.transcriber(for: preferred, language: language)
                } else if let transcriberFactory {
                    candidate = await transcriberFactory()
                } else {
                    candidate = await engineProvider.automaticTranscriber(language: language)
                }
                guard self.modelPrepGeneration == prepGen else { return }
                candidateIsUltra = candidate is ParakeetUltraTranscriber
                // Two in-process Parakeet models never stay loaded together.
                if candidate is ParakeetTranscriber || candidateIsUltra,
                   self.workingEngine?.transcriber is ParakeetTranscriber
                    || self.workingEngine?.transcriber is ParakeetUltraTranscriber {
                    self.workingEngine = nil
                }
                engineName = candidate.displayName
                loadingEngines[prepGen] = SpeechEngineChoice(displayName: candidate.displayName)
                if candidateIsUltra { multilingualLoads.insert(prepGen) }
                defer {
                    loadingEngines[prepGen] = nil
                    multilingualLoads.remove(prepGen)
                }
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
                if candidateIsUltra {
                    self.multilingualParakeetLoaded()
                }
                self.publishKeyboardSnapshot()
                if self.pendingHandoff != nil {
                    self.activateWarmSessionAndRunHandoff()
                }
                self.syncMultilingualParakeet()
            } catch {
                guard self.modelPrepGeneration == prepGen else { return }
                if candidateIsUltra, fallbacksLeft > 0, !(error is CancellationError) {
                    // Parakeet Ultra didn't load: the engine that dictated before keeps
                    // dictating, else the one Typr picks without it (Hex #2337).
                    self.multilingualParakeetFailedToLoad(error)
                    if let working = self.workingEngine {
                        self.restore(working, because: error.localizedDescription)
                    } else {
                        self.preparationTask = nil
                        self.prepareModel(fallbacksLeft: fallbacksLeft - 1)
                    }
                    return
                }
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
                // A downloaded Parakeet Ultra can still dictate.
                self.syncMultilingualParakeet()
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
        if (error as? ParakeetUltraTranscriber.TranscriberError) == .notEnoughMemory {
            return ParakeetUltraTranscriber.notEnoughMemoryMessage
        }
        return nil
    }

    nonisolated static func isDownloadInterruption(_ error: any Error) -> Bool {
        if error is StallWatch.Stalled || error is URLError { return true }
        return (error as? ParakeetTranscriber.TranscriberError) == .downloadFailed
    }
}

/// Experimental › Hex experiments › Multilingual model (Parakeet) (anomalyco/hex #2197, #2337):
/// Parakeet Ultra downloads and loads beside the engine that dictates meanwhile, so it never
/// takes a working dictation away. Only while no engine is chosen: a chosen engine is never
/// replaced.
extension DictationController {
    /// The switch turned on or off. On, the engine Typr dictates with stays while Parakeet
    /// Ultra downloads and loads beside it; a load that ended Typr gets another try. Off, the
    /// download stops and is deleted once no load of it runs, and Typr prepares the engine it
    /// picks without it if Ultra was the one dictating (now, or once the dictation in flight
    /// is done).
    func multilingualParakeetChanged() {
        let settings = MultilingualParakeetSettings()
        if settings.isEnabled {
            ParakeetLoadGuard(model: ParakeetUltraTranscriber.loadGuardModel).forget()
            multilingualDownload.settle()
            if isModelReady || phase == .preparingModel || preferredEngine != nil {
                syncMultilingualParakeet()
                return
            }
        } else {
            settings.isModelReady = false
            removeMultilingualModel()
            if engineName != ParakeetUltraTranscriber.name, isModelReady || preferredEngine != nil {
                // Ultra wasn't dictating: drop a load of it beside the engine that is.
                if isModelReady { modelPrepGeneration &+= 1 }
                return
            }
        }
        guard canChangeEngine else {
            pendingAppleLanguageChange = true
            return
        }
        prepareModel()
        if !settings.isEnabled, workingEngine?.transcriber is ParakeetUltraTranscriber {
            workingEngine = nil
        }
    }

    /// Stops the download, waits for every load of the model to return (a Core ML load can't
    /// be interrupted), then deletes it, unless the switch was turned on again meanwhile.
    private func removeMultilingualModel() {
        let download = multilingualDownload
        Task {
            await download.stop()
            while !multilingualLoads.isEmpty {
                deletionWaitsForTesting += 1
                await withCheckedContinuation { loadFinishedWaiters.append($0) }
            }
            guard !MultilingualParakeetSettings().isEnabled else { return }
            ParakeetUltraModel.remove()
        }
    }

    /// Parakeet V2 dictates and leaves no room to load Parakeet Ultra beside it (English
    /// before iOS 26): Ultra takes its place and loads as it would at launch, rather than
    /// never getting its first load. False when V2 isn't the engine.
    func replaceParakeetWithMultilingual(language: String) -> Bool {
        guard transcriber is ParakeetTranscriber, phase != .preparingModel, canChangeEngine else { return false }
        prepareModel(fallbacksLeft: 2, candidate: ParakeetUltraTranscriber(language: language))
        return true
    }

    /// Loads Parakeet Ultra while the engine Typr has keeps dictating, and switches to it once
    /// it's loaded; a dictation in flight isn't interrupted. A failure keeps that engine and
    /// says why. Only while no other preparation runs; the next one waits for this load.
    func loadMultilingualParakeetBeside(language: String) {
        guard phase != .preparingModel, preferredEngine == nil else { return }
        modelPrepGeneration &+= 1
        let prepGen = modelPrepGeneration
        multilingualDownload.loading()
        let previous = preparationTask
        multilingualLoads.insert(prepGen)
        let backgroundTime = BackgroundTime("Prepare the multilingual model")
        preparationTask = Task {
            defer {
                backgroundTime.end()
                self.multilingualLoads.remove(prepGen)
            }
            await previous?.value
            guard self.modelPrepGeneration == prepGen else { return }
            let candidate = ParakeetUltraTranscriber(language: language)
            do {
                try await candidate.prepare { _ in }
                let languageName = await candidate.languageName
                guard self.modelPrepGeneration == prepGen, self.preferredEngine == nil else { return }
                self.workingEngine = nil
                self.transcriber = candidate
                self.currentEngine = nil
                self.engineName = candidate.displayName
                self.transcriptionLanguage = languageName
                self.isModelReady = true
                self.keyboardBridge.setModelInstalled(true)
                switch self.phase {
                case .modelRequired, .failed:
                    self.phase = .ready
                default:
                    break
                }
                self.multilingualParakeetLoaded()
                self.publishKeyboardSnapshot()
            } catch {
                guard self.modelPrepGeneration == prepGen else { return }
                self.multilingualParakeetFailedToLoad(error)
            }
        }
    }
}

/// Background time from iOS while Typr finishes the multilingual model's download or load,
/// ended when it's done or when iOS asks for it back (Hex's `BackgroundTime`).
@MainActor
final class BackgroundTime {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
