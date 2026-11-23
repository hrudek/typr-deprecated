import AVFAudio
import Foundation
import Observation
import Speech
import SwiftUI
import UIKit

@MainActor
@Observable
final class DictationController {
    static let shared = DictationController(
        autoPrepareOnInit: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        cleanup: TranscriptCleanupProduction.dependencies(),
        appleIntelligenceCleaner: AppleIntelligenceCleaner(),
        dictationLog: .shared,
        statistics: UsageDictationRecorder(store: UsageStatisticsStore()),
        liveActivity: LiveActivityCoordinator(),
        modelBackground: ModelBackgroundPreparation.shared,
        deferPreparationUntilActive: true
    )

    private static let minCaptureDuration: TimeInterval = 0.30
    private static let maxCaptureDuration: TimeInterval = 60.0
    private static let resultDeliveryTTL: TimeInterval = 30.0
    nonisolated static let armedCaptureLifetime: TimeInterval = 1.5
    /// Typr audio activation retries: waits before each further microphone activation attempt.
    /// After another app ends an audio interruption (observed: WhatsApp voice messages), iOS
    /// refuses Typr's activation for about five seconds ("Cannot start playing"); later attempts
    /// succeed. About 5.5 s in total. Off, like Hex, one attempt.
    nonisolated static let audioActivationRetryDelays: [Duration] = [
        .milliseconds(500), .seconds(1), .milliseconds(1500), .milliseconds(2500),
    ]
    nonisolated static let audioBusyMessage = "Another app is still using audio. Try again in a moment."

    enum Phase: Equatable {
        case modelRequired
        case preparingModel
        case ready
        case requestingPermission
        case recording
        case transcribing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparingModel, .requestingPermission, .transcribing:
                true
            default:
                false
            }
        }

        var isFailure: Bool {
            if case .failed = self { true } else { false }
        }
    }

    enum AutoReturnState: Equatable {
        case idle
        case attempting
        case succeeded
        case swipeFallback
    }

    struct ActiveCaptureSession {
        let statisticsToken: UsageCaptureToken?
        let generation: UInt64
        let capture: any ActiveAudioCapture
        let startedAt: TimeInterval
        let keyboardJobID: String?
        let style: DictationStyle
        let vocabularyTerms: [String]
        /// Speech hints (Custom vocabulary + built-in glossary).
        let vocabulary: DictationVocabulary
        let vocabularyEnabled: Bool
        let typrCleanupEnabled: Bool
        let appleIntelligenceCleanup: Bool
        /// Spelling, Clean up what I say and formatting, frozen at start.
        let pipeline: DictationPipeline
        let copyToPasteboard: Bool
        let cleanupJob: CleanupJob?
        let cleanupSkipReason: CleanupSkipReason?
        let logToken: DictationLogToken?
        let logCleanupPath: DictationLogCleanupPath
        /// Dictation language, host app and data-only caret text for Typr cleanup, frozen at start.
        let cleanupContext: CleanupContext
        /// The engine and language this capture is transcribed with, frozen at start: a later
        /// engine or language change applies to the next dictation only.
        let transcriber: any LocalTranscribing
        let language: DictationLanguage
        let speechLanguageName: String
        /// Translate what I say, frozen at start; nil inserts as spoken.
        let translation: DictationTranslationPlan?
    }

    struct PendingKeyboardHandoff {
        let jobID: String?
        let style: DictationStyle
        let requestedAt: TimeInterval
        let attemptAutoReturn: Bool
    }

    var transcriber: any LocalTranscribing
    /// Test seam for the automatic (no engine chosen) path; nil uses the provider's automatic choice.
    let transcriberFactory: (() async -> any LocalTranscribing)?
    let engineProvider: any SpeechEngineProviding
    let modelBackground: (any ModelPreparationScheduling)?
    private var deferredLaunchPreparation: Bool
    private let customVocabularySettings: CustomVocabularySettings
    private let dictationLearning: DictationLearningStore
    private let audio: any AudioManaging
    let keyboardBridge: KeyboardBridge
    private let fileManager: FileManager
    let now: () -> TimeInterval
    private let liveActivity: (any LiveActivityPresenting)?
    let hostReturner: HostReturner
    /// The app the current cold-start handoff came from, by bundle ID; nil when the keyboard could not name it.
    var returnHost: String?

    let cleanup: TranscriptCleanupDependencies?
    private let appleIntelligenceCleaner: (any TranscriptCleaning)?
    private let transcriptionBackground: any BackgroundTaskStarting
    private let cleanupCoordinator = CleanupCoordinator()
    let statistics: UsageDictationRecorder?
    let languageSettings: TyprSettings
    private let translationSettings: DictationTranslationSettings
    /// Apple's translation when nil (`DictationTranslationPlan.translate`).
    private let translationEngine: TranslationEngine?
    var pendingCleanupJob: CleanupJob?
    private var transcriptionHeartbeat: Task<Void, Never>?
    private let dictationLog: DictationLogStore?
    var transcribingLog: DictationLogRecording?
    @ObservationIgnored private var loudestAverageDBFS: Float?

    private func endCleanupJob() {
        if let job = pendingCleanupJob {
            cleanupCoordinator.cancel(job.id)
            job.finish()
        }
        pendingCleanupJob = nil
        transcriptionHeartbeat?.cancel()
        transcriptionHeartbeat = nil
    }

    private var jobGeneration: UInt64 = 0
    var modelPrepGeneration: UInt64 = 0
    @ObservationIgnored var preparationTask: Task<Void, Never>?
    var activeCapture: ActiveCaptureSession?
    private struct ArmedCapture {
        let jobID: String
        let capture: any ArmedAudioCapture
        let armedAt: TimeInterval
    }
    private var armedCapture: ArmedCapture?
    /// Latched before audio activation: once interrupted, other audio may report false.
    private var releaseAudioAfterCapture = false
    private var meterTask: Task<Void, Never>?
    var transcriptionTask: Task<Void, Never>?
    // Cancellation is cooperative: an old task can still own a model after the UI returns to
    // ready. Keep a fence until its actual completion, including tasks superseded by a capture.
    var inFlightTranscriptions: Set<UUID> = []
    var inFlightPermissionRequests = 0
    var pendingAppleLanguageChange = false
    private var keyboardSessionTask: Task<Void, Never>?
    var autoReturnFallbackTask: Task<Void, Never>?

    private var lastKeyboardCommandID: String?
    private var lastHandledLaunchJobID: String?
    private var activeKeyboardJobID: String?
    private var keyboardResultID: String?
    private var keyboardFeedbackOffer: DictationFeedbackOffer?
    private var keyboardResultExpiresAt: TimeInterval?
    private var keyboardResult: String?
    private var keyboardResultTranslationFailure: TranslationFailure?
    private var keyboardResultTranslated = false
    private var keyboardMessage: String?
    var pendingHandoff: PendingKeyboardHandoff?
    var keyboardSessionExpiresAt: TimeInterval = 0
    private var suspendedWarmSessionOnInterruption = false
    /// Each warm-loop restart of a keepalive that stopped by itself reopens the microphone under
    /// every app recording at the time, so one that stops again soon waits 1 s, 2 s, … 30 s
    /// instead of 100 ms; one that ran a while restarts at once (anomalyco/hex #2160).
    @ObservationIgnored private var keepaliveRestartedAt = -TimeInterval.infinity
    @ObservationIgnored private var keepaliveRestartDelay: TimeInterval = 0
    @ObservationIgnored private(set) var keepaliveRestartDue: TimeInterval?
    static let steadyKeepalive: TimeInterval = 10
    private static let maxKeepaliveRestartDelay: TimeInterval = 30
    @ObservationIgnored private var interruptionResumeTask: Task<Void, Never>?
    /// Between `.interruptionBegan` and `.interruptionEnded`, independent of a pending resume.
    private var interruptionInProgress = false
    private var warmSessionInterrupted = false
    private let audioRetryDelays: [Duration]
    /// Set when a transcription failed in a way that may come from the engine itself. Other
    /// failures (microphone, silence) keep the prepared model for the next dictation.
    var modelNeedsReload = false

    var phase = Phase.modelRequired
    var isModelReady = false
    var transcript = ""
    private(set) var lastLoggedTranscriptID: UUID?
    /// Why `transcript` went in as spoken although Translate what I say was on.
    private(set) var translationFailure: TranslationFailure?
    @ObservationIgnored var audioLevel: Float = 0
    @ObservationIgnored var loudnessDB: Float = -120
    @ObservationIgnored private var rawRecordingDuration: TimeInterval = 0
    private(set) var recordingWholeSeconds: Int = 0
    var recordingDuration: TimeInterval {
        get { rawRecordingDuration }
        set {
            rawRecordingDuration = newValue
            let whole = max(0, Int(newValue))
            if recordingWholeSeconds != whole {
                recordingWholeSeconds = whole
            }
        }
    }
    var copied = false
    var keyboardSessionEnabled = false {
        didSet { if !keyboardSessionEnabled { warmSessionInterrupted = false } }
    }
    @ObservationIgnored private var rawKeyboardSessionRemaining: TimeInterval = 0
    private(set) var keyboardSessionDisplayRemaining = "0:00"
    var keyboardSessionRemaining: TimeInterval {
        get { rawKeyboardSessionRemaining }
        set {
            rawKeyboardSessionRemaining = newValue
            let formatted = TyprTheme.formatRemaining(newValue)
            if keyboardSessionDisplayRemaining != formatted {
                keyboardSessionDisplayRemaining = formatted
            }
        }
    }
    @ObservationIgnored private var lastPublishedSnapshotSignature: String?
    @ObservationIgnored private var lastPublishedSnapshotAt: TimeInterval = -100
    var warmDuration: WarmSessionDuration
    private(set) var style: DictationStyle
    var microphone: MicrophoneChoice
    var autoReturnState: AutoReturnState = .idle
    private(set) var handoffNotice: String?
    var engineName = "Local speech"
    var transcriptionLanguage = "English"
    /// The language the next dictation uses (`LanguageSettings.typrDictationLanguage`): on
    /// Automatic it follows the keyboard between German and English.
    private(set) var dictationLanguage: DictationLanguage
    /// Settings › Language's choice.
    private(set) var dictationLanguageChoice: DictationLanguage
    let hexLanguageSettings: LanguageSettings
    /// The iPhone's languages, which Automatic dictates in without a keyboard to follow.
    let preferredLanguages: () -> [String]
    /// The engine the user explicitly chose (persisted). nil: never chosen, the original
    /// automatic choice applies. An explicit engine is never replaced by another one.
    var preferredEngine: SpeechEngineChoice?
    /// The engine of the ready transcriber; nil while none is ready or while switching.
    var currentEngine: SpeechEngineChoice?
    var isDeletingModel = false
    /// Every candidate still inside `prepare`, by its preparation generation, including one a
    /// timeout dropped: a Core ML load can't be interrupted, so deletion waits for each.
    @ObservationIgnored var loadingEngines: [UInt64: SpeechEngineChoice] = [:] {
        didSet {
            let waiters = loadFinishedWaiters
            loadFinishedWaiters = []
            waiters.forEach { $0.resume() }
        }
    }
    /// Parakeet Ultra loads still inside `prepare`, by preparation generation: turning the
    /// experiment off deletes its files only once each returned.
    @ObservationIgnored var multilingualLoads: Set<UInt64> = [] {
        didSet {
            let waiters = loadFinishedWaiters
            loadFinishedWaiters = []
            waiters.forEach { $0.resume() }
        }
    }
    @ObservationIgnored var multilingualRemovalGeneration: UInt64 = 0
    @ObservationIgnored var loadFinishedWaiters: [CheckedContinuation<Void, Never>] = []
    /// Experimental › Hex experiments › Multilingual model (Parakeet): its download, beside the
    /// engine Typr dictates with meanwhile.
    @ObservationIgnored let multilingualDownload: ParakeetUltraDownload
    @ObservationIgnored var deletionWaitsForTesting = 0
    var modelPreparation = ModelPreparationProgress(
        fractionCompleted: 0,
        detail: "Checking model files"
    )
    /// Why the engine Typr picked by itself changed or stayed: Automatic moved on from a
    /// language this iPhone can't dictate yet, Parakeet had no room, or a new guess failed and
    /// the engine that worked keeps dictating.
    var languageNotice: String?
    @ObservationIgnored var isInBackground = false
    @ObservationIgnored var preparationFailedInBackground = false
    @ObservationIgnored var preparationChangedAt = ContinuousClock.now
    @ObservationIgnored var preparationReported = false
    @ObservationIgnored var preparationLimits = (firstReport: Duration.seconds(30), stall: Duration.seconds(120))
    /// The engine Typr picked by itself that dictated before the automatic preparation now
    /// running; it comes back when that preparation fails (Hex #2371: a failed guess never
    /// takes away a working engine).
    @ObservationIgnored var workingEngine: WorkingEngine?

    init(
        audio: (any AudioManaging)? = nil,
        keyboardBridge: KeyboardBridge? = nil,
        transcriber: (any LocalTranscribing)? = nil,
        transcriberFactory: (() async -> any LocalTranscribing)? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        autoPrepareOnInit: Bool = true,
        hostReturner: HostReturner? = nil,
        customVocabularySettings: CustomVocabularySettings = CustomVocabularySettings(),
        dictationLearning: DictationLearningStore = DictationLearningStore(),
        cleanup: TranscriptCleanupDependencies? = nil,
        appleIntelligenceCleaner: (any TranscriptCleaning)? = nil,
        transcriptionBackground: (any BackgroundTaskStarting)? = nil,
        dictationLog: DictationLogStore? = nil,
        statistics: UsageDictationRecorder? = nil,
        liveActivity: (any LiveActivityPresenting)? = nil,
        languageSettings: TyprSettings = TyprSettings(),
        hexLanguageSettings: LanguageSettings? = nil,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages },
        engineProvider: (any SpeechEngineProviding)? = nil,
        audioActivationRetryDelays: [Duration] = DictationController.audioActivationRetryDelays,
        modelBackground: (any ModelPreparationScheduling)? = nil,
        deferPreparationUntilActive: Bool = false,
        translationSettings: DictationTranslationSettings = DictationTranslationSettings(),
        translationEngine: TranslationEngine? = nil,
        multilingualDownload: ParakeetUltraDownload? = nil
    ) {
        self.translationSettings = translationSettings
        self.translationEngine = translationEngine
        self.multilingualDownload = multilingualDownload ?? ParakeetUltraDownload()
        self.audioRetryDelays = audioActivationRetryDelays
        let resolvedBridge = keyboardBridge ?? KeyboardBridge()
        let resolvedAudio = audio ?? SystemAudioManager(exclusiveSession: { languageSettings[experiment: .typrExclusiveAudioSession] })
        let initialTranscriber = transcriber ?? ParakeetTranscriber()
        let resolvedProvider = engineProvider ?? ProductionSpeechEngineProvider()
        let preferred = languageSettings.preferredSpeechEngine

        self.cleanup = cleanup
        self.appleIntelligenceCleaner = appleIntelligenceCleaner
        self.transcriptionBackground = transcriptionBackground ?? SystemBackgroundTasks(name: "Transcription")
        self.dictationLog = dictationLog
        self.statistics = statistics
        self.liveActivity = liveActivity
        self.languageSettings = languageSettings
        let hexLanguage = hexLanguageSettings ?? languageSettings.hexLanguage
        self.preferredLanguages = preferredLanguages
        self.hexLanguageSettings = hexLanguage
        self.dictationLanguage = hexLanguage.typrDictationLanguage(typr: languageSettings)
        self.dictationLanguageChoice = hexLanguage.typrDictationChoice(typr: languageSettings)
        self.audio = resolvedAudio
        self.keyboardBridge = resolvedBridge
        self.transcriber = initialTranscriber
        self.transcriberFactory = transcriberFactory
        self.engineProvider = resolvedProvider
        self.modelBackground = modelBackground
        self.deferredLaunchPreparation = autoPrepareOnInit && deferPreparationUntilActive
        self.preferredEngine = preferred
        self.customVocabularySettings = customVocabularySettings
        self.dictationLearning = dictationLearning
        self.fileManager = fileManager
        self.now = now
        self.warmDuration = resolvedBridge.warmDuration
        self.style = resolvedBridge.style
        self.microphone = resolvedBridge.microphone
        self.hostReturner = hostReturner ?? .live

        let hasCachedModel = ParakeetTranscriber.hasCachedModel
        resolvedBridge.publish(.offline)
        // The keyboard's flag follows the selected engine; no choice keeps the original Parakeet check.
        resolvedBridge.setModelInstalled(preferred.map { resolvedProvider.isInstalled($0) } ?? hasCachedModel)
        if let preferred {
            engineName = preferred.displayName
        }

        wireAudioCallbacks()
        wireSystemIntentBus()
        self.multilingualDownload.onDownloaded = { [weak self] in
            self?.syncMultilingualParakeet()
        }
        if autoPrepareOnInit {
            liveActivity?.endImmediately()
        }

        if Self.applyLaunchFixtureIfPresent(to: self) {
            return
        }

        if autoPrepareOnInit, !deferPreparationUntilActive {
            prepareLaunchModel()
        }
    }

    var isRecording: Bool {
        phase == .recording
    }

    var primaryTitle: String {
        switch phase {
        case .modelRequired, .failed:
            "Prepare \(engineName)"
        case .preparingModel:
            "Preparing \(engineName)"
        case .ready:
            "Start dictation"
        case .requestingPermission:
            "Checking microphone"
        case .recording:
            "Finish"
        case .transcribing:
            "Transcribing…"
        }
    }

    // MARK: - Settings

    func setWarmDuration(_ duration: WarmSessionDuration) {
        warmDuration = duration
        keyboardBridge.warmDuration = duration

        if keyboardSessionEnabled {
            if let seconds = duration.seconds {
                keyboardSessionExpiresAt = now() + seconds
                keyboardSessionRemaining = seconds
                publishKeyboardSnapshot()
            } else if phase == .ready {
                endWarmSession()
            }
        }
    }

    /// Used by the settings segmented control: picking a duration warms immediately; picking Off ends it.
    func selectWarmDuration(_ duration: WarmSessionDuration) {
        setWarmDuration(duration)
        if duration == .off {
            if keyboardSessionEnabled {
                endWarmSession()
            }
        } else if !keyboardSessionEnabled {
            requestWarmSession(attemptAutoReturn: false)
        }
    }

    func setStyle(_ newStyle: DictationStyle) {
        style = newStyle
        keyboardBridge.style = newStyle
    }

    /// The language picker: stored for the next recording.
    func setDictationLanguage(_ language: DictationLanguage) {
        hexLanguageSettings.chooseTyprDictationLanguage(language, typr: languageSettings)
        followDictationLanguage()
    }

    /// Reads the choice and the keyboard's language again. Apple Speech holds one locale, so an
    /// idle, prepared Apple Speech engine is prepared again for a new language; otherwise the
    /// next preparation (relaunch, retry) uses it.
    func followDictationLanguage() {
        dictationLanguageChoice = hexLanguageSettings.typrDictationChoice(typr: languageSettings)
        let language = hexLanguageSettings.typrDictationLanguage(typr: languageSettings)
        guard language != dictationLanguage else { return }
        dictationLanguage = language
        languageNotice = nil
        // Apple Speech prepares one locale. Do not mutate the current capture; reprepare when
        // idle, including after a cancelled inference has really released its snapshot.
        if preferredEngine == .appleSpeech || transcriber.displayName == "Apple Speech" || engineName == "Apple Speech"
            || engineName == ParakeetUltraTranscriber.name {
            pendingAppleLanguageChange = true
            preparePendingAppleLanguageIfIdle()
        }
        if MultilingualParakeetSettings().isEnabled {
            syncMultilingualParakeet()
        }
    }

    func preparePendingAppleLanguageIfIdle() {
        guard pendingAppleLanguageChange, canChangeEngine, phase != .preparingModel else { return }
        prepareModel()
    }

    // MARK: - Standalone & System Actions

    func performPrimaryAction() {
        switch phase {
        case .modelRequired, .failed:
            prepareModel()
        case .ready:
            startRecording(copyToPasteboard: false)
        case .recording:
            finishRecording()
        case .preparingModel, .requestingPermission, .transcribing:
            break
        }
    }

    func cancelCurrentJob() {
        discardArmedCapture()
        transcribingLog?.finishIfOpen(.cancelled)
        transcribingLog = nil
        endCleanupJob()
        jobGeneration &+= 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        liveActivity?.endImmediately()

        if let session = activeCapture {
            activeCapture = nil
            stopMetering()
            session.capture.stop()
            try? fileManager.removeItem(at: session.capture.url)
        }

        if activeKeyboardJobID != nil {
            keyboardMessage = nil
        }
        activeKeyboardJobID = nil
        audioLevel = 0
        loudnessDB = -120
        recordingDuration = 0
        if phase == .recording || phase == .transcribing || phase == .requestingPermission {
            phase = .ready
        }
        restoreAudioAfterCapture()
        publishKeyboardSnapshot()
        preparePendingAppleLanguageIfIdle()
    }

    func clearTranscript() {
        transcript = ""
        translationFailure = nil
        copied = false
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        UIPasteboard.general.string = transcript
        copied = true
    }

    func toggleWarmSession() {
        if keyboardSessionEnabled {
            endWarmSession()
        } else {
            if warmDuration == .off {
                setWarmDuration(.fifteenMinutes)
            }
            requestWarmSession(attemptAutoReturn: false)
        }
    }

    func endWarmSession(message: String? = nil) {
        keyboardSessionTask?.cancel()
        keyboardSessionTask = nil
        pendingHandoff = nil
        suspendedWarmSessionOnInterruption = false
        releaseAudioAfterCapture = false
        discardArmedCapture()

        // Cancel an unaccepted in-progress recording, but preserve any already-accepted transcription!
        if let session = activeCapture {
            endCleanupJob()
            jobGeneration &+= 1
            activeCapture = nil
            stopMetering()
            session.capture.stop()
            try? fileManager.removeItem(at: session.capture.url)
            activeKeyboardJobID = nil
            audioLevel = 0
            loudnessDB = -120
            recordingDuration = 0
            liveActivity?.endImmediately()
            if phase == .recording {
                phase = .ready
            }
        }

        interruptionResumeTask?.cancel()
        interruptionResumeTask = nil
        keyboardSessionEnabled = false
        keyboardSessionRemaining = 0
        keyboardSessionExpiresAt = 0
        keyboardMessage = message

        if phase != .recording {
            audio.deactivateSession()
        }

        publishKeyboardSnapshot()
        preparePendingAppleLanguageIfIdle()
    }

    func endStaleLiveActivities() {
        guard activeCapture == nil, phase != .recording, phase != .transcribing else { return }
        liveActivity?.endImmediately()
    }

    func noteSceneDidBecomeActive() {
        isInBackground = false
        if activeCapture == nil { followDictationLanguage() }
        multilingualDownload.appBecameActive(canRetry: canDownloadMultilingualModel)
        if preparationFailedInBackground {
            // Picks up a download that iOS cut off while Typr was in the background; FluidAudio
            // resumes each file from the bytes it has.
            preparationFailedInBackground = false
            if case .failed = phase, !isModelReady { prepareModel() }
        }
        if deferredLaunchPreparation {
            deferredLaunchPreparation = false
            prepareLaunchModel()
        }
        prepareInstalledModelIfNeeded()
        // A preparation that lost or never got its continued task asks again while active.
        modelBackground?.sceneDidBecomeActive()
        scheduleModelMaintenance()
    }

    func noteSceneDidEnterBackground() {
        isInBackground = true
        multilingualDownload.appMovedToBackground()
        scheduleModelMaintenance()
        autoReturnFallbackTask?.cancel()
        autoReturnFallbackTask = nil
        if case .attempting = autoReturnState {
            autoReturnState = .succeeded
        }
    }

    // MARK: - Keyboard Launch & Auto-Return

    func handleKeyboardLaunch(_ request: KeyboardLaunchRequest) {
        switch request {
        case .setup, .translationSettings: return
        case .startSession, .startRecording: break
        }
        autoReturnFallbackTask?.cancel()
        autoReturnState = .idle
        handoffNotice = nil
        returnHost = request.host

        let currentTime = now()
        if request.isHandoffExpired(at: currentTime) {
            handoffNotice = "Timed out"
            pendingHandoff = PendingKeyboardHandoff(
                jobID: nil,
                style: style,
                requestedAt: currentTime,
                attemptAutoReturn: false
            )
            fulfillPendingHandoffOrPrepare()
            return
        }

        switch request {
        case .setup, .translationSettings:
            break

        case .startSession:
            pendingHandoff = PendingKeyboardHandoff(
                jobID: nil,
                style: style,
                requestedAt: currentTime,
                attemptAutoReturn: true
            )
            fulfillPendingHandoffOrPrepare()

        case .startRecording(let jobID, _, let requestedStyle, _):
            guard !jobID.isEmpty, jobID != lastHandledLaunchJobID else { return }
            lastHandledLaunchJobID = jobID
            if let requestedStyle {
                setStyle(requestedStyle)
            }
            pendingHandoff = PendingKeyboardHandoff(
                jobID: jobID,
                style: requestedStyle ?? style,
                requestedAt: currentTime,
                attemptAutoReturn: true
            )
            fulfillPendingHandoffOrPrepare()
        }
    }

    func fulfillPendingHandoffOrPrepare() {
        guard let handoff = pendingHandoff else { return }

        if now() - handoff.requestedAt > KeyboardLaunchRequest.handoffWindow {
            handoffNotice = "Timed out"
            pendingHandoff = PendingKeyboardHandoff(
                jobID: nil,
                style: handoff.style,
                requestedAt: now(),
                attemptAutoReturn: false
            )
        }

        switch phase {
        case .failed where canReusePreparedModel:
            // A microphone or capture failure leaves the prepared model usable. Reloading it
            // here only made the next dictation wait for preparation again.
            phase = .ready
            activateWarmSessionAndRunHandoff()
        case .modelRequired, .failed:
            prepareModel()
        case .ready:
            activateWarmSessionAndRunHandoff()
        case .preparingModel, .requestingPermission, .recording, .transcribing:
            break
        }
    }

    func requestWarmSession(attemptAutoReturn: Bool) {
        pendingHandoff = PendingKeyboardHandoff(
            jobID: nil,
            style: style,
            requestedAt: now(),
            attemptAutoReturn: attemptAutoReturn
        )
        fulfillPendingHandoffOrPrepare()
    }

    func activateWarmSessionAndRunHandoff() {
        guard phase == .ready else { return }
        let handoff = pendingHandoff
        pendingHandoff = nil

        // If a one-shot recording was requested (`warmDuration == .off` and a jobID is present),
        // go straight into recording and release the mic as soon as capture finishes.
        if warmDuration == .off, let jobID = handoff?.jobID {
            let expired = handoff.map { now() - $0.requestedAt > KeyboardLaunchRequest.handoffWindow } ?? false
            if !expired {
                startRecording(
                    keyboardJobID: jobID,
                    styleOverride: handoff?.style,
                    copyToPasteboard: false,
                    attemptAutoReturnOnStart: handoff?.attemptAutoReturn ?? false
                )
                startKeyboardSessionLoop()
            } else {
                handoffNotice = "Timed out"
                autoReturnState = .swipeFallback
            }
            return
        }

        // A warm-only request must not interrupt media. A fresh dictation below is
        // allowed to interrupt it, but must release the session when capture ends.
        let hasFreshCapture = handoff?.jobID != nil
            && handoff.map { now() - $0.requestedAt <= KeyboardLaunchRequest.handoffWindow } == true
        if otherAudioBlocksMicrophone, !hasFreshCapture {
            endWarmSession()
            handoffNotice = "Media is playing. Start dictation to use the microphone."
            maybeAutoReturnAfterActivation(allowed: handoff?.attemptAutoReturn ?? false)
            return
        }

        if keyboardSessionEnabled, audio.isKeepaliveRunning {
            refreshWarmExpiry()
            if let jobID = handoff?.jobID {
                let expired = handoff.map { now() - $0.requestedAt > KeyboardLaunchRequest.handoffWindow } ?? false
                if !expired {
                    startRecording(
                        keyboardJobID: jobID,
                        styleOverride: handoff?.style,
                        copyToPasteboard: false,
                        attemptAutoReturnOnStart: handoff?.attemptAutoReturn ?? false
                    )
                    return
                } else {
                    handoffNotice = "Timed out"
                }
            }
            maybeAutoReturnAfterActivation(allowed: handoff?.attemptAutoReturn ?? false)
            return
        }

        jobGeneration &+= 1
        let requestGen = jobGeneration
        phase = .requestingPermission
        keyboardMessage = nil
        // This activation replaces a pending resume after an interruption.
        takeOverInterruptionResume()

        Task {
            let granted = await audio.requestPermission()
            guard self.jobGeneration == requestGen else { return }
            guard granted else {
                phase = .failed("Microphone access is off. Allow it in Settings to dictate.")
                publishKeyboardSnapshot()
                return
            }

            // If we also have a fresh recording job, begin capture directly so we don't bounce keepalive -> recorder!
            if let jobID = handoff?.jobID,
               let requestedAt = handoff?.requestedAt,
               self.now() - requestedAt <= KeyboardLaunchRequest.handoffWindow {
                self.enableWarmSessionBookkeeping()
                self.phase = .ready
                self.startKeyboardSessionLoop()
                self.startRecording(
                    keyboardJobID: jobID,
                    styleOverride: handoff?.style,
                    copyToPasteboard: false,
                    attemptAutoReturnOnStart: handoff?.attemptAutoReturn ?? false
                )
                return
            }

            if let jobID = handoff?.jobID, !jobID.isEmpty {
                self.handoffNotice = "Timed out"
            }

            do {
                try await activateAudio(isCurrent: { self.jobGeneration == requestGen }) {
                    try self.startWarmInput()
                }
                noteAudioActivated()
                enableWarmSessionBookkeeping()
                phase = .ready
                startKeyboardSessionLoop()
                publishKeyboardSnapshot()
                maybeAutoReturnAfterActivation(allowed: handoff?.attemptAutoReturn ?? false)
            } catch {
                guard self.jobGeneration == requestGen else { return }
                audio.deactivateSession()
                phase = otherAudioBlocksMicrophone ? .ready : .failed(Self.audioFailureMessage(for: error))
                publishKeyboardSnapshot()
            }
        }
    }

    /// Recheck on every warm start, including route changes and interruption retries.
    /// Never seize the microphone just to keep it warm while media is playing.
    func startWarmInput() throws {
        guard !otherAudioBlocksMicrophone else { throw CancellationError() }
        discardArmedCapture()
        try audio.startKeepalive(microphone: idleMicrophone)
    }

    private var otherAudioBlocksMicrophone: Bool {
        languageSettings[experiment: .typrExclusiveAudioSession] && audio.isOtherAudioPlaying
    }

    private var captureMicrophone: MicrophoneChoice {
        warmSessionInterrupted && microphone == .bluetooth ? .automatic : microphone
    }

    /// Hex's warm session (anomalyco/hex #2179) idles on the iPhone's microphone, so it never
    /// holds a car or headset in call audio between dictations; each dictation moves to its own
    /// input. iOS can't start input in the background, so there a move that needs another input
    /// (a headset, CarPlay or Bluetooth hands-free) fails the dictation. Typr keep selected warm
    /// microphone idles on the chosen one instead.
    private var idleMicrophone: MicrophoneChoice {
        languageSettings[experiment: .typrKeepSelectedWarmMicrophone] ? captureMicrophone : .iPhone
    }

    private func enableWarmSessionBookkeeping() {
        let seconds = warmDuration.seconds ?? (15 * 60)
        keyboardSessionEnabled = true
        keyboardSessionExpiresAt = now() + seconds
        keyboardSessionRemaining = seconds
    }

    private func refreshWarmExpiry() {
        guard keyboardSessionEnabled, let seconds = warmDuration.seconds else { return }
        keyboardSessionExpiresAt = now() + seconds
        keyboardSessionRemaining = seconds
    }

    // MARK: - Capture & Generation-Scoped Transcription

    func startRecording(
        keyboardJobID: String? = nil,
        styleOverride: DictationStyle? = nil,
        copyToPasteboard: Bool = false,
        attemptAutoReturnOnStart: Bool = false,
        keyboardContext: CleanupContext? = nil
    ) {
        guard activeCapture == nil else { return }
        followDictationLanguage()
        // Never begin a new Apple capture with the previous locale. The current capture is
        // unaffected, but the next waits for the deferred local preparation.
        if pendingAppleLanguageChange {
            preparePendingAppleLanguageIfIdle()
            return
        }
        guard isModelReady, phase != .preparingModel, phase != .requestingPermission else { return }
        if let keyboardJobID, keyboardJobID == activeKeyboardJobID {
            return
        }
        let armed: ArmedCapture?
        if let keyboardJobID, armedCapture?.jobID == keyboardJobID, armedCapture?.capture.isRecording == true {
            armed = armedCapture
            armedCapture = nil
        } else {
            armed = nil
            discardArmedCapture()
        }
        activeKeyboardJobID = keyboardJobID
        if keyboardJobID != nil {
            keyboardMessage = nil
        }

        // Bumping generation invalidates any stale winding-down transcription task so it can never
        // overwrite our new capture's phase, job state, or temporary WAV file.
        jobGeneration &+= 1
        let captureGeneration = jobGeneration
        transcribingLog?.finishIfOpen(.cancelled)
        transcribingLog = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        endCleanupJob()
        let captureTranscriber = transcriber
        let captureLanguage = dictationLanguage
        let captureLanguageName = switch SpeechEngineChoice(displayName: captureTranscriber.displayName) {
        case .whisperLargeV3Turbo: WhisperTranscriber.languageName(for: captureLanguage)
        case .parakeetV3: ParakeetV3Transcriber.languageName(for: captureLanguage)
        case .orukeet: OrukeetTranscriber.languageName(for: captureLanguage)
        case .cohereTranscribe: CohereTranscriber.languageName(for: captureLanguage)
        default: transcriptionLanguage
        }
        let effectiveStyle = styleOverride ?? style
        let vocabularyEnabled = customVocabularySettings.isEnabled
        let savedVocabularyTerms = customVocabularySettings.terms
        let vocabularyTerms = vocabularyEnabled ? savedVocabularyTerms : []
        let vocabulary = DictationVocabulary(
            settings: customVocabularySettings,
            learnedFixes: languageSettings[experiment: .learnFromEdits] ? dictationLearning.corrections : []
        )
        let appleIntelligenceCleanup = effectiveStyle != .verbatim
            && languageSettings[experiment: .appleIntelligenceCleanup]
        let typrCleanupEnabled = !appleIntelligenceCleanup && cleanup?.isEnabled() == true
        let logToken = dictationLog?.token()
        let logCleanupPath: DictationLogCleanupPath = effectiveStyle == .verbatim ? .none
            : (appleIntelligenceCleanup ? .upstream : (typrCleanupEnabled ? .typr : .none))
        let cleanupEnabled = typrCleanupEnabled && effectiveStyle != .verbatim
        let pipeline = DictationPipeline(style: effectiveStyle, language: captureLanguage,
                                         vocabulary: vocabulary, settings: languageSettings)
        let translation = DictationTranslationPlan(settings: translationSettings,
                                                   typrPolicy: languageSettings[experiment: .typrTranslationPolicy])
        let disabledCleanupReason: CleanupSkipReason? = !typrCleanupEnabled ? .off : (effectiveStyle == .verbatim ? .verbatim : nil)
        // The keyboard's caret text and host app; a cold start knows only the app it came from.
        var cleanupContext = keyboardContext ?? CleanupContext(application: attemptAutoReturnOnStart ? returnHost : nil)
        cleanupContext.language = captureLanguage

        func begin(_ capture: any ActiveAudioCapture, startedAt: TimeInterval) {
            var cleanupJob: CleanupJob?
            var cleanupSkipReason = disabledCleanupReason
            if cleanupEnabled, let cleanup {
                if cleanup.cleaner.unavailableReason != nil {
                    cleanupSkipReason = .unavailable
                } else if cleanupCoordinator.reservedBy != nil {
                    cleanupSkipReason = .busy
                } else {
                    let job = CleanupJob(session: cleanup.cleaner.makeSession(), background: cleanup.background)
                    cleanupJob = job
                    pendingCleanupJob = job
                    cleanupCoordinator.prewarm(job)
                }
            }
            activeCapture = ActiveCaptureSession(
                statisticsToken: statistics?.beginCapture(),
                generation: captureGeneration,
                capture: capture,
                startedAt: startedAt,
                keyboardJobID: keyboardJobID,
                style: effectiveStyle,
                vocabularyTerms: vocabularyTerms,
                vocabulary: vocabulary,
                vocabularyEnabled: vocabularyEnabled,
                typrCleanupEnabled: typrCleanupEnabled,
                appleIntelligenceCleanup: appleIntelligenceCleanup,
                pipeline: pipeline,
                copyToPasteboard: copyToPasteboard,
                cleanupJob: cleanupJob,
                cleanupSkipReason: cleanupSkipReason,
                logToken: logToken,
                logCleanupPath: logCleanupPath,
                cleanupContext: cleanupContext,
                transcriber: captureTranscriber,
                language: captureLanguage,
                speechLanguageName: captureLanguageName,
                translation: translation
            )
            refreshWarmExpiry()
            audioLevel = 0
            loudnessDB = -120
            loudestAverageDBFS = nil
            recordingDuration = 0
            phase = .recording
            if copyToPasteboard || languageSettings[experiment: .typrLiveActivityForAllDictations] {
                liveActivity?.startRecording(startedAt: Date(timeIntervalSince1970: startedAt))
            }
            startMetering(for: captureGeneration)
            publishKeyboardSnapshot()

            if attemptAutoReturnOnStart {
                maybeAutoReturnAfterActivation(allowed: true)
            }
        }

        copied = false
        if let armed {
            let url = newCaptureURL(for: captureGeneration)
            do {
                begin(try armed.capture.commit(to: url), startedAt: armed.armedAt)
                return
            } catch {
                armed.capture.stop()
                try? fileManager.removeItem(at: url)
            }
        }

        phase = .requestingPermission
        // The capture starts the input itself. A resume still retrying after an interruption
        // must not restart (stop) the input under it later.
        takeOverInterruptionResume()

        inFlightPermissionRequests += 1
        Task {
            defer {
                self.inFlightPermissionRequests -= 1
                self.preparePendingAppleLanguageIfIdle()
            }
            let granted = await audio.requestPermission()
            guard self.jobGeneration == captureGeneration else { return }
            guard granted else {
                activeKeyboardJobID = nil
                let message = "Microphone access is off. Allow it in Settings."
                keyboardMessage = keyboardJobID == nil ? nil : message
                phase = .failed(message)
                publishKeyboardSnapshot()
                return
            }

            let captureURL = newCaptureURL(for: captureGeneration)

            do {
                let capture = try await activateAudio(isCurrent: { self.jobGeneration == captureGeneration }) {
                    // Read before activating: activation itself pauses other audio. OR
                    // across retries so a partial activation cannot erase that decision.
                    self.releaseAudioAfterCapture = self.releaseAudioAfterCapture || self.otherAudioBlocksMicrophone
                    return try self.audio.beginCapture(
                        at: captureURL,
                        maxDuration: Self.maxCaptureDuration,
                        microphone: self.captureMicrophone
                    )
                }
                guard self.jobGeneration == captureGeneration else {
                    capture.stop()
                    try? fileManager.removeItem(at: captureURL)
                    return
                }
                noteAudioActivated()
                begin(capture, startedAt: now())
            } catch {
                try? fileManager.removeItem(at: captureURL)
                guard self.jobGeneration == captureGeneration else { return }
                let message = Self.audioFailureMessage(for: error)
                activeKeyboardJobID = nil
                keyboardMessage = keyboardJobID == nil ? nil : message
                phase = .failed(message)
                restoreAudioAfterCapture()
                publishKeyboardSnapshot()
            }
        }
    }

    func finishRecording() {
        guard let session = activeCapture else { return }
        let stoppedAt = ContinuousClock.now
        activeCapture = nil

        stopMetering()
        let finalDuration = max(recordingDuration, session.capture.currentTime)
        session.capture.stop()
        if session.capture.didFailWriting {
            activeCapture = session
            failRecording()
            return
        }
        audioLevel = 0
        loudnessDB = -120

        let captureURL = session.capture.url
        let captureGeneration = session.generation
        let keyboardJobID = session.keyboardJobID

        guard finalDuration >= Self.minCaptureDuration else {
            endCleanupJob()
            try? fileManager.removeItem(at: captureURL)
            recordingDuration = 0
            activeKeyboardJobID = nil
            keyboardMessage = nil
            phase = .ready
            liveActivity?.endImmediately()
            restoreAudioAfterCapture()
            publishKeyboardSnapshot()
            return
        }

        let recording = session.logToken.flatMap { token in
            dictationLog?.begin(token: token, context: .capture(
                keyboardJob: keyboardJobID != nil, copyToPasteboard: session.copyToPasteboard,
                style: session.style, engine: session.transcriber.displayName, language: session.speechLanguageName,
                duration: finalDuration, loudestAverage: loudestAverageDBFS,
                cleanupPath: session.logCleanupPath, vocabularyCount: session.vocabularyTerms.count,
                vocabularyEnabled: session.vocabularyEnabled,
                upstreamCleanupEnabled: session.appleIntelligenceCleanup,
                typrCleanupEnabled: session.typrCleanupEnabled,
                cleanupContext: session.cleanupContext),
                stoppedAt: stoppedAt)
        }
        transcribingLog = recording
        phase = .transcribing
        // The microphone closes below, and with it the audio background mode: without background
        // time iOS can suspend Typr mid-transcription (One shot, back in the host app), so the
        // keyboard never gets the text (Hex #2163).
        let backgroundTime = BackgroundLease(transcriptionBackground)
        session.cleanupJob?.begin()
        transcriptionHeartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.jobGeneration == captureGeneration, self.phase == .transcribing else { return }
                self.publishKeyboardSnapshot()
            }
        }
        liveActivity?.markTranscribing(startedAt: Date(timeIntervalSince1970: session.startedAt))
        restoreAudioAfterCapture()
        publishKeyboardSnapshot()

        let activeTranscriber = session.transcriber

        transcriptionTask?.cancel()
        let inferenceID = UUID()
        inFlightTranscriptions.insert(inferenceID)
        let task = Task { [weak self] in
            let asrStarted = ContinuousClock.now
            defer {
                recording?.finishIfOpen(.cancelled) // Also outside the generation fence: stale tasks terminate their own entry.
                try? FileManager.default.removeItem(at: captureURL)
                session.cleanupJob?.finish()
                backgroundTime.end()
                if let self, self.jobGeneration == captureGeneration {
                    self.transcribingLog = nil
                    self.endCleanupJob()
                }
            }

            do {
                let rawText = try await activeTranscriber.transcribe(
                    captureURL,
                    vocabulary: session.vocabulary.speechHints,
                    language: session.language
                )
                guard let self, self.jobGeneration == captureGeneration, !Task.isCancelled else {
                    return
                }
                // Spelling (Custom vocabulary, then the built-in tech glossary) runs before
                // optional cleanup so cleanup sees the intended words, then the user's terms
                // again after formatting because a style can lowercase a term or capitalize a
                // sentence start ("iPhone" -> "IPhone").
                let asrMilliseconds = dictationLogMilliseconds(from: asrStarted)
                var firstPass = DictationLogSpellingPass()
                let observeFirst: ((String, String, String, DictationVocabulary.Source) -> Void)? = recording == nil ? nil : {
                    before, after, term, source in
                    firstPass.record(before: before, after: after, term: term,
                                     source: source == .builtIn ? source.rawValue : nil)
                }
                var secondPass = DictationLogSpellingPass()
                let observeSecond: ((String, String, String) -> Void)? = recording == nil ? nil : { before, after, term in
                    secondPass.record(before: before, after: after, term: term)
                }
                let cleanup = self.cleanup
                // Off and Verbatim remain synchronous: no prepare, model call, lease or await.
                let skipped: CleanupSkipReason? = cleanup == nil ? nil
                    : (session.cleanupSkipReason == .off || session.cleanupSkipReason == .verbatim
                        ? session.cleanupSkipReason : nil)
                var refine: ((String, [String]) async -> String)?
                if let cleanup, skipped == nil {
                    // Typr AI cleanup is on.
                    refine = { [weak self] text, terms in
                        guard let self else { return text }
                        return await self.cleanupCoordinator.clean(text, job: session.cleanupJob,
                            dependencies: cleanup, skipReason: session.cleanupSkipReason,
                            vocabulary: terms, context: session.cleanupContext, diagnostics: recording)
                    }
                } else if session.appleIntelligenceCleanup, let cleaner = self.appleIntelligenceCleaner {
                    refine = { text, _ in
                        guard cleaner.isAvailable,
                              cleaner.supports(language: session.language.formattingLanguage(for: text)) else { return text }
                        return await cleaner.clean(text) ?? text
                    }
                }
                var translationFailure: TranslationFailure?
                var translated = false
                var translate: ((String) async -> DictationPipeline.Translation)?
                if let plan = session.translation {
                    translate = { [weak self] text in
                        guard let self, self.jobGeneration == captureGeneration, !Task.isCancelled else { return .asSpoken }
                        let outcome = await plan.translate(text, source: session.language,
                                                           settings: self.translationSettings, engine: self.translationEngine)
                        guard self.jobGeneration == captureGeneration, !Task.isCancelled else { return .asSpoken }
                        switch outcome {
                        case .translated(let translation):
                            translated = true
                            return .translated(translation, language: plan.target)
                        case .failed(let failure):
                            translationFailure = failure
                            return .asSpoken
                        case .skipped:
                            return .asSpoken
                        }
                    }
                }
                let stages = await session.pipeline.run(
                    rawText,
                    onSpelling: observeFirst,
                    onSpelled: { [weak self] spelled in
                        recording?.recognized(rawText, spelled: spelled, asrMilliseconds: asrMilliseconds,
                                              spellingPass: firstPass)
                        if !session.appleIntelligenceCleanup, let skipped, let cleanup {
                            self?.cleanupCoordinator.recordSkip(skipped, dependencies: cleanup, diagnostics: recording)
                        }
                    },
                    refine: refine,
                    translate: translate,
                    onRespelling: observeSecond
                )
                guard self.jobGeneration == captureGeneration, !Task.isCancelled else { return }
                recording?.processingStages(cleanupOutput: stages.cleaned, formattedText: stages.styled)
                let beforeSpelling = stages.styled
                let formatted = stages.formatted
                if keyboardJobID != nil, recording != nil {
                    // An offer omitted while the archive loads cannot be added after insertion:
                    // the keyboard deliberately consumes each result exactly once.
                    await self.dictationLog?.waitForFeedbackReadiness()
                    guard self.jobGeneration == captureGeneration, !Task.isCancelled else { return }
                }
                self.statistics?.success(session.statisticsToken, recognized: rawText,
                                         delivered: formatted, seconds: finalDuration)
                recording?.finish(text: formatted, beforeSpelling: beforeSpelling, spellingPass: secondPass)
                self.recordingDuration = 0
                self.transcript = formatted
                self.translationFailure = translationFailure
                // Exact recording correlation, never whichever archive row happens to be latest.
                self.lastLoggedTranscriptID = recording.flatMap { recording in
                    guard let entry = self.dictationLog?.entry(recording.entryID),
                          entry.status == .finished, entry.finalText?.text == DictationLogText(formatted).text else { return nil }
                    return recording.entryID
                }
                if session.copyToPasteboard && !formatted.isEmpty {
                    UIPasteboard.general.string = formatted
                    self.copied = true
                    self.liveActivity?.finishCopied()
                } else {
                    self.liveActivity?.endImmediately()
                }

                if keyboardJobID != nil {
                    self.keyboardResultID = UUID().uuidString
                    self.keyboardResult = formatted
                    self.keyboardResultTranslationFailure = translationFailure
                    self.keyboardResultTranslated = translated
                    self.keyboardResultExpiresAt = self.now() + Self.resultDeliveryTTL
                    if let recording, let resultID = self.keyboardResultID, let keyboardJobID {
                        self.keyboardFeedbackOffer = self.dictationLog?.makeKeyboardFeedbackOffer(
                            recording: recording, jobID: keyboardJobID, resultID: resultID,
                            expiresAt: Date(timeIntervalSince1970: self.now() + 600))
                    }
                    self.keyboardMessage = nil
                }
                self.activeKeyboardJobID = nil
                self.refreshWarmExpiry()
                self.phase = .ready
                self.publishKeyboardSnapshot()
            } catch {
                guard !Task.isCancelled, let self, self.jobGeneration == captureGeneration else {
                    return
                }
                recording?.failASR(error, milliseconds: dictationLogMilliseconds(from: asrStarted))
                if !Self.transcriptionFailureKeepsModel(error) {
                    self.modelNeedsReload = true
                }
                self.recordingDuration = 0
                self.activeKeyboardJobID = nil
                self.liveActivity?.endImmediately()
                self.keyboardMessage = keyboardJobID == nil ? nil : error.localizedDescription
                self.phase = .failed(error.localizedDescription)
                self.publishKeyboardSnapshot()
            }
        }
        transcriptionTask = task
        Task { [weak self] in
            // Waiting outside the inference body matters: its locals (and model snapshot) must
            // be gone before a different engine may allocate a large model.
            await task.value
            guard let self else { return }
            self.inFlightTranscriptions.remove(inferenceID)
            self.preparePendingAppleLanguageIfIdle()
        }
    }

    private func restoreAudioAfterCapture() {
        if releaseAudioAfterCapture || otherAudioBlocksMicrophone {
            // The writer is already stopped. Release before ASR, including short,
            // cancelled and failed captures; do not let the warm loop restart input.
            endWarmSession()
            return
        }
        if keyboardSessionEnabled, let seconds = warmDuration.seconds, seconds > 0 {
            let remaining = keyboardSessionExpiresAt - now()
            if remaining <= 0 {
                keyboardSessionEnabled = false
                keyboardSessionRemaining = 0
                keyboardSessionExpiresAt = 0
                audio.deactivateSession()
                return
            }
            // An interruption stopped the input; `.interruptionEnded` resumes the session.
            guard !suspendedWarmSessionOnInterruption else { return }
            do {
                // The capture recorded from the keepalive input, so it is normally still
                // running. Restarting it here would fail in the background and end the session.
                try audio.ensureKeepalive(microphone: idleMicrophone)
            } catch {
                keyboardSessionEnabled = false
                keyboardSessionRemaining = 0
                keyboardSessionExpiresAt = 0
                keyboardMessage = Self.audioFailureMessage(for: error)
                audio.deactivateSession()
            }
        } else {
            keyboardSessionEnabled = false
            keyboardSessionRemaining = 0
            keyboardSessionExpiresAt = 0
            audio.deactivateSession()
        }
    }

    private func startMetering(for generation: UInt64) {
        stopMetering()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let session = self.activeCapture,
                      session.generation == generation else {
                    break
                }

                // Recorder readiness is a sample, not the capture's lifetime. A transient
                // false must not strand the app meter and keyboard heartbeat until Stop.
                // Completion/interruption callbacks and explicit Stop own capture teardown.
                guard session.capture.isRecording else {
                    try? await Task.sleep(for: .milliseconds(33))
                    continue
                }

                let db = session.capture.averagePowerDB()
                self.loudnessDB = db
                if db.isFinite { self.loudestAverageDBFS = max(self.loudestAverageDBFS ?? db, db) }
                self.audioLevel = max(0, min(1, (db + 48) / 48))
                self.recordingDuration = session.capture.currentTime
                self.publishKeyboardSnapshot(minInterval: 0.10)

                if self.recordingDuration >= Self.maxCaptureDuration - 0.25 {
                    self.finishRecording()
                    return
                }

                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    // MARK: - Warm Session Loop & Snapshot Truth

    private func startKeyboardSessionLoop() {
        keyboardSessionTask?.cancel()
        keepaliveRestartedAt = -.infinity
        keepaliveRestartDelay = 0
        keepaliveRestartDue = nil
        keyboardSessionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.keyboardSessionEnabled || self.activeKeyboardJobID != nil else { return }

                // Never expire an in-flight recording or accepted transcription mid-work.
                if self.keyboardSessionEnabled, self.phase != .recording && self.phase != .transcribing {
                    let remaining = self.keyboardSessionExpiresAt - self.now()
                    if remaining <= 0 {
                        self.endWarmSession()
                        return
                    }
                    self.keyboardSessionRemaining = remaining

                    if self.phase == .ready && self.otherAudioBlocksMicrophone {
                        self.endWarmSession()
                        return
                    }

                    // Verify the keepalive engine is genuinely alive so we never publish a stuck "Ready".
                    if self.audio.isKeepaliveRunning {
                        self.keepaliveRestartDue = nil
                    } else if self.phase == .ready && !self.suspendedWarmSessionOnInterruption,
                              self.keepaliveRestartIsDue() {
                        do {
                            try self.startWarmInput()
                        } catch {
                            self.endWarmSession()
                            return
                        }
                    }
                }

                self.consumeKeyboardCommand()
                if self.phase != .recording {
                    self.publishKeyboardSnapshot(minInterval: 0.60)
                }
                try? await Task.sleep(for: .milliseconds(self.armedCapture == nil ? 100 : 20))
            }
        }
    }

    private func keepaliveRestartIsDue() -> Bool {
        let time = now()
        if keepaliveRestartDue == nil {
            let stoppedSoon = time - keepaliveRestartedAt < Self.steadyKeepalive
            keepaliveRestartDelay = stoppedSoon
                ? min(max(1, keepaliveRestartDelay * 2), Self.maxKeepaliveRestartDelay)
                : 0
            keepaliveRestartDue = time + keepaliveRestartDelay
        }
        guard let due = keepaliveRestartDue, time >= due else { return false }
        keepaliveRestartDue = nil
        keepaliveRestartedAt = time
        return true
    }

    func processPendingKeyboardCommandForTesting() {
        consumeKeyboardCommand()
        publishKeyboardSnapshot()
    }

    func updateRecordingDurationForTesting(_ duration: TimeInterval) {
        recordingDuration = duration
    }

    private func consumeKeyboardCommand() {
        if let armed = armedCapture, now() - armed.armedAt > Self.armedCaptureLifetime {
            discardArmedCapture()
        }
        dictationLog?.drainKeyboardFeedback()
        if activeCapture == nil { followDictationLanguage() }
        guard let command = keyboardBridge.latestCommand(),
              command.id != lastKeyboardCommandID else { return }
        lastKeyboardCommandID = command.id

        // Ignore stale commands left in UserDefaults from >10s ago.
        guard now() - command.sentAt <= KeyboardLaunchRequest.handoffWindow else { return }

        switch command.kind {
        case .arm:
            armCapture(jobID: command.jobID, sentAt: command.sentAt)
        case .start:
            // After a failure the warm input and prepared model can still serve this dictation.
            let canStart = phase == .ready
                || (phase.isFailure && canReusePreparedModel && audio.isKeepaliveRunning)
            guard canStart, activeKeyboardJobID == nil else { return }
            setStyle(command.style)
            startRecording(
                keyboardJobID: command.jobID,
                styleOverride: command.style,
                copyToPasteboard: false,
                keyboardContext: CleanupContext(application: command.host, before: command.context ?? "",
                                                selected: command.selected ?? "", after: command.after ?? "")
            )
        case .stop:
            guard phase == .recording, activeKeyboardJobID == command.jobID else { return }
            finishRecording()
        case .cancel:
            if armedCapture?.jobID == command.jobID {
                discardArmedCapture()
                return
            }
            guard (phase == .recording || phase == .transcribing),
                  activeKeyboardJobID == command.jobID else { return }
            cancelCurrentJob()
        }
    }

    private func armCapture(jobID: String, sentAt: TimeInterval) {
        discardArmedCapture()
        let microphone = captureMicrophone
        guard now() - sentAt <= Self.armedCaptureLifetime,
              keyboardSessionEnabled, phase == .ready, activeCapture == nil, activeKeyboardJobID == nil,
              isModelReady, !pendingAppleLanguageChange, !suspendedWarmSessionOnInterruption,
              !otherAudioBlocksMicrophone, audio.keepaliveFollows(microphone) else { return }
        guard let capture = try? audio.beginArmedCapture(maxDuration: Self.maxCaptureDuration, microphone: microphone)
        else { return }
        armedCapture = ArmedCapture(jobID: jobID, capture: capture, armedAt: now())
    }

    private func failRecording() {
        cancelCurrentJob()
        phase = .failed("Recording stopped unexpectedly.")
        publishKeyboardSnapshot()
    }

    private func discardArmedCapture() {
        armedCapture?.capture.stop()
        armedCapture = nil
    }

    private func newCaptureURL(for generation: UInt64) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("typr-\(generation)-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    func publishKeyboardSnapshot(minInterval: TimeInterval = 0) {
        let currentTime = now()

        if let expires = keyboardResultExpiresAt, expires + KeyboardSnapshot.resultOfferWindow <= currentTime {
            keyboardResultID = nil
            keyboardFeedbackOffer = nil
            keyboardResult = nil
            keyboardResultTranslationFailure = nil
            keyboardResultTranslated = false
            keyboardResultExpiresAt = nil
        }

        let state: KeyboardDictationState
        switch phase {
        case .recording:
            // Hardware truth guard: only claim `.recording` while an active capture is genuinely recording.
            if let session = activeCapture, session.capture.isRecording {
                state = .recording
            } else {
                state = keyboardSessionEnabled ? .ready : .offline
            }
        case .transcribing:
            state = .transcribing
        case .failed:
            state = .failed
        case .modelRequired, .preparingModel, .requestingPermission:
            state = .offline
        case .ready:
            state = (keyboardSessionEnabled && audio.isKeepaliveRunning) ? .ready : .offline
        }

        let failureMessage: String?
        if case .failed(let message) = phase {
            failureMessage = message
        } else {
            failureMessage = keyboardMessage
        }

        let signature = "\(state.rawValue)|\(activeKeyboardJobID ?? "")|\(keyboardResultID ?? "")|\(failureMessage ?? "")"
        if minInterval > 0,
           signature == lastPublishedSnapshotSignature,
           currentTime - lastPublishedSnapshotAt < minInterval {
            return
        }
        lastPublishedSnapshotSignature = signature
        lastPublishedSnapshotAt = currentTime

        let effectiveHeartbeat: TimeInterval
        if state == .recording || state == .transcribing || (keyboardSessionEnabled && audio.isKeepaliveRunning) {
            effectiveHeartbeat = currentTime
        } else {
            effectiveHeartbeat = 0
        }

        keyboardBridge.publish(
            KeyboardSnapshot(
                state: state,
                heartbeat: effectiveHeartbeat,
                expiresAt: keyboardSessionEnabled ? keyboardSessionExpiresAt : 0,
                recordingStartedAt: activeCapture?.startedAt,
                audioLevel: state == .recording ? audioLevel : 0,
                loudnessDB: state == .recording ? loudnessDB : nil,
                jobID: activeKeyboardJobID,
                resultID: keyboardResultID,
                resultExpiresAt: keyboardResultExpiresAt,
                transcript: keyboardResult,
                translationFailure: keyboardResultTranslationFailure,
                translated: keyboardResultTranslated,
                message: failureMessage,
                feedbackOffer: keyboardFeedbackOffer?.resultID == keyboardResultID ? keyboardFeedbackOffer : nil
            )
        )
    }

    // MARK: - Audio Interruptions, Route Changes, & System Intents

    private func wireAudioCallbacks() {
        audio.onUnexpectedCaptureEnd = { [weak self] finishedURL, succeeded in
            guard let self,
                  let session = self.activeCapture,
                  session.capture.url == finishedURL else {
                return
            }
            if succeeded {
                self.finishRecording()
            } else {
                self.failRecording()
            }
        }

        audio.onSystemEvent = { [weak self] event in
            self?.handleAudioSystemEvent(event)
        }
    }

    func handleAudioSystemEvent(_ event: AudioSystemEvent) {
        discardArmedCapture()
        switch event {
        case .interruptionBegan:
            interruptionInProgress = true
            interruptionResumeTask?.cancel()
            interruptionResumeTask = nil
            suspendedWarmSessionOnInterruption = keyboardSessionEnabled
            warmSessionInterrupted = warmSessionInterrupted || keyboardSessionEnabled
            if otherAudioBlocksMicrophone {
                if activeCapture == nil {
                    endWarmSession()
                    return
                }
                releaseAudioAfterCapture = true
            }
            if phase == .recording {
                // Save spoken audio if >= 300ms; otherwise cancel cleanly so "Listening" never sticks during a call.
                if let session = activeCapture, max(recordingDuration, session.capture.currentTime) >= Self.minCaptureDuration {
                    audio.stopKeepalive()
                    finishRecording()
                } else {
                    cancelCurrentJob()
                    keyboardMessage = "Interrupted"
                }
            } else {
                audio.stopKeepalive()
            }
            publishKeyboardSnapshot()

        case .interruptionEnded(let shouldResume):
            interruptionInProgress = false
            guard suspendedWarmSessionOnInterruption else { return }
            if otherAudioBlocksMicrophone {
                endWarmSession()
                return
            }
            guard keyboardSessionEnabled, keyboardSessionExpiresAt > now() else {
                suspendedWarmSessionOnInterruption = false
                endWarmSession()
                return
            }
            if shouldResume || UIApplication.shared.applicationState == .active {
                resumeWarmSessionAfterInterruption()
            } else {
                suspendedWarmSessionOnInterruption = false
                endWarmSession()
            }

        case .routeOldDeviceUnavailable:
            // e.g. AirPods placed in case: finish active speech >= 300ms or rebind keepalive tap to built-in mic.
            if phase == .recording {
                if let session = activeCapture, max(recordingDuration, session.capture.currentTime) >= Self.minCaptureDuration {
                    finishRecording()
                } else {
                    cancelCurrentJob()
                }
            } else if keyboardSessionEnabled && phase == .ready {
                do {
                    try startWarmInput()
                    publishKeyboardSnapshot()
                } catch {
                    endWarmSession()
                }
            }

        case .routeNewDeviceAvailable:
            if keyboardSessionEnabled && phase == .ready && !suspendedWarmSessionOnInterruption
                && !audio.keepaliveFollows(idleMicrophone) {
                do { try startWarmInput() }
                catch { endWarmSession() }
                publishKeyboardSnapshot()
            }

        case .mediaServicesReset:
            if phase == .recording {
                cancelCurrentJob()
            }
            if keyboardSessionEnabled {
                do {
                    try startWarmInput()
                    publishKeyboardSnapshot()
                } catch {
                    endWarmSession()
                }
            }
        }
    }

    /// A keyboard activation or capture now owns the input: stop a pending resume. While the
    /// interruption itself is still running (a call), the session stays suspended so a failed
    /// attempt does not end it and `.interruptionEnded` still resumes it.
    /// Typr's input runs again, so any interruption is over for Typr. iOS does not always send
    /// `.interruptionEnded`; a later one must neither restart this input nor end the session.
    private func noteAudioActivated() {
        interruptionInProgress = false
        suspendedWarmSessionOnInterruption = false
    }

    private func takeOverInterruptionResume() {
        interruptionResumeTask?.cancel()
        interruptionResumeTask = nil
        if !interruptionInProgress {
            suspendedWarmSessionOnInterruption = false
        }
    }

    /// Resumes the warm input after an interruption. The input stays marked as suspended while
    /// iOS still refuses activation, so the session loop does not end the session meanwhile.
    private func resumeWarmSessionAfterInterruption() {
        interruptionResumeTask?.cancel()
        interruptionResumeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.activateAudio(isCurrent: {
                    self.suspendedWarmSessionOnInterruption && self.keyboardSessionEnabled
                        && self.keyboardSessionExpiresAt > self.now()
                        && self.activeCapture == nil
                        && self.phase != .requestingPermission && self.phase != .recording
                }) {
                    try self.startWarmInput()
                }
                self.suspendedWarmSessionOnInterruption = false
                self.interruptionResumeTask = nil
                self.publishKeyboardSnapshot()
            } catch {
                // Cancelled by a new interruption, a keyboard activation or capture, or the
                // session ending. A capture owns the input now; never end its session here.
                guard !Task.isCancelled, self.suspendedWarmSessionOnInterruption,
                      self.activeCapture == nil,
                      self.phase != .requestingPermission, self.phase != .recording else { return }
                self.suspendedWarmSessionOnInterruption = false
                self.interruptionResumeTask = nil
                self.endWarmSession()
            }
        }
    }

    /// Runs one microphone activation, trying again while iOS briefly refuses it after another
    /// app's audio. Stops with `CancellationError` once `isCurrent` turns false.
    private func activateAudio<T>(isCurrent: () -> Bool, _ attempt: () throws -> T) async throws -> T {
        var lastError: (any Error)?
        let retries = languageSettings[experiment: .typrAudioActivationRetries] ? audioRetryDelays : []
        for delay in [Duration.zero] + retries {
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
            guard isCurrent() else { throw CancellationError() }
            do {
                return try attempt()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CancellationError()
    }

    /// AVAudioSession refusals while another app holds audio: cannot start playing ('!pla'),
    /// insufficient priority ('!pri'), cannot interrupt others ('!int').
    nonisolated static func isAudioBusy(_ error: any Error) -> Bool {
        [0x2170_6C61, 0x2170_7269, 0x2169_6E74].contains((error as NSError).code)
    }

    nonisolated static func audioFailureMessage(for error: any Error) -> String {
        isAudioBusy(error) ? audioBusyMessage : error.localizedDescription
    }

    /// Silence and cancellation say nothing about the engine; other failures reload it.
    nonisolated static func transcriptionFailureKeepsModel(_ error: any Error) -> Bool {
        switch DictationLogASRFailure.classify(error) {
        case .noSpeech, .cancelled:
            true
        case .modelNotReady, .other:
            (error as? WhisperTranscriber.TranscriberError) == .emptyTranscript
        }
    }
}
