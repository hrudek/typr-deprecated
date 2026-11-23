import Foundation
import Observation
import SwiftUI

/// Resumes each file from its partial download, including after relaunch.
@MainActor
@Observable
final class ParakeetUltraDownload {
    enum State: Equatable {
        case idle
        case downloading(Int64)
        /// A nil retry delay waits for foreground activation.
        case waiting(Int64, retryIn: Int?)
        case loading
        case failed(String)
    }

    private(set) var state = State.idle
    /// Called once every file is on disk.
    @ObservationIgnored var onDownloaded: (@MainActor () -> Void)?

    nonisolated static let stallLimit: Duration = .seconds(20)
    static let automaticTries = 6

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var drainingTask: Task<Void, Never>?
    @ObservationIgnored private var tries = 0
    /// What was on disk at the last stop: a download that moved since starts its tries over.
    @ObservationIgnored private var bytesAtLastStop: Int64 = 0
    @ObservationIgnored private var failedForConnection = false
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var backgroundTime: BackgroundTime?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let files: [ParakeetUltraModel.File]
    typealias Fetch = @Sendable (@escaping @Sendable (Int64) async -> Void) async throws -> Void
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let backoff: (Int) -> Int

    init(
        directory: URL = ParakeetUltraModel.directory,
        files: [ParakeetUltraModel.File] = ParakeetUltraModel.files,
        base: String = ParakeetUltraModel.baseURL,
        session: URLSession = ParakeetUltraDownload.makeSession(),
        stallLimit: Duration = ParakeetUltraDownload.stallLimit,
        backoff: @escaping (Int) -> Int = ParakeetUltraDownload.backoff,
        fetch: Fetch? = nil
    ) {
        self.directory = directory
        self.files = files
        self.fetch = fetch ?? { publish in
            try await Self.fetch(
                directory: directory, files: files, base: base, session: session,
                stallLimit: stallLimit, publish: publish
            )
        }
        self.backoff = backoff
    }

    /// A connection that sends nothing for 30 s ends, rather than after the default minute.
    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }

    /// Seconds before automatic try `n` (1, 2, …): 2, 4, 8, 16, then 30.
    nonisolated static func backoff(_ tries: Int) -> Int {
        min(30, 1 << max(1, min(tries, 5)))
    }

    var isRunning: Bool { task != nil }

    var total: Int64 { files.reduce(0) { $0 + $1.size } }

    func start() {
        guard task == nil else { return }
        let previous = drainingTask
        drainingTask = nil
        tries = 0
        failedForConnection = false
        state = .downloading(ParakeetUltraModel.bytesOnDisk(in: directory, files: files))
        task = Task { [weak self] in
            // Cancellation can leave URLSession callbacks or file promotion still running.
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            self.bytesAtLastStop = ParakeetUltraModel.bytesOnDisk(in: self.directory, files: self.files)
            await self.loop()
        }
    }

    func restart() {
        cancel()
        start()
    }

    /// The returned task drains the writer and all superseded writers before deletion.
    @discardableResult
    func cancel() -> Task<Void, Never>? {
        if let task {
            task.cancel()
            drainingTask = task
            self.task = nil
        }
        endBackgroundTime()
        failedForConnection = false
        state = .idle
        return drainingTask
    }

    func loading() {
        state = .loading
    }

    func dropLoad() {
        if state == .loading { state = .idle }
    }

    func settle() {
        guard task == nil else { return }
        state = .idle
    }

    func fail(_ message: String) {
        cancel()
        state = .failed(message)
    }

    func appMovedToBackground() {
        backgroundedAt = Date()
        // A few more seconds from iOS, so a quick look at another app doesn't stop it.
        if task != nil, backgroundTime == nil {
            backgroundTime = BackgroundTime("Download the multilingual model")
        }
    }

    func appBecameActive(canRetry: Bool, now: Date = Date()) {
        let away = backgroundedAt.map { now.timeIntervalSince($0) } ?? 0
        backgroundedAt = nil
        endBackgroundTime()
        guard canRetry else {
            switch state {
            case .downloading, .waiting:
                cancel()
            case .failed where failedForConnection:
                cancel()
            default:
                break
            }
            return
        }
        switch state {
        case .waiting:
            restart()
        case .failed where failedForConnection:
            restart()
        case .downloading where away > 25:
            restart()
        default:
            break
        }
    }

    private func endBackgroundTime() {
        backgroundTime?.end()
        backgroundTime = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            do {
                try await fetch { [weak self] bytes in
                    await MainActor.run {
                        guard !Task.isCancelled, let self, case .downloading = self.state else { return }
                        self.state = .downloading(bytes)
                    }
                }
                guard !Task.isCancelled else { return }
                task = nil
                endBackgroundTime()
                state = .loading
                onDownloaded?()
                return
            } catch {
                guard !Task.isCancelled else { return }
                let onDisk = ParakeetUltraModel.bytesOnDisk(in: directory, files: files)
                if onDisk > bytesAtLastStop {
                    tries = 0
                }
                bytesAtLastStop = onDisk
                tries += 1
                guard Self.triesAgain(after: error), tries < Self.automaticTries else {
                    task = nil
                    endBackgroundTime()
                    failedForConnection = Self.triesAgain(after: error)
                    state = .failed(Self.message(for: error))
                    return
                }
                if backgroundedAt != nil {
                    task = nil
                    endBackgroundTime()
                    state = .waiting(onDisk, retryIn: nil)
                    return
                }
                for remaining in stride(from: backoff(tries), to: 0, by: -1) {
                    state = .waiting(onDisk, retryIn: remaining)
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                }
                state = .downloading(onDisk)
            }
        }
    }

    /// One try: the download beside a watch that publishes its bytes twice a second and ends
    /// it once they stop moving for `stallLimit` (time while iOS had Typr suspended doesn't
    /// count). Returns only once nothing writes to the folder any more.
    nonisolated static func fetch(
        directory: URL,
        files: [ParakeetUltraModel.File],
        base: String,
        session: URLSession,
        stallLimit: Duration,
        publish: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        let bytes = ByteReading(ParakeetUltraModel.bytesOnDisk(in: directory, files: files))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await ParakeetUltraModel.download(to: directory, files: files, base: base, session: session) {
                    bytes.value = $0
                }
            }
            group.addTask {
                let clock = ContinuousClock()
                let poll = Duration.milliseconds(500)
                var last = bytes.value
                var since = clock.now
                var polled = since
                while true {
                    try await Task.sleep(for: poll)
                    let now = clock.now
                    let resumed = now - polled > poll + StallWatch.suspensionGap
                    polled = now
                    let current = bytes.value
                    await publish(current)
                    if current != last || resumed {
                        last = current
                        since = now
                    } else if now - since >= stallLimit {
                        throw StallWatch.Stalled()
                    }
                }
            }
            // The download finishing, or either one throwing, ends the other.
            _ = try await group.next()
            group.cancelAll()
        }
    }

    /// A dropped connection, a download that stopped moving, a busy server or a damaged file
    /// is tried again; a refused request, a full iPhone or anything else waits for the person.
    nonisolated static func triesAgain(after error: Error) -> Bool {
        if error is StallWatch.Stalled || error is URLError { return true }
        switch error as? ParakeetUltraModel.DownloadError {
        case .badStatus(let status):
            return status == 0 || status == 408 || status == 429 || status >= 500
        case .corrupt:
            return true
        case nil:
            return false
        }
    }

    nonisolated static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        return (ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError)
            || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC))
    }

    nonisolated static func message(for error: Error) -> String {
        if isOutOfSpace(error) {
            return "The multilingual model needs \(ParakeetUltraTranscriber.downloadSize) of free space. Free some up, then try again."
        }
        if error is StallWatch.Stalled || error is URLError {
            return "The multilingual model's download stopped. Check your connection and try again."
        }
        switch error as? ParakeetUltraModel.DownloadError {
        case .badStatus(429):
            return "Hugging Face is limiting downloads right now. Try again in a few minutes."
        case .badStatus(let status):
            return "The multilingual model didn't download (error \(status)). Try again later."
        case .corrupt:
            return "Part of the multilingual model arrived damaged. Try again."
        case nil:
            return "The multilingual model didn't download. Try again."
        }
    }

    /// What Typr says about it, or nil while there's nothing to say.
    var status: String? {
        switch state {
        case .idle:
            nil
        case .downloading(let bytes):
            "Downloading the multilingual model: \(Self.size(bytes)) of \(Self.size(total))"
        case .waiting(_, let seconds?):
            "The multilingual model's download stopped. Trying again in \(seconds) s."
        case .waiting(_, nil):
            "The multilingual model's download resumes when you open Typr."
        case .loading:
            "Getting the multilingual model ready"
        case .failed(let message):
            message
        }
    }

    /// The share on disk, while it downloads or waits.
    var fraction: Double? {
        switch state {
        case .downloading(let bytes), .waiting(let bytes, _):
            total > 0 ? min(1, Double(bytes) / Double(total)) : 0
        default:
            nil
        }
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    nonisolated static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

/// Bytes written by the download and read by its watch.
private nonisolated final class ByteReading: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Int64

    init(_ value: Int64) {
        current = value
    }

    var value: Int64 {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// The multilingual model's download or load, on home and under its switch in Experimental:
/// what it's doing, that Typr dictates with its usual model meanwhile, and after a failure
/// Try again and Turn off.
struct MultilingualModelStatus: View {
    let download: ParakeetUltraDownload
    let retry: () -> Void
    let turnOff: () -> Void

    var body: some View {
        if let status = download.status {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: download.isFailed ? "exclamationmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(download.isFailed ? TyprTheme.danger : TyprTheme.textMuted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(status)
                            .font(.system(size: 13))
                            .foregroundStyle(TyprTheme.textBase)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("multilingual-model-status")
                        Text("Until then, Typr uses its usual model.")
                            .font(.system(size: 12))
                            .foregroundStyle(TyprTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                        .tint(TyprTheme.textBase)
                }
                if download.isFailed {
                    HStack(spacing: 8) {
                        Button("Try again", action: retry)
                            .accessibilityIdentifier("multilingual-model-try-again")
                        Button("Turn off", action: turnOff)
                            .accessibilityIdentifier("multilingual-model-turn-off")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TyprTheme.textBase)
                    .buttonStyle(MultilingualStatusButtonStyle())
                }
            }
            .padding(14)
            .background(
                download.isFailed ? TyprTheme.dangerSurface : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}

private struct MultilingualStatusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.15 : 0.09), in: Capsule())
    }
}
