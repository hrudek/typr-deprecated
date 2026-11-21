import XCTest
@testable import Typr

@MainActor
final class CleanupGuardTests: XCTestCase {
    private let loggedCases: [(transcript: String, answer: String, accepted: Bool)] = [
        ("Aber bewerb dich doch einfach da, warum auch nicht?",
         "1. Aber\n2. bewerb dich doch einfach da\n3. warum auch nicht", false),
        ("Das ist ein Test. Mal gucken, was jetzt hierbei rumkommt.",
         "1. Das ist ein Test.  \n2. Mal gucken, was jetzt hierbei rumkommt.", false),
        ("Das ist ein Test, hallo, mein Wissen, ob es jetzt klappt.",
         "1. Das ist ein Test.\n2. Hallo.\n3. Mein Wissen.\n4. Ob es jetzt klappt.", false),
        ("Ja, oder einfach umstecken.", "Ja, ja, oder einfach umstecken.", true),
        ("Kannst du mir den Bericht schicken?", "Ja, ich schicke dir den Bericht.", false),
        ("would you say", "Yes, I would say.", false)
    ]

    func testHexGuardOnLoggedAnswers() {
        for item in loggedCases {
            XCTAssertEqual(CleanupGuard.isAcceptable(original: item.transcript, cleaned: item.answer), item.accepted, item.transcript)
        }
    }

    func testHexGuardAcceptsCorrectionsAndRejectsNegationOrNumberChanges() {
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "see you tuesday, no wait, wednesday", cleaned: "see you wednesday"))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "ich gehe zu open ai", cleaned: "ich gehe zu OpenAI"))
        XCTAssertFalse(CleanupGuard.isAcceptable(original: "I can come at 5", cleaned: "I can come at 6"))
        XCTAssertFalse(CleanupGuard.isAcceptable(original: "I do not agree with this plan", cleaned: "I agree with this plan"))
        XCTAssertFalse(CleanupGuard.isAcceptable(original: "hello there", cleaned: "  "))
    }

    func testGermanReplyPersonAndPreambleAreRejected() {
        XCTAssertEqual(CleanupGuard.rejection(original: "schick mir die notizen", cleaned: "Schick dir die Notizen."),
                       "the cleaned text changed who is speaking")
        XCTAssertEqual(CleanupGuard.rejection(original: "also kannst du das morgen machen", cleaned: "Ja, kannst du das morgen machen?"),
                       "the cleaned text starts with a reply")
        XCTAssertEqual(CleanupGuard.rejection(original: "bring die unterlagen mit", cleaned: "Bring Folgendes mit: Unterlagen."),
                       "the cleaned text starts with a preamble")
        XCTAssertEqual(CleanupGuard.rejection(original: "das ist der plan und der text für morgen steht",
                                              cleaned: "Das ist der Plan, der bereinigte Text für morgen steht."),
                       "the cleaned text starts with a preamble")
        XCTAssertEqual(CleanupGuard.rejection(original: "ich rufe dich morgen an", cleaned: "Ich rufe dich morgen ganz bestimmt an."),
                       "the cleaned text added words the speaker did not say")
    }

    func testGermanOpenersTheSpeakerSaidAreKept() {
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "ja das passt so", cleaned: "Ja, das passt so."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "äh ja schick es ab", cleaned: "Ja, schick es ab."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "nein das ist der falsche ordner", cleaned: "Nein, das ist der falsche Ordner."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "hier ist der plan für morgen", cleaned: "Hier ist der Plan für morgen."))
    }

    func testGermanStuttersMisheardWordsAndContractionsAreAccepted() {
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "ich ich glaube wir sollten das so machen", cleaned: "Ich glaube, wir sollten das so machen."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "wir wir müssen den bericht bis freitag fertig machen",
                                                cleaned: "Wir müssen den Bericht bis Freitag fertig machen."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "ich öffne get hub und cloud code", cleaned: "Ich öffne GitHub und Claude Code."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "wie geht es dir", cleaned: "Wie geht's dir?"))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "gibts noch kaffee", cleaned: "Gibt es noch Kaffee?"))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "gibt es noch kaffee", cleaned: "Gibt's noch Kaffee?"))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "hab's vergessen", cleaned: "Habe es vergessen."))
    }

    func testGermanSelfCorrectionTailsAreAcceptedAndTruncationsRejected() {
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "wir treffen uns am dienstag im büro, ich meine, am mittwoch",
                                                cleaned: "Wir treffen uns am Mittwoch."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "ruf den kunden an, streich das, schreib ihm eine mail",
                                                cleaned: "Schreib ihm eine Mail."))
        XCTAssertTrue(CleanupGuard.isAcceptable(original: "schick es am dienstag, nein warte, am mittwoch", cleaned: "Schick es am Mittwoch."))
        let truncations = [
            ("schick bitte den quartalsbericht an das vertriebsteam und frag sie ob die zahlen bis freitag stimmen",
             "Schick bitte den Quartalsbericht an das Vertriebsteam."),
            ("wir müssen das budget und den startplan mit dem ganzen team vor freitag besprechen, eigentlich machen wir es am montag",
             "Machen wir es am Montag.")
        ]
        for (original, cleaned) in truncations {
            XCTAssertEqual(CleanupGuard.rejection(original: original, cleaned: cleaned),
                           "the cleaned text dropped most of the transcript", original)
        }
    }

    func testCoordinatorPastesTranscriptWhenTheEngineRejectsTheAnswer() async {
        for item in loggedCases where !item.accepted {
            let session = CleanupTestSession(), bg = CleanupTestBackground(), observer = CleanupTestObserver(), sleeper = CleanupTestSleeper()
            session.result = item.answer
            session.acceptance = { CleanupGuard.isAcceptable(original: $1, cleaned: $0) }
            let deps = TranscriptCleanupDependencies(cleaner: CleanupTestCleaner(session: session), background: bg, isEnabled: { true }, sleep: sleeper.sleep, observer: observer)
            let job = CleanupJob(session: session, background: bg); job.begin()
            let value = await CleanupCoordinator().clean(item.transcript, job: job, dependencies: deps)
            XCTAssertEqual(value, item.transcript)
            XCTAssertEqual(observer.events.map(\.outcome), [.failed(.unacceptable)])
            job.finish(); sleeper.fire()
            for _ in 0..<30 { await Task.yield() }
        }
    }
}
