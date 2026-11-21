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
        let holds = try await pollState(timeout: .milliseconds(50)) { false }
        XCTAssertFalse(holds)
    }

    func testRepeatedStallsStopExtendingTheDeadlineAfterThreeTimeouts() async throws {
        var polls = 0
        let holds = try await pollState(timeout: .milliseconds(100)) {
            polls += 1
            block(milliseconds: 350)
            return false
        }
        XCTAssertFalse(holds)
        XCTAssertLessThanOrEqual(polls, 3)
    }
}
