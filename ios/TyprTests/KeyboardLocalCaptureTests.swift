import JavaScriptCore
import XCTest
@testable import Typr

final class KeyboardLocalCaptureTests: XCTestCase {
    private let mib = 1_048_576

    private func route(
        enabled: Bool = true,
        warm: Bool = false,
        supported: Bool = true,
        speechReady: Bool = true,
        microphoneAllowed: Bool = true,
        memory: Int = 0,
        captureLoaded: Bool = false
    ) -> KeyboardDictationRoute {
        KeyboardDictationRoute.choose(
            keyboardEnabled: enabled, warm: warm, supported: supported, speechReady: speechReady,
            microphoneAllowed: microphoneAllowed, availableMemory: memory, captureLoaded: captureLoaded
        )
    }

    @MainActor
    func testTheSwitchIsOffByDefaultSoTheTyprAppDictates() {
        let suite = "keyboard.local.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(ExperimentalSwitch.all.contains(.keyboardDictation))
        let enabled = TyprSettings(defaults: defaults)[experiment: .keyboardDictation]
        XCTAssertFalse(enabled)
        XCTAssertEqual(route(enabled: enabled), .app)
        XCTAssertTrue(ExperimentalSwitch.keyboardDictation.title.contains("Apple Speech"))
        XCTAssertTrue(ExperimentalSwitch.keyboardDictation.detail.contains("not Orukeet"))
    }

    func testRouteKeepsWarmOrukeetAndFallsBackToTheAppWhenAnythingIsMissing() {
        XCTAssertEqual(route(), .keyboard)
        XCTAssertEqual(route(warm: true), .app, "a warm mic keeps the selected engine")
        XCTAssertEqual(route(supported: false), .app, "before iOS 26")
        XCTAssertEqual(route(speechReady: false), .app, "no Apple Speech model for the language")
        XCTAssertEqual(route(microphoneAllowed: false), .app)
    }

    func testMemoryGateFollowsHex() {
        XCTAssertEqual(route(memory: 32 * mib), .keyboard)
        XCTAssertEqual(route(memory: 32 * mib - 1), .app, "first capture needs 32 MiB")
        XCTAssertEqual(route(memory: 24 * mib, captureLoaded: true), .keyboard)
        XCTAssertEqual(route(memory: 24 * mib - 1, captureLoaded: true), .app, "later captures need 24 MiB")
        XCTAssertEqual(route(memory: 0), .keyboard, "0: iOS doesn't say (simulator)")
    }

    func testArmedCaptureIsKeptByTheHoldAndBecomesTheResult() {
        var capture = KeyboardLocalCapture()
        XCTAssertTrue(capture.arm(jobID: "a", at: 100))
        XCTAssertTrue(capture.isCapturing("a"))
        XCTAssertNil(capture.snapshot(now: 100.1, loudnessDB: -30), "armed shows nothing")

        XCTAssertEqual(capture.start(jobID: "b", at: 100.4), .kept(jobID: "a"))
        XCTAssertEqual(capture.snapshot(now: 101, loudnessDB: -30)?.state, .recording)
        XCTAssertEqual(capture.snapshot(now: 101, loudnessDB: -30)?.recordingStartedAt, 100, "audio from touch-down")

        XCTAssertEqual(capture.stop(), "a")
        XCTAssertTrue(capture.acceptsAudio("a"), "the page's last chunks after Done still count")
        XCTAssertFalse(capture.acceptsAudio("b"))
        XCTAssertEqual(capture.snapshot(now: 102, loudnessDB: -30)?.state, .transcribing)
        capture.finish(jobID: "a", transcript: "Hallo, wie geht es dir?", resultID: "r")
        let result = capture.snapshot(now: 103, loudnessDB: -30)
        XCTAssertEqual(result?.transcript, "Hallo, wie geht es dir?")
        XCTAssertTrue(result?.hasDeliverableResult(at: 103) ?? false)
        XCTAssertEqual(capture.start(jobID: "c", at: 103), .ignored, "no new job before delivery")

        capture.delivered(resultID: "r")
        XCTAssertNil(capture.snapshot(now: 104, loudnessDB: -30))
        XCTAssertFalse(capture.isActive)
    }

    func testTapSlideOrTimeoutDiscardsTheArmedCaptureAndALateStartIsClosed() {
        var capture = KeyboardLocalCapture()
        XCTAssertTrue(capture.arm(jobID: "a", at: 100))
        XCTAssertEqual(capture.discard(), "a")
        XCTAssertFalse(capture.isCapturing("a"), "a microphone that starts now is closed")
        XCTAssertNil(capture.discard())
        XCTAssertNil(capture.stop(), "nothing is transcribed")

        XCTAssertTrue(capture.arm(jobID: "b", at: 200))
        XCTAssertFalse(capture.expireArmed(jobID: "b", now: 202.9))
        XCTAssertFalse(capture.expireArmed(jobID: "other", now: 210))
        XCTAssertTrue(capture.expireArmed(jobID: "b", now: 203))
        XCTAssertFalse(capture.isActive)

        XCTAssertEqual(capture.start(jobID: "c", at: 300), .begin(jobID: "c"), "a cold tap starts its own job")
        XCTAssertFalse(capture.arm(jobID: "d", at: 300.1), "no arming while recording")
        XCTAssertFalse(capture.expireArmed(jobID: "c", now: 400), "a kept job never times out as armed")
    }

    func testCancelAndFailures() {
        var capture = KeyboardLocalCapture()
        _ = capture.start(jobID: "a", at: 100)
        capture.cancel()
        XCTAssertFalse(capture.isActive)
        XCTAssertNil(capture.snapshot(now: 101, loudnessDB: -62))

        XCTAssertTrue(capture.arm(jobID: "b", at: 200))
        capture.fail("no mic", now: 200.1)
        XCTAssertFalse(capture.isActive, "a failure while armed drops it silently")
        XCTAssertNil(capture.snapshot(now: 200.2, loudnessDB: -62))

        _ = capture.start(jobID: "c", at: 300)
        _ = capture.stop()
        capture.finish(jobID: "other", transcript: "x", resultID: "r")
        XCTAssertEqual(capture.snapshot(now: 301, loudnessDB: -62)?.state, .transcribing, "another job's result is ignored")
        capture.fail("Apple Speech couldn't transcribe this", now: 301)
        XCTAssertEqual(capture.snapshot(now: 302, loudnessDB: -62)?.message, "Apple Speech couldn't transcribe this")
        XCTAssertNil(capture.snapshot(now: 307.1, loudnessDB: -62), "the failure clears")

        _ = capture.start(jobID: "d", at: 400)
        _ = capture.stop()
        capture.finish(jobID: "d", transcript: "", resultID: "r")
        XCTAssertNil(capture.snapshot(now: 401, loudnessDB: -62), "no speech ends quietly")
    }

    @MainActor
    func testGermanTextGetsTheAppsFormatting() {
        let suite = "keyboard.local.text.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TyprSettings(defaults: defaults)
        settings.dictationLanguage = .german
        let heard = " Hallo Komma wie geht es dir Fragezeichen ich bin gleich da Punkt bis bald "

        XCTAssertEqual(KeyboardLocalCapture.text(from: heard, style: .polished, settings: settings),
                       TyprTranscriptFormatter.format(heard.trimmingCharacters(in: .whitespaces), style: .polished, language: .german))
        settings[experiment: .spokenPunctuation] = true
        XCTAssertEqual(KeyboardLocalCapture.text(from: heard, style: .polished, settings: settings),
                       "Hallo, wie geht es dir? Ich bin gleich da. Bis bald.")
        settings.dictationEndsWithPeriod = false
        XCTAssertEqual(KeyboardLocalCapture.text(from: heard, style: .polished, settings: settings),
                       "Hallo, wie geht es dir? Ich bin gleich da. Bis bald")
        settings.dictationLowercase = true
        XCTAssertEqual(KeyboardLocalCapture.text(from: heard, style: .polished, settings: settings),
                       TyprTranscriptFormatter.lowercased("Hallo, wie geht es dir? Ich bin gleich da. Bis bald", style: .polished))
        XCTAssertEqual(KeyboardLocalCapture.text(from: heard, style: .verbatim, settings: settings),
                       TyprTranscriptFormatter.lowercased(heard.trimmingCharacters(in: .whitespaces), style: .verbatim))
        XCTAssertEqual(KeyboardLocalCapture.text(from: "  ", style: .polished, settings: settings), "")
    }

    func testCapturePageStopDuringAPendingCloseStillStopsTheNextMicrophone() throws {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in XCTFail("\(exception?.toString() ?? "")") }
        let page = KeyboardCapturePage.html
        let script = try XCTUnwrap(page.components(separatedBy: "<script>").last?.components(separatedBy: "</script>").first)
        context.evaluateScript("""
        var posts = [], streams = [], closes = [];
        var webkit = { messageHandlers: { typr: { postMessage: function (m) { posts.push(m.type); } } } };
        var setInterval = function () { return 1; }, clearInterval = function () {};
        var navigator = { mediaDevices: { getUserMedia: async function () {
          var track = { stopped: false, stop: function () { this.stopped = true; } };
          var stream = { track: track, getTracks: function () { return [track]; }, getAudioTracks: function () { return [track]; } };
          streams.push(stream);
          return stream;
        } } };
        class AudioContext {
          constructor() { this.state = "running"; this.sampleRate = 48000; this.destination = {}; }
          async resume() {}
          close() { return new Promise(function (resolve) { closes.push(resolve); }); }
          createMediaStreamSource() { return { connect: function () {}, disconnect: function () {} }; }
          createScriptProcessor() { return { connect: function () {}, disconnect: function () {} }; }
        }
        """)
        context.evaluateScript(script)
        for step in ["typrStart()", "typrStop()", "typrStart()", "closes[0]()", "typrStop()"] {
            context.evaluateScript(step)
        }
        XCTAssertEqual(context.evaluateScript("streams.length").toInt32(), 2)
        XCTAssertEqual(context.evaluateScript("JSON.stringify(streams.map(s => s.track.stopped))").toString(), "[true,true]")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(posts)").toString(), #"["started","stopped","started","stopped"]"#)
    }
}
