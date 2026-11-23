import AVFAudio
import Foundation
import os
import Speech
import UIKit
import WebKit

/// Settings > Experimental's in-keyboard dictation, adapted from Hex's KeyboardLocalDictation
/// (anomalyco/hex #1999, #2089, #2045): records inside the keyboard and transcribes with Apple
/// Speech, so a cold Typr key needs no jump to Typr. The keyboard itself may not record, so
/// capture runs in WebKit's media process through getUserMedia under Typr's microphone
/// permission. Audio streams straight into the analyzer and is never written anywhere.
@MainActor
final class KeyboardLocalDictation {
    private var state = KeyboardLocalCapture()
    private var capture: KeyboardWebCapture?
    private var speech: AnyObject?
    private var prepared: (language: DictationLanguage, locale: Locale, format: AVAudioFormat)?
    /// The language whose Apple Speech model was checked (and, if missing, downloaded) in
    /// this keyboard process: checked once, not on every appearance.
    private var checkedLanguage: DictationLanguage?
    /// A capture that could not start (microphone refused, no Apple Speech): Typr dictates
    /// for the rest of this keyboard's life.
    private var unavailable = false
    private var loudness: Float = -62
    private var transcription: Task<Void, Never>?
    /// A kept dictation whose capture failed before any audio: the Typr app takes it.
    var onHandOff: (() -> Void)?

    static var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var isActive: Bool { state.isActive }

    var isArmed: Bool {
        if case .armed = state.phase { return true }
        return false
    }

    func route(enabled: Bool, warm: Bool) -> KeyboardDictationRoute {
        KeyboardDictationRoute.choose(
            keyboardEnabled: enabled && !unavailable,
            warm: warm,
            supported: Self.isSupported,
            speechReady: prepared?.language == TyprSettings().dictationLanguage,
            microphoneAllowed: AVAudioApplication.shared.recordPermission != .denied,
            availableMemory: os_proc_available_memory(),
            captureLoaded: capture != nil
        )
    }

    /// After the keyboard's first frame: loads the capture page (no microphone, no orange dot)
    /// and checks Apple Speech for the dictation language, so the Typr key only has the
    /// microphone left to open.
    func prepare(in host: UIView) {
        guard Self.isSupported, !unavailable, !state.isActive else { return }
        if capture == nil, KeyboardDictationRoute.hasMemory(available: os_proc_available_memory(), captureLoaded: false) {
            let capture = KeyboardWebCapture(host: host)
            listenWhileIdle(capture)
            self.capture = capture
        }
        let language = TyprSettings().dictationLanguage
        guard #available(iOS 26.0, *), checkedLanguage != language else { return }
        checkedLanguage = language
        Task { [weak self] in
            let ready = await KeyboardSpeechStream.prepare(language: language)
            guard let self else { return }
            self.prepared = ready.map { (language, $0.locale, $0.format) }
        }
    }

    /// Memory is short: a page between dictations goes and is made again when needed.
    func releaseIfIdle() {
        guard !state.isActive, let capture else { return }
        self.capture = nil
        capture.tearDown()
    }

    /// The Typr key's touch-down: the microphone opens now, unseen, so the first words are
    /// kept if the touch becomes a hold (`start`).
    func arm(in host: UIView) {
        let jobID = UUID().uuidString
        guard state.arm(jobID: jobID, at: Date().timeIntervalSince1970, translation: Self.translationPlan()) else { return }
        begin(jobID: jobID, in: host)
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardLocalCapture.armedTimeout) { [weak self] in
            guard let self, self.state.expireArmed(jobID: jobID, now: Date().timeIntervalSince1970) else { return }
            self.endCapture()
        }
    }

    /// Keeps an armed capture or starts a new one; false when nothing started.
    func start(in host: UIView) -> Bool {
        switch state.start(jobID: UUID().uuidString, at: Date().timeIntervalSince1970, translation: Self.translationPlan()) {
        case .kept:
            return true
        case .begin(let jobID):
            begin(jobID: jobID, in: host)
            return true
        case .ignored:
            return false
        }
    }

    /// A tap, slide or cancelled touch: the armed capture and its audio are dropped.
    func discard() {
        guard state.discard() != nil else { return }
        endCapture()
    }

    func stop() {
        guard let jobID = state.stop() else { return }
        capture?.stop()
        // The page's last audio arrives with its `stopped`; without one, finish anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.transcribe(jobID) }
    }

    func cancel() {
        guard state.isActive else { return }
        state.cancel()
        endCapture()
    }

    /// Also drops a finished result not yet inserted, so it never lands in the next field.
    func keyboardWillHide() {
        state.cancel()
        endCapture()
    }

    func snapshot(now: TimeInterval) -> KeyboardSnapshot? {
        state.snapshot(now: now, loudnessDB: loudness)
    }

    func delivered(resultID: String) {
        state.delivered(resultID: resultID)
    }

    private func begin(jobID: String, in host: UIView) {
        guard #available(iOS 26.0, *), let prepared,
              let stream = try? KeyboardSpeechStream(locale: prepared.locale, format: prepared.format) else {
            failToStart(jobID, reason: "Apple Speech isn't ready")
            return
        }
        speech = stream
        loudness = -62
        let capture = capture ?? KeyboardWebCapture(host: host)
        self.capture = capture
        capture.onEvent = { [weak self] event in self?.handle(event, jobID: jobID) }
        capture.start()
    }

    private func handle(_ event: KeyboardWebCapture.Event, jobID: String) {
        switch event {
        case .started:
            // A start that ends after its job was dropped closes its microphone at once.
            if !state.isCapturing(jobID) { capture?.stop() }
        case .samples(let data, let rate, let peak):
            guard state.acceptsAudio(jobID), #available(iOS 26.0, *) else { return }
            (speech as? KeyboardSpeechStream)?.append(data, sampleRate: rate)
            loudness = peak > 0 ? max(-62, 20 * log10(peak)) : -62
        case .stopped:
            transcribe(jobID)
        case .failed(let message):
            capture?.stop()
            failToStart(jobID, reason: message)
        case .processTerminated:
            // Hex #2045: a terminated web view leaves the keyboard instead of piling up.
            let ended = capture
            capture = nil
            Task { @MainActor in ended?.tearDown() }
            if state.isCapturing(jobID) { failToStart(jobID, reason: "capture process ended") }
        case .loaded:
            break
        }
    }

    private func listenWhileIdle(_ capture: KeyboardWebCapture) {
        capture.onEvent = { [weak self, weak capture] event in
            guard let self, let capture else { return }
            switch event {
            case .started: capture.stop()
            case .processTerminated:
                if capture === self.capture { self.capture = nil }
                Task { @MainActor in capture.tearDown() }
            default: break
            }
        }
    }

    /// The capture could not run: a kept dictation goes to the Typr app, and so do later ones.
    private func failToStart(_ jobID: String, reason: String) {
        guard state.isCapturing(jobID) else { return }
        Logger(subsystem: "dev.rudek.typr.keyboard", category: "dictation")
            .error("in-keyboard dictation unavailable: \(reason, privacy: .public)")
        unavailable = true
        let kept = !isArmed
        state.cancel()
        endCapture()
        if kept { onHandOff?() }
    }

    private func endCapture() {
        transcription?.cancel()
        transcription = nil
        if let capture {
            listenWhileIdle(capture)
            capture.stop()
        }
        if #available(iOS 26.0, *) { (speech as? KeyboardSpeechStream)?.cancel() }
        speech = nil
    }

    private static func translationPlan() -> DictationTranslationPlan? {
        DictationTranslationPlan(settings: DictationTranslationSettings(),
                                 typrPolicy: TyprSettings()[experiment: .typrTranslationPolicy])
    }

    private func transcribe(_ jobID: String) {
        guard case .transcribing(let current) = state.phase, current == jobID, transcription == nil,
              #available(iOS 26.0, *), let stream = speech as? KeyboardSpeechStream else { return }
        speech = nil
        if let capture { listenWhileIdle(capture) }
        let style = KeyboardBridge().style
        let settings = TyprSettings()
        let translationSettings = DictationTranslationSettings()
        let translation = state.translation
        transcription = Task { [weak self] in
            let heard: String
            do {
                heard = try await stream.finish()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.transcription = nil
                self.state.fail("Apple Speech couldn't transcribe this", now: Date().timeIntervalSince1970)
                return
            }
            guard let self, !Task.isCancelled else { return }
            var outcome = TranslationOutcome.skipped
            let translate: ((String) async -> DictationPipeline.Translation)? = translation.map { plan in
                { text in
                    outcome = await plan.translate(text, source: settings.dictationLanguage, settings: translationSettings)
                    guard !Task.isCancelled, let translated = outcome.text else { return .asSpoken }
                    return .translated(translated, language: plan.target)
                }
            }
            let text = await KeyboardLocalCapture.text(from: heard, style: style, settings: settings, translate: translate)
            guard !Task.isCancelled else { return }
            self.transcription = nil
            self.state.finish(jobID: jobID, transcript: text, resultID: UUID().uuidString, translation: outcome)
        }
    }
}

/// One dictation's Apple Speech analyzer, fed the page's PCM as it arrives.
@available(iOS 26.0, *)
@MainActor
private final class KeyboardSpeechStream {
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let started: Task<Void, Error>
    private let results: Task<String, Error>
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    /// The supported locale for the dictation language (German first when chosen) and its audio
    /// format, once its model is installed; starts the model download once when it isn't.
    static func prepare(language: DictationLanguage) async -> (locale: Locale, format: AVAudioFormat)? {
        guard SpeechTranscriber.isAvailable else { return nil }
        var locale: Locale?
        for identifier in language.speechLocaleCandidates(preferred: Locale.preferredLanguages, current: Locale.current.identifier) {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
            if locale != nil { break }
        }
        guard let locale else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            try? await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else { return nil }
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return nil }
        return (locale, format)
    }

    init(locale: Locale, format: AVAudioFormat) throws {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        )
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.format = format
        self.input = input
        started = Task { try await analyzer.start(inputSequence: stream) }
        results = Task {
            var text = AttributedString()
            for try await result in transcriber.results where result.isFinal {
                text += result.text
            }
            return String(text.characters)
        }
    }

    /// 16-bit mono PCM at the page's rate, converted to the analyzer's format.
    func append(_ data: Data, sampleRate: Double) {
        let frames = data.count / 2
        guard frames > 0 else { return }
        if sourceFormat?.sampleRate != sampleRate {
            sourceFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
            converter = sourceFormat.flatMap { AVAudioConverter(from: $0, to: format) }
        }
        guard let sourceFormat, let converter,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frames)),
              let output = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount((Double(frames) * format.sampleRate / sampleRate).rounded(.up)) + 32
              ) else { return }
        source.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, let target = source.int16ChannelData?[0] else { return }
            memcpy(target, base, frames * 2)
        }
        let pending = PendingBuffer(source)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let buffer = pending.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
        if error == nil, output.frameLength > 0 { input.yield(AnalyzerInput(buffer: output)) }
    }

    func finish() async throws -> String {
        input.finish()
        try await started.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await results.value
    }

    func cancel() {
        input.finish()
        results.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}

private final class PendingBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// A hidden web view whose page records with getUserMedia and posts 16-bit PCM chunks.
@MainActor
private final class KeyboardWebCapture: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Event {
        case started
        case samples(Data, rate: Double, peak: Float)
        case stopped
        case loaded
        case failed(String)
        case processTerminated
    }

    var onEvent: ((Event) -> Void)?
    private let webView: WKWebView
    private var isLoaded = false
    private var startWhenLoaded = false
    private var rate: Double = 48_000

    init(host: UIView) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakMessageHandler(self), name: "typr")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.02
        host.addSubview(webView)
        webView.loadHTMLString(KeyboardCapturePage.html, baseURL: URL(string: "https://keyboard.typr.local/"))
    }

    func start() {
        guard isLoaded else {
            startWhenLoaded = true
            return
        }
        webView.evaluateJavaScript("typrStart()")
    }

    func stop() {
        startWhenLoaded = false
        webView.evaluateJavaScript("typrStop()")
    }

    func tearDown() {
        onEvent = nil
        startWhenLoaded = false
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "typr")
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        onEvent?(.loaded)
        if startWhenLoaded {
            startWhenLoaded = false
            start()
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoaded = false
        onEvent?(.processTerminated)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "started":
            rate = (body["rate"] as? Double) ?? 48_000
            onEvent?(.started)
        case "pcm":
            guard let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded) else { return }
            onEvent?(.samples(data, rate: rate, peak: Float((body["peak"] as? Double) ?? 0)))
        case "stopped":
            onEvent?(.stopped)
        case "error":
            onEvent?(.failed((body["message"] as? String) ?? "unknown"))
        default:
            break
        }
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
