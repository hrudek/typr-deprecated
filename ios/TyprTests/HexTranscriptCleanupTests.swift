import XCTest
@testable import Typr

// Ported from anomalyco/hex ios/HEXMobileTests/TranscriptCleanupTests.swift at 0c1c13d7 (MIT).
final class TranscriptCleanupGuardTests: XCTestCase {
    func testAcceptsMisheardWordsAndSpokenSelfCorrections() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "we should use cloud code on tuesday, no wait, wednesday",
                cleaned: "We should use Claude Code on Wednesday."
            )
        )
    }

    func testAcceptsPunctuationAndCaseChanges() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "meet at ten on thursday and bring the notes",
                cleaned: "Meet at ten on Thursday, and bring the notes."
            )
        )
    }

    func testRejectsDigitChanges() {
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "call me at 555 0100",
                cleaned: "call me at 555 0101"
            )
        )
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "see you at ten",
                cleaned: "see you at 10"
            )
        )
    }

    func testRejectsLostNegation() {
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "do not delete the file",
                cleaned: "delete the file"
            )
        )
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "I don't think that is right",
                cleaned: "I think that is right"
            )
        )
    }

    func testRejectsAddedNegation() {
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "I will go tomorrow",
                cleaned: "I will not go tomorrow"
            )
        )
    }

    func testRejectsRunawayLength() {
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "ship it",
                cleaned: String(repeating: "ship it ", count: 30)
            )
        )
    }

    func testRejectsEmptyOutputAndEmptyInput() {
        XCTAssertFalse(TranscriptCleanupGuard.isAcceptable(original: "", cleaned: ""))
        XCTAssertFalse(TranscriptCleanupGuard.isAcceptable(original: "ship it", cleaned: "   "))
    }

    func testRejectsAnAnswerWithLittleOverlap() {
        XCTAssertFalse(
            TranscriptCleanupGuard.isAcceptable(
                original: "what time is the meeting",
                cleaned: "The weather tomorrow will be sunny and warm."
            )
        )
    }

    /// The reported shape: a dictated request comes back answered, with the responder as
    /// the speaker.
    func testRejectsAnAnsweredRequest() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "can you find that article about the quarterly report and send it to me",
                cleaned: "I found one article about the quarterly report and sent it to you."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    /// The reported shape: a dictated fragment comes back answered.
    func testRejectsARepliedToSentence() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "would you say",
                cleaned: "Yes, I would say."
            ),
            "the cleaned text added words the speaker did not say"
        )
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "sure, would you say",
                cleaned: "Yes, would you say."
            ),
            "the cleaned text starts with a reply"
        )
    }

    /// The reported shape: a long transcript comes back behind a preamble.
    func testRejectsAPreambleBeforeALongTranscript() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "the quarterly report needs a short summary for the sales team before the meeting on monday",
                cleaned: "Sure, I can help with that. Here's the cleaned transcript: The quarterly report needs a short summary for the sales team before the meeting on Monday."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    /// A preamble phrase the transcript never said is refused on its own, even when the
    /// words around it stay within the added-word budget.
    func testRejectsAPreamblePhraseTheTranscriptNeverSaid() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "sure here is the plan for the launch and i can help with that",
                cleaned: "Sure, I can help with that. Here's the plan for the launch."
            ),
            "the cleaned text starts with a preamble"
        )
    }

    /// A colon in the first clause is a preamble's shape when the speaker said no colon
    /// at all.
    func testRejectsAnAddedColonInTheFirstClause() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "bring these to the meeting",
                cleaned: "Bring these: notes."
            ),
            "the cleaned text starts with a preamble"
        )
    }

    /// The reported shape: the answer gained words the speaker never said.
    func testRejectsWordsTheSpeakerNeverSaid() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "i will call you tomorrow",
                cleaned: "I will definitely call you tomorrow morning."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    /// A pure insertion is new content even when it is only one word: there is no
    /// dropped word for it to replace.
    func testRejectsAPureInsertion() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "i will call you tomorrow",
                cleaned: "I will definitely call you tomorrow."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    /// A misheard word may be replaced, including a whole phrase, as long as each added
    /// word replaces a distinct word the cleanup dropped.
    func testAcceptsMisheardAndReplacedWords() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "we should use cloud code on tuesday, no wait, wednesday",
                cleaned: "We should use Claude Code on Wednesday."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "open get hub and cloud code",
                cleaned: "Open GitHub and Claude Code."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "open the file in vs code",
                cleaned: "Open the file in VS Code."
            )
        )
    }

    /// A stutter or a repeated pronoun is dropped, never added back.
    func testAcceptsStuttersAndRepeatedPronounSelfCorrections() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i i think we should ship",
                cleaned: "I think we should ship."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "we we should ship it",
                cleaned: "We should ship it."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i'll send it tomorrow, i mean, i'll send it today",
                cleaned: "I'll send it today."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i want, i mean, i need the report",
                cleaned: "I need the report."
            )
        )
    }

    /// A cleanup that keeps less than half the transcript is a spoken self-correction
    /// only when it keeps the tail after a marker.
    func testAcceptsSelfCorrectionMarkerTails() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i'll send it tomorrow, i mean, i'll send it today",
                cleaned: "I'll send it today."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i want, i mean, i need the report",
                cleaned: "I need the report."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "send it on tuesday actually wednesday",
                cleaned: "Send it on Wednesday."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "the the the build is broken",
                cleaned: "The build is broken."
            )
        )
    }

    /// Dropping most of the transcript without a self-correction is a silent truncation,
    /// even when nothing was added.
    func testRejectsTruncationWithoutASelfCorrection() {
        let cases = [
            (
                "first send the quarterly report to the sales team and then ask them to review the numbers before friday because the board meeting moved up and we need everything signed off by thursday afternoon at the latest",
                "First send the quarterly report to the sales team."
            ),
            (
                "remind me to buy milk and eggs and bread on the way home from work",
                "Remind me to buy milk."
            ),
            (
                "can you find that article about the quarterly report and send it to me",
                "Send it to me."
            ),
            (
                "i think we should ship the new version on friday and then we can tell the customers about it",
                "I think we should ship."
            ),
            (
                "scratch that send the invoice to sarah instead of the whole finance team today",
                "Send the invoice to Sarah."
            ),
            (
                "we need to review the budget and the launch plan with the whole team before friday, actually let's do it monday",
                "Let's do it Monday."
            ),
            (
                "send the budget and the launch plan to the whole team, actually just to sarah",
                "Just to Sarah."
            ),
            (
                "please tell the team the budget review moved so we will have to wait until monday",
                "Until Monday."
            ),
            (
                "the team wants to delay the launch until march but i would rather we ship",
                "We ship."
            ),
            (
                "tell sarah the launch plan and the budget are ready for review, sorry for the delay",
                "For the delay."
            ),
        ]
        for (original, cleaned) in cases {
            XCTAssertEqual(
                TranscriptCleanupGuard.rejection(original: original, cleaned: cleaned),
                "the cleaned text dropped most of the transcript",
                "\(original) -> \(cleaned)"
            )
        }
    }

    /// Replaced words count with multiplicity on both sides: two "cloud" occurrences may
    /// become two "Claude" occurrences.
    func testReplacedWordsCountWithMultiplicity() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "ask cloud to review it and then ask cloud to merge it",
                cleaned: "Ask Claude to review it and then ask Claude to merge it."
            )
        )
    }

    /// Pronoun contractions compare as their expansions, so "I'm" and "I am" are the
    /// same words on both sides.
    func testPronounContractionsCompareAsTheirExpansions() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i am going home",
                cleaned: "I'm going home."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "we are ready",
                cleaned: "We're ready."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "you are late",
                cleaned: "You're late."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i'm going home",
                cleaned: "I am going home."
            )
        )
    }

    /// "i'd" reads as "i would". When the speaker meant "i had", the one added word
    /// replaces the one dropped word, so the ambiguity costs nothing.
    func testAHadContractionStillPassesAsItsExpansion() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i'd finished the report",
                cleaned: "I had finished the report."
            )
        )
    }

    /// Who is speaking may not change: an answer or a preamble adds a pronoun the
    /// transcript never used.
    func testRejectsAChangedPerson() {
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "send the notes to me",
                cleaned: "Send the notes to you."
            ),
            "the cleaned text changed who is speaking"
        )
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "we should ship it",
                cleaned: "We should ship it, we should."
            ),
            "the cleaned text changed who is speaking"
        )
    }

    /// A spoken self-correction may drop a pronoun, since the corrected phrase is the one
    /// the speaker settled on.
    func testASelfCorrectionMayDropAPronoun() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "i said tuesday, no wait, wednesday",
                cleaned: "Wednesday."
            )
        )
    }

    /// The transcript may itself start with an opener; only a new one is a reply.
    func testKeepsAnOpenerTheSpeakerSaid() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "yes, ship it on friday",
                cleaned: "Yes, ship it on Friday."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "no, do not delete the file",
                cleaned: "No, do not delete the file."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "of course we should ship it",
                cleaned: "Of course we should ship it."
            )
        )
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "of the course we should ship it",
                cleaned: "Of course we should ship it."
            ),
            "the cleaned text starts with a reply"
        )
    }

    /// The transcript's own leading fillers do not make its opener new, and "ok" and
    /// "okay" are the same opener.
    func testFillersAndOkAreNotReplies() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "um yes ship it",
                cleaned: "Yes, ship it."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "so okay let's go",
                cleaned: "Okay, let's go."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "ok ship it",
                cleaned: "Okay, ship it."
            )
        )
    }

    /// "hear" may come back as "here" when nothing else changed; a reply that merely
    /// starts with "here" still does not pass.
    func testHearBecameHereWithEverythingElseEqual() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "hear is the doc",
                cleaned: "Here is the doc."
            )
        )
        XCTAssertEqual(
            TranscriptCleanupGuard.rejection(
                original: "there is the doc",
                cleaned: "Here is the doc."
            ),
            "the cleaned text starts with a reply"
        )
    }

    /// A colon between two digits is a time, not a preamble.
    func testATimeColonIsNotAPreamble() {
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "meet at 3 30",
                cleaned: "Meet at 3:30."
            )
        )
        XCTAssertTrue(
            TranscriptCleanupGuard.isAcceptable(
                original: "meet at 3:30",
                cleaned: "Meet at 3:30."
            )
        )
    }

    func testCleanupSettingIsOffByDefaultAndPersists() {
        let suite = "AppleIntelligenceCleanupSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(ExperimentalSwitch.hexExperiments.contains(.appleIntelligenceCleanup))
        XCTAssertEqual(ExperimentalSwitch.appleIntelligenceCleanup.title, "Clean up with Apple Intelligence")
        XCTAssertFalse(TyprSettings(defaults: defaults)[experiment: .appleIntelligenceCleanup])

        TyprSettings(defaults: defaults)[experiment: .appleIntelligenceCleanup] = true
        XCTAssertTrue(TyprSettings(defaults: defaults)[experiment: .appleIntelligenceCleanup])
    }
}
