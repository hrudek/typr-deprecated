import XCTest

@MainActor
final class TestStateWaitingTests: XCTestCase {
    private func block(milliseconds: Int) {
        let end = ContinuousClock.now.advanced(by: .milliseconds(milliseconds))
        while ContinuousClock.now < end {}
    }

    func testAStalledMainActorDoesNotUseUpTheTimeout() async throws {
        var polls = 0
        try await waitForState("state after a stall", timeout: .milliseconds(200)) {
            polls += 1
            if polls == 2 { block(milliseconds: 500) }
            return polls >= 4
        }
        XCTAssertGreaterThanOrEqual(polls, 4)
    }

    func testAWaitThatNeverHoldsFailsAfterTheTimeout() async throws {
        let result = try await pollState(timeout: .milliseconds(50)) { false }
        XCTAssertFalse(result.holds)
    }

    /// A frozen runner (one poll far beyond the timeout) is credited in full.
    func testOneLongStallIsCreditedInFull() async throws {
        var polls = 0
        let result = try await pollState(timeout: .milliseconds(100)) {
            polls += 1
            if polls == 2 { block(milliseconds: 1_000) }
            return polls >= 4
        }
        XCTAssertTrue(result.holds)
        XCTAssertEqual(result.stalls, 1)
    }

    func testRepeatedStallsStopExtendingTheDeadline() async throws {
        var polls = 0
        let result = try await pollState(timeout: .milliseconds(100)) {
            polls += 1
            block(milliseconds: 150)
            return false
        }
        XCTAssertFalse(result.holds)
        XCTAssertLessThanOrEqual(polls, maxCreditedStalls + 1)
    }
}
