import XCTest
@testable import Typr

final class CleanupGuardHexTests: XCTestCase {
    func testRejectsAnAnsweredRequest() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "can you find that article about the quarterly report and send it to me",
                cleaned: "I found one article about the quarterly report and sent it to you."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    func testRejectsARepliedToSentence() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "would you say",
                cleaned: "Yes, I would say."
            ),
            "the cleaned text added words the speaker did not say"
        )
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "sure, would you say",
                cleaned: "Yes, would you say."
            ),
            "the cleaned text starts with a reply"
        )
    }

    func testRejectsAPreambleBeforeALongTranscript() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "the quarterly report needs a short summary for the sales team before the meeting on monday",
                cleaned: "Sure, I can help with that. Here's the cleaned transcript: The quarterly report needs a short summary for the sales team before the meeting on Monday."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    func testRejectsAPreamblePhraseTheTranscriptNeverSaid() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "sure here is the plan for the launch and i can help with that",
                cleaned: "Sure, I can help with that. Here's the plan for the launch."
            ),
            "the cleaned text starts with a preamble"
        )
    }

    func testRejectsAnAddedColonInTheFirstClause() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "bring these to the meeting",
                cleaned: "Bring these: notes."
            ),
            "the cleaned text starts with a preamble"
        )
    }

    func testRejectsWordsTheSpeakerNeverSaid() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "i will call you tomorrow",
                cleaned: "I will definitely call you tomorrow morning."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    func testRejectsAPureInsertion() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "i will call you tomorrow",
                cleaned: "I will definitely call you tomorrow."
            ),
            "the cleaned text added words the speaker did not say"
        )
    }

    func testAcceptsMisheardAndReplacedWords() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "we should use cloud code on tuesday, no wait, wednesday",
                cleaned: "We should use Claude Code on Wednesday."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "open get hub and cloud code",
                cleaned: "Open GitHub and Claude Code."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "open the file in vs code",
                cleaned: "Open the file in VS Code."
            )
        )
    }

    func testAcceptsStuttersAndRepeatedPronounSelfCorrections() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i i think we should ship",
                cleaned: "I think we should ship."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "we we should ship it",
                cleaned: "We should ship it."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i'll send it tomorrow, i mean, i'll send it today",
                cleaned: "I'll send it today."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i want, i mean, i need the report",
                cleaned: "I need the report."
            )
        )
    }

    func testAcceptsSelfCorrectionMarkerTails() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i'll send it tomorrow, i mean, i'll send it today",
                cleaned: "I'll send it today."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i want, i mean, i need the report",
                cleaned: "I need the report."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "send it on tuesday actually wednesday",
                cleaned: "Send it on Wednesday."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "the the the build is broken",
                cleaned: "The build is broken."
            )
        )
    }

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
                CleanupGuard.rejection(original: original, cleaned: cleaned),
                "the cleaned text dropped most of the transcript",
                "\(original) -> \(cleaned)"
            )
        }
    }

    func testReplacedWordsCountWithMultiplicity() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "ask cloud to review it and then ask cloud to merge it",
                cleaned: "Ask Claude to review it and then ask Claude to merge it."
            )
        )
    }

    func testPronounContractionsCompareAsTheirExpansions() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i am going home",
                cleaned: "I'm going home."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "we are ready",
                cleaned: "We're ready."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "you are late",
                cleaned: "You're late."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i'm going home",
                cleaned: "I am going home."
            )
        )
    }

    func testAHadContractionStillPassesAsItsExpansion() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i'd finished the report",
                cleaned: "I had finished the report."
            )
        )
    }

    func testRejectsAChangedPerson() {
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "send the notes to me",
                cleaned: "Send the notes to you."
            ),
            "the cleaned text changed who is speaking"
        )
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "we should ship it",
                cleaned: "We should ship it, we should."
            ),
            "the cleaned text changed who is speaking"
        )
    }

    func testASelfCorrectionMayDropAPronoun() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "i said tuesday, no wait, wednesday",
                cleaned: "Wednesday."
            )
        )
    }

    func testKeepsAnOpenerTheSpeakerSaid() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "yes, ship it on friday",
                cleaned: "Yes, ship it on Friday."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "no, do not delete the file",
                cleaned: "No, do not delete the file."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "of course we should ship it",
                cleaned: "Of course we should ship it."
            )
        )
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "of the course we should ship it",
                cleaned: "Of course we should ship it."
            ),
            "the cleaned text starts with a reply"
        )
    }

    func testFillersAndOkAreNotReplies() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "um yes ship it",
                cleaned: "Yes, ship it."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "so okay let's go",
                cleaned: "Okay, let's go."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "ok ship it",
                cleaned: "Okay, ship it."
            )
        )
    }

    func testHearBecameHereWithEverythingElseEqual() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "hear is the doc",
                cleaned: "Here is the doc."
            )
        )
        XCTAssertEqual(
            CleanupGuard.rejection(
                original: "there is the doc",
                cleaned: "Here is the doc."
            ),
            "the cleaned text starts with a reply"
        )
    }

    func testATimeColonIsNotAPreamble() {
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "meet at 3 30",
                cleaned: "Meet at 3:30."
            )
        )
        XCTAssertTrue(
            CleanupGuard.isAcceptable(
                original: "meet at 3:30",
                cleaned: "Meet at 3:30."
            )
        )
    }
}
