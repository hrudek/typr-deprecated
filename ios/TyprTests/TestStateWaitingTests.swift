import XCTest

@MainActor
final class TestStateWaitingTests: XCTestCase {
    func testAFrozenProcessDoesNotUseUpTheTimeout() async throws {
        var polls = 0
        try await waitForState("state after a freeze", timeout: .milliseconds(200)) {
            polls += 1
            if polls == 2 {
                let end = ContinuousClock.now.advanced(by: .milliseconds(500))
                while ContinuousClock.now < end {}
            }
            return polls >= 4
        }
        XCTAssertEqual(polls, 4)
    }
}
