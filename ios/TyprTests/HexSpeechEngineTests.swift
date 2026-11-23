import Foundation
import Speech
import XCTest
@testable import Typr

/// Hex's automatic engine choice and its transcribers' pure parts (ported from Hex's
/// `DictationControllerTests`), and the engine selection matrix: a chosen engine is exactly
/// that engine or its own error, never another one.
@MainActor
final class HexSpeechEngineTests: XCTestCase {
    private static let gigabyte: UInt64 = 1 << 30
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var roots: [URL] = []

    override func setUp() async throws {
        suiteName = "typr.tests.engine.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }

    private func device(
        system: Int = 18,
        memory: UInt64 = 5_500 << 20,
        available: UInt64 = 0,
        setAside: Bool = false
    ) -> HexSpeechEnginePolicy {
        HexSpeechEnginePolicy(system: system, physicalMemory: memory, availableMemory: available, parakeetSetAside: setAside)
    }

    private func root(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typr-engine-matrix-\(name)-\(UUID().uuidString)", isDirectory: true)
        roots.append(url)
        return url
    }

    // MARK: - Hex's automatic choice

    /// Parakeet V2 knows only English: Spanish goes to Apple Speech whatever happens, even when
    /// Apple Speech doesn't answer, rather than Parakeet hearing it as English words.
    func testSpanishNeverGoesToEnglishOnlyParakeet() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Apple Speech arrived in iOS 26") }
        func language(_ identifier: String, _ module: SpeechModuleKind) -> SpeechLanguage {
            SpeechLanguage(locale: Locale(identifier: identifier), module: module)
        }
        typealias Controller = DictationController
        XCTAssertEqual(Controller.appleSpeechLanguage(picked: language("es-ES", .speech), wanted: "es-ES", parakeetFits: true)?.identifier, "es-ES")
        XCTAssertEqual(Controller.appleSpeechLanguage(picked: language("es-MX", .dictation), wanted: "es-MX", parakeetFits: true)?.identifier, "es-MX")
        XCTAssertEqual(Controller.appleSpeechLanguage(picked: language("en-US", .speech), wanted: nil, parakeetFits: true)?.identifier, "en-US")
        XCTAssertNil(Controller.appleSpeechLanguage(picked: language("en-US", .dictation), wanted: nil, parakeetFits: true,
                                                    hasSpeechTranscriber: false), "English on DictationTranscriber: Parakeet")
        // Speech not answering: English may go to Parakeet, Spanish never.
        XCTAssertNil(Controller.appleSpeechLanguage(picked: nil, wanted: "en-US", parakeetFits: true, hasSpeechTranscriber: false))
        XCTAssertNil(Controller.appleSpeechLanguage(picked: nil, wanted: nil, parakeetFits: true))
        XCTAssertEqual(Controller.appleSpeechLanguage(picked: nil, wanted: "es-ES", parakeetFits: true)?.identifier, "es-ES")
        XCTAssertEqual(Controller.appleSpeechLanguage(picked: nil, wanted: "es-US", parakeetFits: true)?.identifier, "es-US")
    }

    func testAppleSpeechKeepsEnglishWhereItHasSpeechTranscriberOrParakeetDoesNotFit() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Apple Speech arrived in iOS 26") }
        let english = SpeechLanguage(locale: Locale(identifier: "en-US"), module: .dictation)
        XCTAssertTrue(AppleSpeechTranscriber.shouldUse(english, parakeetFits: false, hasSpeechTranscriber: false, appleSetAside: false))
        XCTAssertTrue(AppleSpeechTranscriber.shouldUse(english, parakeetFits: true, hasSpeechTranscriber: true, appleSetAside: false))
        XCTAssertFalse(AppleSpeechTranscriber.shouldUse(english, parakeetFits: true, hasSpeechTranscriber: true, appleSetAside: true),
                       "only once Apple's English is set aside is Parakeet the way left")
        XCTAssertFalse(AppleSpeechTranscriber.shouldUse(english, parakeetFits: true, hasSpeechTranscriber: false, appleSetAside: false))
    }

    func testBeforeIOS26EveryOtherLanguageGoesToTheOnDeviceRecognizer() {
        for language in ["zh-CN", "zh-Hans-CN", "es-ES", "fr-FR", "de-DE"] {
            XCTAssertEqual(device(memory: 8 * Self.gigabyte).engine(for: language, appleSpeechPicks: false), .onDeviceRecognizer, language)
        }
        XCTAssertNil(device().notice(for: "zh-CN"), "nothing to say: Parakeet never had Chinese")
        XCTAssertNil(device(memory: 2_813 << 20).notice(for: "en-US"), "nor on an iPhone it never fit")
    }

    func testFromIOS26TheRecognizerIsNeverPicked() async {
        for system in [26, 27] {
            for memory in [2_813 << 20, 3_700 << 20, 5_500 << 20] as [UInt64] {
                for setAside in [false, true] {
                    for language in ["en-US", "zh-CN", nil] as [String?] {
                        let choice = device(system: system, memory: memory, available: 1 << 20, setAside: setAside)
                        XCTAssertEqual(choice.engine(for: language, appleSpeechPicks: true), .appleSpeech)
                        XCTAssertEqual(choice.engine(for: language, appleSpeechPicks: false), .parakeet)
                        XCTAssertNil(choice.notice(for: language))
                    }
                }
            }
        }
        XCTAssertTrue(device(system: 26, memory: 5_500 << 20).parakeetFitsBesideAppleSpeech)
        XCTAssertFalse(device(system: 26, memory: 3_700 << 20).parakeetFitsBesideAppleSpeech, "iPhone 11")
        XCTAssertFalse(device(system: 26, setAside: true).parakeetFitsBesideAppleSpeech, "Apple Speech after a load that ended Typr")
        XCTAssertFalse(device(system: 26, available: 1 << 30).parakeetFitsBesideAppleSpeech)
        if #available(iOS 26.0, *) {
            for language in DictationLanguage.allCases {
                let transcriber = await DictationController.defaultTranscriber(language: language,
                                                                                settings: LanguageSettings(defaults: defaults))
                XCTAssertFalse(transcriber is OnDeviceSpeechTranscriber, "\(language): \(type(of: transcriber))")
            }
        }
    }

    func testAParakeetLoadThatEndedTyprMovesEnglishToTheRecognizerBeforeIOS26() {
        let loads = ParakeetLoadGuard(defaults: defaults)
        let nextLaunch = ParakeetLoadGuard(defaults: defaults)
        loads.begin()
        nextLaunch.noteLaunch()
        XCTAssertFalse(nextLaunch.lastLoadWasInterrupted, "one interrupted load is no evidence")
        loads.begin()
        nextLaunch.noteLaunch()
        XCTAssertTrue(nextLaunch.lastLoadWasInterrupted)
        let choice = device(setAside: nextLaunch.lastLoadWasInterrupted)
        XCTAssertEqual(choice.engine(for: "en-US", appleSpeechPicks: false), .onDeviceRecognizer)
        let transcriber = DictationController.transcriberBeforeAppleSpeech(
            policy: choice, explicit: nil, suite: suiteName, resolve: { _, _, _ in "en-US" }
        )
        XCTAssertTrue(transcriber is OnDeviceSpeechTranscriber)
        XCTAssertTrue(DictationController.transcriberBeforeAppleSpeech(policy: device(), explicit: "en-US", suite: suiteName) is ParakeetTranscriber)
        XCTAssertTrue(DictationController.transcriberBeforeAppleSpeech(policy: device(), explicit: "de-DE", suite: suiteName,
                                                                       resolve: { _, _, _ in "de-DE" }) is OnDeviceSpeechTranscriber,
                      "German never goes to English-only Parakeet")

        // A load that returned clears what came before.
        nextLaunch.end(loaded: true)
        XCTAssertFalse(nextLaunch.lastLoadWasInterrupted)
        // Too little memory at the load counts the same way, before anything loads.
        nextLaunch.setAside()
        XCTAssertTrue(nextLaunch.lastLoadWasInterrupted)
        XCTAssertTrue(ParakeetTranscriber.hasRoomToLoad(available: 0), "the simulator says nothing")
        XCTAssertFalse(ParakeetTranscriber.hasRoomToLoad(available: 1_200 << 20))
        XCTAssertTrue(ParakeetTranscriber.hasRoomToLoad(available: 2 << 30))
    }

    func testASetAsideLoadIsTriedAgainAfterADayOrANewBuild() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let loads = ParakeetLoadGuard(defaults: defaults, build: "100", now: { now })
        loads.setAside()
        XCTAssertTrue(loads.lastLoadWasInterrupted)
        XCTAssertFalse(ParakeetLoadGuard(defaults: defaults, build: "101", now: { now }).lastLoadWasInterrupted)
        now = now.addingTimeInterval(ParakeetLoadGuard.setAsideDuration + 1)
        XCTAssertFalse(loads.lastLoadWasInterrupted)
    }

    func testTheRecognizerAsksForSpeechRecognitionOnlyAsItGetsReady() async throws {
        let access = CountingSpeechAccess(answer: .denied)
        let transcriber = DictationController.transcriberBeforeAppleSpeech(
            policy: device(memory: 2_813 << 20),
            explicit: nil,
            suite: suiteName,
            access: access.access,
            resolve: { _, _, _ in "zh-CN" }
        )
        XCTAssertEqual(access.requests, 0, "picking the engine asks nothing")
        let details = DetailLog()
        do {
            try await transcriber.prepare { details.append($0.detail) }
            XCTFail("prepared without Speech Recognition")
        } catch {
            XCTAssertEqual(error as? OnDeviceSpeechTranscriber.TranscriberError, .notAllowed)
            XCTAssertEqual(error.localizedDescription, "Allow Speech Recognition for Typr in Settings. It runs on this iPhone.")
        }
        XCTAssertEqual(access.requests, 1)
        XCTAssertEqual(
            details.values,
            ["Checking on-device speech recognition", "Allow Speech Recognition. It stays on this iPhone."],
            "says it stays on the iPhone before iOS asks"
        )
        let languageID = await transcriber.languageIdentifier
        XCTAssertEqual(languageID, "zh-CN")

        // English on an iPhone Parakeet fits never asks at all.
        let parakeet = DictationController.transcriberBeforeAppleSpeech(policy: device(), explicit: nil, suite: suiteName, access: access.access)
        XCTAssertTrue(parakeet is ParakeetTranscriber)
        XCTAssertEqual(access.requests, 1)
        XCTAssertTrue(OnDeviceSpeechTranscriber.isNoSpeech(NSError(domain: "kAFAssistantErrorDomain", code: 1110)))
    }

    func testTheRecognizerFindsChineseAndEnglishAsAppleListsThem() {
        let supported = ["de-DE", "en-AU", "en-GB", "en-IN", "en-US", "fr-CA", "fr-FR", "yue-CN", "zh-CN", "zh-HK", "zh-TW"]
        XCTAssertEqual(OnDeviceSpeechLanguages.match("zh-Hans-CN", in: supported), "zh-CN", "a Simplified Chinese iPhone")
        XCTAssertEqual(OnDeviceSpeechLanguages.match("zh-Hant-TW", in: supported), "zh-TW")
        XCTAssertEqual(OnDeviceSpeechLanguages.match("zh-Hant-HK", in: supported), "zh-HK")
        XCTAssertEqual(OnDeviceSpeechLanguages.match("en-GB", in: supported), "en-GB")
        XCTAssertEqual(OnDeviceSpeechLanguages.match("en", in: supported), "en-US")
        XCTAssertEqual(OnDeviceSpeechLanguages.match("en-NZ", in: supported), "en-US")
        XCTAssertEqual(OnDeviceSpeechLanguages.match("de-CH", in: supported), "de-DE")
        XCTAssertNil(OnDeviceSpeechLanguages.match("he-IL", in: supported))

        let languages = LanguageSettings(defaults: defaults)
        let onDevice: (String) -> Bool = { $0 != "fr-CA" }
        func resolve(_ explicit: String?, _ preferred: [String], strict: Bool = false) -> String? {
            OnDeviceSpeechLanguages.resolve(explicit: explicit, strict: strict, settings: languages, preferred: preferred,
                                            supported: supported, onDevice: onDevice)
        }
        XCTAssertEqual(resolve(nil, ["zh-Hans-CN", "en-CN"]), "zh-CN")
        XCTAssertEqual(resolve(nil, ["he-IL", "fr-CA"]), "en-US",
                       "neither Hebrew nor Canadian French on device: English, which every iPhone on iOS 18 has")
        languages.markUnavailable("zh-CN")
        XCTAssertEqual(resolve(nil, ["zh-Hans-CN", "en-CN"]), "en-US", "Automatic passes over a language set aside")
        XCTAssertEqual(resolve("de-DE", ["en-US"]), "de-DE", "a choice made by hand is tried as it is")
        XCTAssertEqual(resolve("he-IL", ["en-US"]), "en-US", "a choice the recognizer doesn't have falls through to Automatic")
        XCTAssertEqual(resolve("de-DE", ["en-US"], strict: true), "de-DE")
        XCTAssertNil(resolve("he-IL", ["en-US"], strict: true), "Typr strict dictation language: never another language")
    }

    /// Hex: an explicit language Apple Speech doesn't have falls through to Automatic's pick.
    /// Typr strict dictation language passes no candidates, so it stays unpicked.
    func testAnExplicitLanguageAppleLacksFallsThroughUnlessStrict() async {
        let english = Locale(identifier: "en-US")
        func pick(strict: Bool) async -> SpeechLanguage? {
            await SpeechLanguagePicker.pick(
                explicit: "de-DE",
                candidates: strict ? [] : ["en-US"],
                speech: { @Sendable locale in locale.language.languageCode == english.language.languageCode ? english : nil },
                dictation: { @Sendable _ in nil }
            )
        }
        let fallback = await pick(strict: false)
        XCTAssertEqual(fallback?.identifier, "en-US")
        let strict = await pick(strict: true)
        XCTAssertNil(strict)
    }

    func testTheStrictSwitchReachesTheRecognizerChoice() {
        var seen: [Bool] = []
        for strict in [false, true] {
            _ = DictationController.transcriberBeforeAppleSpeech(
                policy: device(), explicit: "de-DE", strict: strict, suite: suiteName,
                resolve: { _, strict, _ in seen.append(strict); return "de-DE" }
            )
        }
        XCTAssertEqual(seen, [false, true])
        XCTAssertFalse(TyprSettings(defaults: defaults)[experiment: .typrStrictDictationLanguage], "off by default: Hex")
        XCTAssertTrue(ExperimentalSwitch.typrVariants.contains(.typrStrictDictationLanguage))
    }

    func testTyprsLanguageChoiceIsTheExplicitLanguage() {
        let languages = LanguageSettings(defaults: defaults)
        XCTAssertNil(languages.explicitDictationLanguage(typr: .automatic))
        XCTAssertEqual(languages.explicitDictationLanguage(typr: .german), "de-DE")
        XCTAssertEqual(languages.explicitDictationLanguage(typr: .english), "en-US")
        languages.dictationLanguage = "fr-FR"
        XCTAssertNil(languages.explicitDictationLanguage(typr: .automatic), "Typr dictates in German or English only")
        XCTAssertEqual(languages.explicitDictationLanguage(typr: .german), "de-DE", "Typr's own choice comes first")
        XCTAssertEqual(DictationController.wantedLanguage(explicit: "de-DE"), "de-DE")
        XCTAssertEqual(DictationController.wantedLanguage(explicit: nil), Locale.preferredLanguages.first)
    }

    func testParakeetPreparationProgressMovesAndEnds() {
        var progress = ParakeetPreparationProgress(downloads: true, compiledBefore: false)
        XCTAssertEqual(progress.snapshot(at: 0).fractionCompleted, 0)
        progress.download(0.5)
        XCTAssertEqual(progress.snapshot(at: 0).fractionCompleted ?? 0, 0.35, accuracy: 0.001)
        progress.startLoading(at: 10)
        let early = progress.snapshot(at: 11).fractionCompleted ?? 0
        let later = progress.snapshot(at: 60).fractionCompleted ?? 0
        XCTAssertGreaterThan(later, early)
        XCTAssertLessThan(later, 1, "never full before Core ML says it's done")
        progress.finish()
        XCTAssertEqual(progress.snapshot(at: 61).fractionCompleted, 1)
    }

    func testTheDictationLogNamesHexsEngineFailures() {
        XCTAssertEqual(DictationLogASRFailure.classify(ParakeetTranscriber.TranscriberError.notEnoughMemory), .modelNotReady)
        XCTAssertEqual(DictationLogASRFailure.classify(ParakeetTranscriber.TranscriberError.downloadFailed), .modelNotReady)
        XCTAssertEqual(DictationLogASRFailure.classify(OnDeviceSpeechTranscriber.TranscriberError.notAllowed), .modelNotReady)
        XCTAssertEqual(DictationLogASRFailure.classify(OnDeviceSpeechTranscriber.TranscriberError.emptyTranscript), .noSpeech)
    }

    // MARK: - Engine selection matrix

    private func emptyProvider() -> ProductionSpeechEngineProvider {
        ProductionSpeechEngineProvider(
            whisperStore: WhisperModelStore(root: root("whisper")),
            parakeetV3Store: ParakeetV3ModelStore(root: root("v3")),
            orukeetStore: OrukeetModelStore(root: root("orukeet")),
            cohereStore: CohereModelStore(root: root("cohere"))
        )
    }

    /// Every one of Typr's six engines, chosen, is that engine or fails naming it: nothing is
    /// downloaded to create it and no other engine stands in, whatever the language.
    func testEveryChosenEngineIsExactlyThatEngineOrItsOwnError() async {
        let provider = emptyProvider()
        for engine in SpeechEngineChoice.allCases {
            for language in DictationLanguage.allCases {
                do {
                    let created = try await provider.transcriber(for: engine, language: language)
                    XCTAssertEqual(created.displayName, engine.displayName, "\(engine) \(language)")
                    XCTAssertFalse(engine.requiresExplicitDownload, "\(engine) created without its download")
                } catch let error as SpeechEngineError {
                    switch error {
                    case .notInstalled(let named), .requiresNewerOS(let named):
                        XCTAssertEqual(named, engine)
                    case .languageUnsupported(let named, let failed):
                        XCTAssertEqual(named, engine)
                        XCTAssertEqual(failed, language)
                    case .notReady:
                        XCTFail("\(engine) \(language): not ready")
                    }
                    if engine.requiresExplicitDownload {
                        XCTAssertEqual(error, .notInstalled(engine))
                    }
                } catch {
                    XCTFail("\(engine) \(language): \(error)")
                }
            }
        }
    }

    func testChosenOrukeetIsOrukeetOnceInstalledAndAutomaticNeverPicksAnExtraEngine() async throws {
        let orukeet = OrukeetModelStore(root: root("orukeet"))
        try WhisperTestFiles.writeSparse(orukeet.fileURL(for: OrukeetModelSpec.archive), bytes: OrukeetModelSpec.archive.bytes)
        try orukeet.writeMarker()
        try OrukeetTestFiles.populateCompiled(orukeet)
        XCTAssertTrue(orukeet.isInstalled)
        let whisper = WhisperModelStore(root: root("whisper"))
        try WhisperTestFiles.populate(whisper, marker: true)
        let parakeetV3 = ParakeetV3ModelStore(root: root("v3"))
        try ParakeetV3TestFiles.populate(parakeetV3, marker: true)
        let cohere = CohereModelStore(root: root("cohere"))
        try CohereTestFiles.populate(cohere, marker: true)
        let provider = ProductionSpeechEngineProvider(whisperStore: whisper, parakeetV3Store: parakeetV3,
                                                      orukeetStore: orukeet, cohereStore: cohere)
        for language in DictationLanguage.allCases {
            let chosen = try await provider.transcriber(for: .orukeet, language: language)
            XCTAssertEqual(chosen.displayName, "Orukeet", "\(language)")
            XCTAssertTrue(chosen is OrukeetTranscriber)
            let automatic = await provider.automaticTranscriber(language: language)
            XCTAssertTrue(["Apple Speech", "Parakeet V2"].contains(automatic.displayName),
                          "\(language): \(automatic.displayName)")
        }
        XCTAssertEqual(SpeechEngineChoice(rawValue: "orukeet"), .orukeet, "stored value unchanged")
    }

    func testAChosenEngineIsNeverReplacedByTheAutomaticChoice() {
        for system in [18, 26] {
            for memory in [2 * Self.gigabyte, 8 * Self.gigabyte] {
                let policy = device(system: system, memory: memory, setAside: true)
                for engine in SpeechEngineChoice.allCases {
                    for language in ["de-DE", "en-US", nil] as [String?] {
                        XCTAssertEqual(policy.selection(chosen: engine, language: language, appleSpeechPicks: false), .chosen(engine))
                    }
                }
                XCTAssertNotEqual(policy.selection(chosen: nil, language: "en-US", appleSpeechPicks: true), .chosen(.appleSpeech))
            }
        }
    }
}

/// Getting a language's speech model: `SpeechTranscriber`'s, then `DictationTranscriber`'s, then
/// a plain message. The Apple Speech calls are fakes; the simulator has no speech models.
final class SpeechModelInstallTests: XCTestCase {
    private var suite = ""
    private var settings = LanguageSettings(defaults: nil)

    override func setUp() {
        suite = "typr.tests.install.\(UUID().uuidString)"
        settings = LanguageSettings(defaults: UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private let russian = SpeechLanguage(locale: Locale(identifier: "ru-RU"), module: .speech)

    /// Each module's status before and after its download; a download either throws, hangs
    /// without progress, or installs.
    private final class FakeAssets: @unchecked Sendable {
        enum Download { case installs, fails, hangs }
        let lock = NSLock()
        var status: [SpeechModuleKind: SpeechModelInstall.Availability] = [.speech: .downloadable, .dictation: .downloadable]
        var downloads: [SpeechModuleKind: Download] = [:]
        var dictationHas = true
        var online = true
        var downloaded: [SpeechModuleKind] = []

        var steps: SpeechModelInstall.Steps {
            SpeechModelInstall.Steps(
                dictationEquivalent: { [self] locale in dictationHas ? locale : nil },
                status: { [self] language in lock.withLock { status[language.module] ?? .unsupported } },
                download: { [self] language, progress in
                    let outcome = lock.withLock {
                        downloaded.append(language.module)
                        return downloads[language.module] ?? .installs
                    }
                    switch outcome {
                    case .installs:
                        progress(0.5)
                        lock.withLock { status[language.module] = .installed }
                    case .fails:
                        throw NSError(
                            domain: "SFSpeechErrorDomain",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "transcription.ru asset not found after attempted download."]
                        )
                    case .hangs:
                        progress(0.5)
                        try await Task.sleep(for: .seconds(60))
                    }
                },
                isOnline: { [self] in online }
            )
        }
    }

    private func run(_ assets: FakeAssets) async throws -> SpeechLanguage {
        try await SpeechModelInstall.run(russian, steps: assets.steps, settings: settings, stallLimit: .milliseconds(300))
    }

    func testAnInstalledModelIsUsedAsItIs() async throws {
        let assets = FakeAssets()
        assets.status[.speech] = .installed
        let installed = try await run(assets)
        XCTAssertEqual(installed, russian)
        XCTAssertTrue(assets.downloaded.isEmpty)
    }

    func testASpeechTranscriberAssetThatNeverArrivesFallsBackToDictationTranscriber() async throws {
        let assets = FakeAssets()
        assets.downloads[.speech] = .fails
        let installed = try await run(assets)
        XCTAssertEqual(installed.module, .dictation)
        XCTAssertEqual(installed.identifier, "ru-RU")
        XCTAssertEqual(assets.downloaded, [.speech, .dictation])
        XCTAssertFalse(settings.speechModuleFailed("ru-RU"), "one failure sets nothing aside")
        _ = try await run(assets)
        XCTAssertTrue(settings.speechModuleFailed("ru-RU"), "twice in a row: the next dictation goes straight to DictationTranscriber")
        XCTAssertFalse(settings.isUnavailable("ru-RU"))
    }

    func testASpeechTranscriberModelThatInstallsBetweenTwoFailuresIsNotSetAside() async throws {
        let failing = FakeAssets()
        failing.downloads[.speech] = .fails
        _ = try await run(failing)
        _ = try await run(FakeAssets())
        _ = try await run(failing)
        XCTAssertFalse(settings.speechModuleFailed("ru-RU"), "not in a row")
    }

    func testAFailureThatSetsNothingAsideKeepsTheLanguage() async {
        let assets = FakeAssets()
        assets.downloads = [.speech: .fails, .dictation: .fails]
        for _ in 0..<3 {
            _ = try? await SpeechModelInstall.run(
                russian, steps: assets.steps, settings: settings, setsAside: false, stallLimit: .milliseconds(300)
            )
        }
        XCTAssertFalse(settings.speechModuleFailed("ru-RU"))
        XCTAssertFalse(settings.isUnavailable("ru-RU"))
    }

    func testNeitherModelOnlineSetsTheLanguageAside() async {
        let assets = FakeAssets()
        assets.downloads = [.speech: .fails, .dictation: .fails]
        do {
            _ = try await run(assets)
            XCTFail("nothing installed")
        } catch {
            XCTAssertEqual(error as? SpeechModelUnavailable, SpeechModelUnavailable(language: "ru-RU", reason: .notOnThisIPhone))
            XCTAssertEqual(error.localizedDescription, "Russian isn't available for dictation on this iPhone yet.")
        }
        XCTAssertFalse(settings.isUnavailable("ru-RU"), "one failure sets nothing aside")
        _ = try? await run(assets)
        XCTAssertTrue(settings.isUnavailable("ru-RU"))
    }

    func testUnsupportedEverywhereIsNotAvailableWithoutDownloading() async {
        let assets = FakeAssets()
        assets.status = [.speech: .unsupported, .dictation: .unsupported]
        do {
            _ = try await run(assets)
            XCTFail("nothing installed")
        } catch {
            XCTAssertEqual((error as? SpeechModelUnavailable)?.reason, .notOnThisIPhone)
        }
        XCTAssertTrue(assets.downloaded.isEmpty)
    }

    func testOfflineIsADownloadFailureNotAMissingLanguage() async {
        let assets = FakeAssets()
        assets.downloads = [.speech: .fails, .dictation: .fails]
        assets.online = false
        do {
            _ = try await run(assets)
            XCTFail("nothing installed")
        } catch {
            XCTAssertEqual((error as? SpeechModelUnavailable)?.reason, .downloadFailed)
            XCTAssertEqual(error.localizedDescription, "Russian speech didn't download. Check your connection.")
        }
        XCTAssertFalse(settings.isUnavailable("ru-RU"), "tried again next time")
    }

    func testAStalledDownloadEndsInsteadOfHanging() async {
        let assets = FakeAssets()
        assets.downloads = [.speech: .hangs, .dictation: .hangs]
        let started = Date()
        do {
            _ = try await run(assets)
            XCTFail("nothing installed")
        } catch {
            XCTAssertEqual((error as? SpeechModelUnavailable)?.reason, .downloadFailed)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "two 0.3 s stalls, not two 60 s downloads")
        XCTAssertEqual(assets.downloaded, [.speech, .dictation])
    }

    func testAStalledSpeechTranscriberDownloadStillTriesDictationTranscriber() async throws {
        let assets = FakeAssets()
        assets.downloads = [.speech: .hangs]
        let installed = try await run(assets)
        XCTAssertEqual(installed.module, .dictation)
    }

    func testAnAutomaticMoveSaysItSwitched() {
        let switched = SpeechModelUnavailable(language: "ru-RU", reason: .notOnThisIPhone, fallback: "en-US")
        XCTAssertTrue(switched.switchedAutomatically)
        XCTAssertFalse(SpeechModelUnavailable(language: "ru-RU", reason: .notOnThisIPhone, fallback: "en-US", automatic: false)
            .switchedAutomatically, "a language picked by hand is offered another, never switched")
        XCTAssertFalse(SpeechModelUnavailable(language: "ru-RU", reason: .downloadFailed, fallback: "en-US").switchedAutomatically)
    }
}

final class StallWatchTests: XCTestCase {
    private enum WorkerError: Error { case failed }

    func testAMovingOperationFinishes() async throws {
        let fraction = ProgressReading()
        let value = try await StallWatch.run(limit: .milliseconds(200), poll: .milliseconds(20), progress: { fraction.value }) {
            for step in 1...10 {
                try await Task.sleep(for: .milliseconds(50))
                fraction.value = Double(step) / 10
            }
            return "done"
        }
        XCTAssertEqual(value, "done")
    }

    func testAnOperationThatStopsMovingIsCancelled() async {
        let cancelled = expectation(description: "worker observed cancellation")
        let started = Date()
        do {
            _ = try await StallWatch.run(limit: .milliseconds(200), poll: .milliseconds(20), progress: { 0.5 }) {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    cancelled.fulfill()
                    throw error
                }
            }
            XCTFail("stalled")
        } catch {
            XCTAssertTrue(error is StallWatch.Stalled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testANilReadingPausesTheWatch() async throws {
        // Core ML's compile reports nothing for longer than the limit; it isn't a stall.
        let value = try await StallWatch.run(limit: .milliseconds(100), poll: .milliseconds(20), progress: { nil }) {
            try await Task.sleep(for: .milliseconds(400))
            return 7
        }
        XCTAssertEqual(value, 7)
    }

    func testCancellingTheCallerEndsTheWait() async {
        let started = expectation(description: "worker started")
        let task = Task {
            try await StallWatch.run(limit: .seconds(30), progress: { nil }) {
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    throw WorkerError.failed
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            try await task.value
            XCTFail("expected caller cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "unexpected error: \(error)")
        }
    }

    func testAWorkerErrorIsPropagated() async {
        do {
            try await StallWatch.run(limit: .seconds(30), progress: { nil }) {
                throw WorkerError.failed
            }
            XCTFail("expected worker error")
        } catch {
            XCTAssertTrue(error is WorkerError, "unexpected error: \(error)")
        }
    }
}

private final class CountingSpeechAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var status: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    let answer: SFSpeechRecognizerAuthorizationStatus

    init(answer: SFSpeechRecognizerAuthorizationStatus) {
        self.answer = answer
    }

    var requests: Int { lock.withLock { count } }

    var access: SpeechRecognitionAccess {
        SpeechRecognitionAccess(
            status: { self.lock.withLock { self.status } },
            request: {
                self.lock.withLock {
                    self.count += 1
                    self.status = self.answer
                    return self.answer
                }
            }
        )
    }
}

private final class DetailLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func append(_ value: String) { lock.withLock { stored.append(value) } }
    var values: [String] { lock.withLock { stored } }
}
