import XCTest
@testable import Typr

struct TestStateTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Waits for a named state instead of a fixed delay. Returns as soon as the state holds; a
/// timeout fails and throws, so the test stops instead of asserting or tearing down files and
/// defaults while work is still running. Time lost to a stalled main actor (a poll far longer than
/// its 5 ms sleep) is credited to the deadline, for at most `maxCreditedStalls` polls: work queued
/// behind the stall has not had its turn yet. Each stall counts in full, because the CI runner can
/// freeze the whole simulator for 60–90 s (app and xcodebuild silent alike).
@MainActor
func waitForState(_ description: String, timeout: Duration = .seconds(10),
                  file: StaticString = #filePath, line: UInt = #line,
                  _ condition: @MainActor () async -> Bool) async throws {
    let result = try await pollState(timeout: timeout, condition)
    guard result.holds else {
        let detail = "\(description) (longest stall \(result.longestStall), \(result.stalls) stalls)"
        XCTFail("Timed out waiting for: \(detail)", file: file, line: line)
        throw TestStateTimeout(description: description)
    }
}

let maxCreditedStalls = 10

struct PollResult {
    var holds = false
    var stalls = 0
    var longestStall = Duration.zero
}

/// `waitForState` without the failure report: `holds` is false once the (stall-extended)
/// deadline passed.
@MainActor
func pollState(timeout: Duration, _ condition: @MainActor () async -> Bool) async throws -> PollResult {
    let poll = Duration.milliseconds(5)
    var deadline = ContinuousClock.now.advanced(by: timeout)
    var result = PollResult()
    var lastTick = ContinuousClock.now
    while true {
        if await condition() {
            result.holds = true
            return result
        }
        let now = ContinuousClock.now
        let stall = lastTick.duration(to: now) - poll
        if stall > .milliseconds(100) {
            result.longestStall = max(result.longestStall, stall)
            if result.stalls < maxCreditedStalls { deadline = deadline.advanced(by: stall) }
            result.stalls += 1
        }
        lastTick = now
        guard now < deadline else { return result }
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
