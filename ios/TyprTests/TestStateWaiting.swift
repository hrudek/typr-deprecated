import XCTest
@testable import Typr

struct TestStateTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Waits for a named state instead of a fixed delay. Returns as soon as the state holds; a
/// timeout fails and throws, so the test stops instead of asserting or tearing down files and
/// defaults while work is still running. Time lost to a stalled main actor (a poll far longer than
/// its 5 ms sleep, e.g. on a cold CI simulator) is credited to the deadline, at most three timeouts
/// in total: work queued behind the stall has not had its turn yet.
@MainActor
func waitForState(_ description: String, timeout: Duration = .seconds(10),
                  file: StaticString = #filePath, line: UInt = #line,
                  _ condition: @MainActor () async -> Bool) async throws {
    guard try await pollState(timeout: timeout, condition) else {
        XCTFail("Timed out waiting for: \(description)", file: file, line: line)
        throw TestStateTimeout(description: description)
    }
}

/// `waitForState` without the failure report: false once the (stall-extended) deadline passed.
@MainActor
func pollState(timeout: Duration, _ condition: @MainActor () async -> Bool) async throws -> Bool {
    let poll = Duration.milliseconds(5)
    var deadline = ContinuousClock.now.advanced(by: timeout)
    var credit = Duration.zero
    var lastTick = ContinuousClock.now
    while true {
        if await condition() { return true }
        let now = ContinuousClock.now
        let stall = min(lastTick.duration(to: now) - poll, timeout * 3 - credit)
        if stall > .milliseconds(100) {
            deadline = deadline.advanced(by: stall)
            credit += stall
        }
        lastTick = now
        guard now < deadline else { return false }
        try await Task.sleep(for: poll)
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
