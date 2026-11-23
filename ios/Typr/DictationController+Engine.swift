import Foundation
import Speech
import os

/// Hex's automatic engine choice (Hex's `DictationController+Engine`), used when no engine is
/// chosen in Typr (`SpeechEngineProviding.automaticTranscriber`). A chosen engine never comes
/// through here, Parakeet Ultra (Hex's multilingual experiment) included.
extension DictationController {
    // MARK: - Which engine dictates (`HexSpeechEnginePolicy`)

    /// The language dictation is meant to be in: the one picked by hand
    /// (`LanguageSettings.explicitDictationLanguage`), else the iPhone's.
    nonisolated static func wantedLanguage(explicit: String?) -> String? {
        explicit ?? Locale.preferredLanguages.first
    }

    /// Hex's `defaultTranscriber`: from iOS 26 Apple Speech where it has the language (English
    /// stays on Parakeet V2 only where `AppleSpeechTranscriber.shouldUse` says so), before it
    /// Parakeet V2 for English where it has room, else Apple's on-device recognizer.
    /// `strict`: Typr strict dictation language.
    static func defaultTranscriber(
        language: DictationLanguage,
        settings: LanguageSettings = LanguageSettings(),
        policy: HexSpeechEnginePolicy = .current,
        strict: Bool = TyprSettings()[experiment: .typrStrictDictationLanguage]
    ) async -> any LocalTranscribing {
        let explicit = settings.explicitDictationLanguage(typr: language)
        guard #available(iOS 26.0, *) else {
            return transcriberBeforeAppleSpeech(policy: policy, explicit: explicit, strict: strict)
        }
        if let speech = await appleSpeechLanguage(
            picked: AppleSpeechTranscriber.preferredLanguage(explicit: explicit, strict: strict),
            wanted: wantedLanguage(explicit: explicit),
            parakeetFits: policy.parakeetFitsBesideAppleSpeech
        ) {
            return AppleSpeechTranscriber(language: speech, automatic: explicit == nil)
        }
        return ParakeetTranscriber()
    }

    /// Before iOS 26: Parakeet or the on-device recognizer (`HexSpeechEnginePolicy`), in the
    /// language the recognizer has on this iPhone, else the one wanted, which then says it
    /// isn't available here.
    nonisolated static func transcriberBeforeAppleSpeech(
        policy: HexSpeechEnginePolicy,
        explicit: String?,
        strict: Bool = false,
        suite: String = KeyboardBridge.appGroup,
        access: SpeechRecognitionAccess = .system,
        resolve: (String?, Bool, LanguageSettings) -> String? = {
            OnDeviceSpeechLanguages.resolve(explicit: $0, strict: $1, settings: $2)
        }
    ) -> any LocalTranscribing {
        let settings = LanguageSettings(defaults: UserDefaults(suiteName: suite))
        let wanted = wantedLanguage(explicit: explicit)
        guard policy.engine(for: wanted, appleSpeechPicks: false) == .onDeviceRecognizer else {
            return ParakeetTranscriber()
        }
        let language = resolve(explicit, strict, settings) ?? wanted ?? "en-US"
        return OnDeviceSpeechTranscriber(language: language, automatic: explicit == nil, access: access, suite: suite)
    }

    /// The language Apple Speech dictates in, or nil for Parakeet V2, which knows only
    /// English: Apple Speech's pick, unless it is English that Parakeet takes
    /// (`AppleSpeechTranscriber.shouldUse`). With no pick (Speech not answering), English goes
    /// to Parakeet only on an iPhone without `SpeechTranscriber`, and any other language
    /// (`wanted`) stays on Apple Speech, which says it can't dictate it rather than Parakeet
    /// hearing Spanish as English words.
    @available(iOS 26.0, *)
    nonisolated static func appleSpeechLanguage(
        picked: SpeechLanguage?,
        wanted: String?,
        parakeetFits: Bool = ParakeetTranscriber.fitsInMemory,
        hasSpeechTranscriber: Bool = SpeechTranscriber.isAvailable,
        appleSetAside: Bool? = nil
    ) -> SpeechLanguage? {
        if let picked {
            return AppleSpeechTranscriber.shouldUse(
                picked,
                parakeetFits: parakeetFits,
                hasSpeechTranscriber: hasSpeechTranscriber,
                appleSetAside: appleSetAside
            ) ? picked : nil
        }
        guard let wanted else { return nil }
        if SpeechLanguagePicker.isEnglish(wanted) {
            let english = SpeechLanguage(locale: Locale(identifier: wanted), module: .speech)
            let setAside = appleSetAside ?? LanguageSettings().isUnavailable(english.identifier)
            guard hasSpeechTranscriber, !setAside else { return nil }
            return english
        }
        return SpeechLanguage(locale: Locale(identifier: wanted), module: .dictation)
    }
}

extension DictationController {
    /// A background-only process launch must not start another engine (or download its assets)
    /// before the scheduler validates the request. Production defers the usual launch behavior
    /// until an active scene; tests can still exercise immediate initialization explicitly.
    func prepareLaunchModel() {
        guard phase == .modelRequired, canChangeEngine else { return }
        let parakeetLoads = ParakeetLoadGuard()
        parakeetLoads.noteLaunch()
        let parakeetInterrupted = parakeetLoads.lastLoadWasInterrupted
        let multilingualTakesOver = prepareMultilingualParakeetAtLaunch()
        if let preferred = preferredEngine {
            // An explicit engine prepares at launch only without downloading: Apple Speech (iOS
            // manages its assets), Parakeet when cached, downloaded engines when verified on disk.
            // Parakeet waits for a tap after loads that ended Typr (`ParakeetLoadGuard`).
            switch preferred {
            case .appleSpeech:
                prepareModel()
            case .parakeetV2:
                if engineProvider.isInstalled(preferred), !parakeetInterrupted {
                    prepareModel()
                }
            case .whisperLargeV3Turbo, .parakeetV3, .orukeet, .cohereTranscribe:
                if engineProvider.isInstalled(preferred) {
                    prepareModel()
                }
            }
        } else if !multilingualTakesOver {
            prepareAutomaticAtLaunch(parakeetInterrupted: parakeetInterrupted)
        }
    }

    /// Experimental › Hex experiments › Multilingual model (Parakeet) at launch: true when
    /// Parakeet Ultra takes the dictation language and loads now, downloaded and compiled for
    /// this iOS (seconds). Otherwise Typr gets ready with the engine it uses without it, and the
    /// download or a first load runs beside it (`syncMultilingualParakeet`). With the
    /// experiment turned off, it only deletes a download turning it off left mid-way.
    private func prepareMultilingualParakeetAtLaunch() -> Bool {
        let loads = ParakeetLoadGuard(model: ParakeetUltraTranscriber.loadGuardModel)
        loads.noteLaunch()
        let settings = MultilingualParakeetSettings()
        guard settings.isEnabled else {
            if settings.isTurnedOff {
                removeMultilingualModel()
            }
            return false
        }
        guard preferredEngine == nil else { return false }
        if !ParakeetUltraModel.isDownloaded() {
            settings.isModelReady = false
        }
        if loads.lastLoadWasInterrupted, multilingualLanguage() != nil {
            settings.isModelReady = false
            multilingualDownload.fail(ParakeetUltraTranscriber.setAsideMessage)
        }
        let language = ParakeetUltraTranscriber.chosenLanguage(language: multilingualLanguage())
        guard let language, Self.multilingualStep(
            language: language,
            downloaded: ParakeetUltraModel.isDownloaded(),
            compiled: ParakeetUltraTranscriber.isCompiled
        ) == .dictate else {
            // A first load waits for the engine Typr gets ready meanwhile (its end syncs).
            startMultilingualDownloadIfWanted()
            return false
        }
        engineName = ParakeetUltraTranscriber.name
        prepareModel(fallbacksLeft: 2, launchUltraLanguage: language)
        return true
    }

    /// What Typr does about Parakeet Ultra: nothing (off, a language it doesn't take, set
    /// aside), download it, load it beside the engine that dictates meanwhile (a first load
    /// compiles for a minute or more), or dictate with it.
    enum MultilingualStep: Equatable {
        case none
        case download
        case loadBeside
        case dictate
    }

    nonisolated static func multilingualStep(language: String?, downloaded: Bool, compiled: Bool) -> MultilingualStep {
        guard language != nil else { return .none }
        guard downloaded else { return .download }
        return compiled ? .dictate : .loadBeside
    }

    func multilingualLanguage() -> String? {
        guard preferredEngine == nil else { return nil }
        let explicit = hexLanguageSettings.explicitDictationLanguage(typr: dictationLanguage)
        return MultilingualParakeetSettings().language(set: explicit, preferred: preferredLanguages())
    }

    var canDownloadMultilingualModel: Bool {
        ParakeetUltraTranscriber.chosenLanguage(language: multilingualLanguage(), availableMemory: 0) != nil
    }

    func startMultilingualDownloadIfWanted() {
        guard canDownloadMultilingualModel, !ParakeetUltraModel.isDownloaded() else { return }
        MultilingualParakeetSettings().isModelReady = false
        multilingualDownload.start()
    }

    func syncMultilingualParakeet(
        availableMemory: UInt64 = UInt64(max(0, os_proc_available_memory())),
        downloaded: Bool = ParakeetUltraModel.isDownloaded()
    ) {
        guard let language = multilingualLanguage() else {
            multilingualDownload.cancel()
            return
        }
        if isModelReady, transcriber is ParakeetUltraTranscriber {
            multilingualDownload.settle()
            return
        }
        guard canDownloadMultilingualModel else { return }
        guard downloaded else {
            startMultilingualDownloadIfWanted()
            return
        }
        guard phase != .preparingModel, multilingualLoads.isEmpty else { return }
        guard ParakeetUltraTranscriber.hasRoomToLoad(available: availableMemory) else {
            multilingualDownload.fail(ParakeetUltraTranscriber.notEnoughMemoryMessage)
            return
        }
        loadMultilingualParakeetBeside(language: language)
    }

    /// Parakeet Ultra loaded: the keyboard opens Typr for its languages from now on.
    func multilingualParakeetLoaded() {
        MultilingualParakeetSettings().isModelReady = true
        multilingualDownload.settle()
    }

    /// Parakeet Ultra didn't load. Missing files download again; anything else sets it aside
    /// (`ParakeetLoadGuard`) until Try again, so Typr doesn't try at every launch.
    func multilingualParakeetFailedToLoad(_ error: any Error) {
        let settings = MultilingualParakeetSettings()
        settings.isModelReady = false
        guard multilingualLanguage() != nil, !(error is CancellationError) else {
            multilingualDownload.settle()
            return
        }
        if (error as? ParakeetUltraTranscriber.TranscriberError) == .notDownloaded {
            multilingualDownload.settle()
            startMultilingualDownloadIfWanted()
            return
        }
        ParakeetLoadGuard(model: ParakeetUltraTranscriber.loadGuardModel).setAside()
        multilingualDownload.fail(Self.switchNotice(for: error) ?? error.localizedDescription)
    }

    /// Try again beside the multilingual model's status: lets a set-aside load try again, and
    /// picks up the download from what's on disk.
    func retryMultilingualParakeet() {
        guard multilingualLanguage() != nil else { return }
        ParakeetLoadGuard(model: ParakeetUltraTranscriber.loadGuardModel).forget()
        multilingualDownload.settle()
        if ParakeetUltraModel.isDownloaded() {
            syncMultilingualParakeet()
        } else {
            MultilingualParakeetSettings().isModelReady = false
            multilingualDownload.restart()
        }
    }

    /// Turn off beside the multilingual model's status, as the switch in Experimental does.
    func turnOffMultilingualParakeet() {
        MultilingualParakeetSettings().isEnabled = false
        multilingualParakeetChanged()
    }

    /// Hex's launch with no engine chosen. A launch after Typr ended while loading Parakeet
    /// doesn't load it again by itself, or it would end the same way at every launch: from
    /// iOS 26 Apple Speech takes over where it has the language, before it the on-device
    /// recognizer always does.
    private func prepareAutomaticAtLaunch(parakeetInterrupted: Bool) {
        let hasCachedModel = ParakeetTranscriber.hasCachedModel
        let policy = HexSpeechEnginePolicy.current
        let explicit = hexLanguageSettings.explicitDictationLanguage(typr: dictationLanguage)
        guard #available(iOS 26.0, *) else {
            switch policy.engine(for: Self.wantedLanguage(explicit: explicit), appleSpeechPicks: false) {
            case .parakeet:
                engineName = "Parakeet V2"
                if hasCachedModel { prepareModel() }
            case .onDeviceRecognizer, .appleSpeech:
                engineName = "Apple Speech"
                if SFSpeechRecognizer.authorizationStatus() == .authorized {
                    keyboardBridge.setModelInstalled(true)
                    prepareModel()
                }
            }
            return
        }
        if hasCachedModel && !parakeetInterrupted {
            engineName = "Parakeet V2"
            prepareModel()
            return
        }
        let launchGeneration = modelPrepGeneration
        let strict = languageSettings[experiment: .typrStrictDictationLanguage]
        Task { [weak self] in
            let speech = await Self.appleSpeechLanguage(
                picked: AppleSpeechTranscriber.preferredLanguage(explicit: explicit, strict: strict),
                wanted: Self.wantedLanguage(explicit: explicit),
                parakeetFits: policy.parakeetFitsBesideAppleSpeech
            )
            guard let self, self.modelPrepGeneration == launchGeneration,
                  self.preferredEngine == nil, self.phase == .modelRequired,
                  self.canChangeEngine else { return }
            if speech != nil {
                self.engineName = "Apple Speech"
                self.prepareModel()
            } else {
                self.engineName = "Parakeet V2"
                if hasCachedModel {
                    self.phase = .failed(ParakeetLoadGuard.message)
                }
            }
        }
    }
}
