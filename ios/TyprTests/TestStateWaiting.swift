import XCTest
@testable import Typr

struct TestStateTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Waits for a named state instead of a fixed delay. Returns as soon as the state holds; a
/// timeout fails and throws, so the test stops instead of asserting or tearing down files and
/// defaults while work is still running. The timeout counts only time the process was responsive:
/// a poll that takes far longer than its 5 ms sleep means the whole process stood still (a cold
/// CI simulator can freeze for seconds), and work queued behind that freeze has not had its turn.
@MainActor
func waitForState(_ description: String, timeout: Duration = .seconds(10),
                  file: StaticString = #filePath, line: UInt = #line,
                  _ condition: @MainActor () async -> Bool) async throws {
    let poll = Duration.milliseconds(5)
    var deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
        let started = ContinuousClock.now
        if await condition() { return }
        guard ContinuousClock.now < deadline else {
            XCTFail("Timed out waiting for: \(description)", file: file, line: line)
            throw TestStateTimeout(description: description)
        }
        try await Task.sleep(for: poll)
        let stall = started.duration(to: .now) - poll
        if stall > .milliseconds(100) { deadline = deadline.advanced(by: stall) }
    }
}

/// Returns after every main-actor job enqueued before it has run (the main executor is a FIFO
/// serial queue). For hops whose correct effect is "nothing changed", e.g. a late progress update.
@MainActor
func mainActorBarrier() async {
    await Task { @MainActor in }.value
}

extension DictationController {
    /// Drain signal before teardown: no capture, permission request, transcription (including the
    /// unwind of a cancelled one) or cleanup job is left, and no phase is mid-work.
    var isIdleForTest: Bool { canChangeEngine && !phase.isBusy }
}
