import XCTest
@testable import Typr

final class HexSpeechEnginePolicyTests: XCTestCase {
    private func policy(system: Int, memoryGB: UInt64 = 6, available: UInt64 = 0, setAside: Bool = false) -> HexSpeechEnginePolicy {
        HexSpeechEnginePolicy(system: system, physicalMemory: memoryGB << 30, availableMemory: available, parakeetSetAside: setAside)
    }

    func testIOS26UsesAppleSpeechWhereItHasTheLanguage() {
        XCTAssertEqual(policy(system: 26).engine(for: "de-DE", appleSpeechPicks: true), .appleSpeech)
        XCTAssertEqual(policy(system: 26).engine(for: "en-US", appleSpeechPicks: false), .parakeet)
    }

    func testBeforeIOS26ParakeetTakesEnglishOnlyWithRoom() {
        XCTAssertEqual(policy(system: 18).engine(for: "en-GB", appleSpeechPicks: false), .parakeet)
        XCTAssertEqual(policy(system: 18).engine(for: nil, appleSpeechPicks: false), .parakeet)
        XCTAssertEqual(policy(system: 18).engine(for: "de-DE", appleSpeechPicks: false), .onDeviceRecognizer)
        XCTAssertEqual(policy(system: 18, memoryGB: 2).engine(for: "en-US", appleSpeechPicks: false), .onDeviceRecognizer)
        XCTAssertEqual(policy(system: 18, setAside: true).engine(for: "en-US", appleSpeechPicks: false), .onDeviceRecognizer)
        XCTAssertEqual(policy(system: 18, available: 100 << 20).engine(for: "en-US", appleSpeechPicks: false), .onDeviceRecognizer)
    }

    func testTyprsChosenEngineIsNeverSubstituted() {
        for choice in SpeechEngineChoice.allCases {
            XCTAssertEqual(policy(system: 18).selection(chosen: choice, language: "de-DE", appleSpeechPicks: true), .chosen(choice))
        }
        XCTAssertEqual(policy(system: 26).selection(chosen: nil, language: "de-DE", appleSpeechPicks: true), .automatic(.appleSpeech))
    }

    func testTyprsStoredEngineRawValuesAreUnchanged() {
        XCTAssertEqual(SpeechEngineChoice.allCases.map(\.rawValue), [
            "apple-speech", "parakeet-v2", "whisper-large-v3-turbo", "parakeet-v3", "orukeet", "cohere-transcribe",
        ])
    }

    func testNoticeOnlyWhenParakeetItselfIsSetAside() {
        XCTAssertNotNil(policy(system: 18, setAside: true).notice(for: "en-US"))
        XCTAssertNil(policy(system: 18, memoryGB: 2).notice(for: "en-US"))
        XCTAssertNil(policy(system: 26, setAside: true).notice(for: "en-US"))
    }
}
