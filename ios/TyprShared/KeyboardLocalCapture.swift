import Foundation

/// Where a Typr key dictation runs: the Typr app (its selected engine, warm mic or cold-start
/// handoff) or, with Settings > Experimental's Apple Speech switch, the keyboard itself
/// (`KeyboardLocalDictation`, Hex's KeyboardLocalDictation, anomalyco/hex #1999 #2089 #2045).
enum KeyboardDictationRoute: Equatable {
    case app
    case keyboard

    /// Memory left below iOS's limit for this keyboard (`os_proc_available_memory`) that the
    /// first in-keyboard dictation needs: the capture web view, its page and the recording
    /// screen, with margin (Hex's measure). Later ones reuse the loaded web view.
    static let startHeadroomNeeded = 32 * 1_048_576
    static let restartHeadroomNeeded = 24 * 1_048_576

    /// Where iOS doesn't say (0, the simulator), there is memory.
    static func hasMemory(available: Int, captureLoaded: Bool) -> Bool {
        available == 0 || available >= (captureLoaded ? restartHeadroomNeeded : startHeadroomNeeded)
    }

    /// A running warm mic keeps the selected engine; anything the keyboard lacks hands off to Typr.
    static func choose(
        keyboardEnabled: Bool,
        warm: Bool,
        supported: Bool,
        speechReady: Bool,
        microphoneAllowed: Bool,
        availableMemory: Int,
        captureLoaded: Bool
    ) -> KeyboardDictationRoute {
        guard keyboardEnabled, !warm, supported, speechReady, microphoneAllowed,
              hasMemory(available: availableMemory, captureLoaded: captureLoaded) else { return .app }
        return .keyboard
    }
}

/// The in-keyboard dictation's states. Armed is the Typr key's touch-down before it is a hold
/// (kept) or a tap, slide or cancelled touch (discarded); it shows nothing.
struct KeyboardLocalCapture {
    enum Phase: Equatable {
        case idle
        case armed(jobID: String, at: TimeInterval)
        case recording(jobID: String, at: TimeInterval)
        case transcribing(jobID: String)
        case finished(jobID: String, resultID: String, transcript: String)
        case failed(message: String, until: TimeInterval)
    }

    enum StartAction: Equatable {
        /// The armed capture becomes this dictation.
        case kept(jobID: String)
        /// Open the microphone for a new job.
        case begin(jobID: String)
        case ignored
    }

    /// A touch-down capture neither kept nor dropped by then is dropped, so a lost touch never
    /// leaves the microphone open.
    static let armedTimeout: TimeInterval = 3
    static let failureShownFor: TimeInterval = 6

    private(set) var phase: Phase = .idle

    var isActive: Bool {
        switch phase {
        case .armed, .recording, .transcribing: true
        default: false
        }
    }

    /// Whether audio or a started microphone for `jobID` belongs to the running capture; a late
    /// start of a dropped job must close its microphone.
    func isCapturing(_ jobID: String) -> Bool {
        switch phase {
        case .armed(let current, _), .recording(let current, _): current == jobID
        default: false
        }
    }

    /// Audio for `jobID` still goes to transcription: the page's last chunks arrive after Done.
    func acceptsAudio(_ jobID: String) -> Bool {
        if case .transcribing(let current) = phase { return current == jobID }
        return isCapturing(jobID)
    }

    mutating func arm(jobID: String, at now: TimeInterval) -> Bool {
        guard !isActive, !hasUndeliveredResult else { return false }
        phase = .armed(jobID: jobID, at: now)
        return true
    }

    mutating func start(jobID: String, at now: TimeInterval) -> StartAction {
        if case .armed(let armed, let at) = phase {
            phase = .recording(jobID: armed, at: at)
            return .kept(jobID: armed)
        }
        guard !isActive, !hasUndeliveredResult else { return .ignored }
        phase = .recording(jobID: jobID, at: now)
        return .begin(jobID: jobID)
    }

    /// The dropped job, if a capture was armed.
    mutating func discard() -> String? {
        guard case .armed(let jobID, _) = phase else { return nil }
        phase = .idle
        return jobID
    }

    /// Drops `jobID` if it is still armed after `armedTimeout`.
    mutating func expireArmed(jobID: String, now: TimeInterval) -> Bool {
        guard case .armed(let current, let at) = phase, current == jobID,
              now - at >= Self.armedTimeout else { return false }
        phase = .idle
        return true
    }

    /// The job whose audio now goes to transcription.
    mutating func stop() -> String? {
        guard case .recording(let jobID, _) = phase else { return nil }
        phase = .transcribing(jobID: jobID)
        return jobID
    }

    mutating func cancel() {
        phase = .idle
    }

    /// An empty transcript ends quietly.
    mutating func finish(jobID: String, transcript: String, resultID: String) {
        guard case .transcribing(let current) = phase, current == jobID else { return }
        phase = transcript.isEmpty ? .idle : .finished(jobID: jobID, resultID: resultID, transcript: transcript)
    }

    /// A failure while armed drops the capture silently: the kept touch then hands off to Typr.
    mutating func fail(_ message: String, now: TimeInterval) {
        if case .armed = phase {
            phase = .idle
            return
        }
        phase = .failed(message: message, until: now + Self.failureShownFor)
    }

    mutating func delivered(resultID: String) {
        if case .finished(_, let current, _) = phase, current == resultID { phase = .idle }
    }

    private var hasUndeliveredResult: Bool {
        if case .finished = phase { return true }
        return false
    }

    /// What the keyboard shows and inserts, like the app's bridge snapshot; nil while idle or armed.
    mutating func snapshot(now: TimeInterval, loudnessDB: Float) -> KeyboardSnapshot? {
        switch phase {
        case .idle, .armed:
            return nil
        case .recording(let jobID, let at):
            return KeyboardSnapshot(state: .recording, heartbeat: now, expiresAt: now + 60,
                                    recordingStartedAt: at, loudnessDB: loudnessDB, jobID: jobID)
        case .transcribing(let jobID):
            return KeyboardSnapshot(state: .transcribing, heartbeat: now, expiresAt: now + 60, jobID: jobID)
        case .finished(let jobID, let resultID, let transcript):
            return KeyboardSnapshot(state: .offline, heartbeat: now, expiresAt: now, jobID: jobID,
                                    resultID: resultID, transcript: transcript)
        case .failed(let message, let until):
            guard until > now else {
                phase = .idle
                return nil
            }
            return KeyboardSnapshot(state: .failed, heartbeat: now, expiresAt: until, message: message)
        }
    }

    /// The app's text steps that need no app code: the style, Format lists, Spoken
    /// punctuation, End with a period and Lowercase.
    @MainActor
    static func text(from heard: String, style: DictationStyle, settings: TyprSettings) -> String {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let formatted = TranscriptFormatter.format(
            trimmed,
            style: style,
            language: settings.dictationLanguage,
            lists: settings[experiment: .formatLists],
            punctuation: settings[experiment: .spokenPunctuation],
            endsWithPeriod: settings.dictationEndsWithPeriod
        )
        return settings.dictationLowercase ? TranscriptFormatter.lowercased(formatted, style: style) : formatted
    }
}

/// The keyboard's hidden capture page (`KeyboardLocalDictation`, Hex's getUserMedia page):
/// records with getUserMedia and posts 16-bit PCM chunks to the `typr` message handler.
enum KeyboardCapturePage {
    /// A stop while a start waits makes that start stale: it releases what it opened.
    static let html = """
    <!doctype html><meta charset="utf-8"><script>
    let ctx, stream, source, node, running = false, generation = 0, revive = null;
    const post = (m) => webkit.messageHandlers.typr.postMessage(m);
    const release = (s, c) => {
      if (s) s.getTracks().forEach((t) => t.stop());
      if (c) c.close().catch(() => {});
    };
    async function typrStart() {
      if (running) return;
      running = true;
      const start = ++generation;
      const stale = () => start !== generation;
      let s = null, c = null;
      try {
        s = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
        if (stale()) return release(s);
        c = new AudioContext();
        await c.resume();
        if (stale()) return release(s, c);
        stream = s;
        ctx = c;
        source = ctx.createMediaStreamSource(stream);
        node = ctx.createScriptProcessor(4096, 1, 1);
        node.onaudioprocess = (event) => {
          if (!running) return;
          const input = event.inputBuffer.getChannelData(0);
          const pcm = new Int16Array(input.length);
          let peak = 0;
          for (let i = 0; i < input.length; i++) {
            const v = Math.max(-1, Math.min(1, input[i]));
            peak = Math.max(peak, Math.abs(v));
            pcm[i] = v < 0 ? v * 0x8000 : v * 0x7fff;
          }
          const bytes = new Uint8Array(pcm.buffer);
          let binary = "";
          for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
          post({ type: "pcm", data: btoa(binary), peak });
        };
        source.connect(node);
        node.connect(ctx.destination);
        // iOS may suspend the context for other audio without resuming it.
        revive = setInterval(() => {
          if (running && ctx && ctx.state !== "running" && ctx.state !== "closed") ctx.resume().catch(() => {});
        }, 250);
        post({ type: "started", rate: ctx.sampleRate });
      } catch (error) {
        if (stale()) return release(s, c);
        running = false;
        release(s, c);
        post({ type: "error", message: (error && (error.name + ": " + error.message)) || String(error) });
      }
    }
    async function typrStop() {
      generation++;
      const wasRunning = running;
      running = false;
      if (revive) { clearInterval(revive); revive = null; }
      // Detached before awaiting: a start during the close owns the globals again.
      const s = stream, c = ctx, src = source, n = node;
      ctx = stream = source = node = null;
      try { n && n.disconnect(); src && src.disconnect(); } catch (e) {}
      if (s) s.getTracks().forEach((t) => t.stop());
      if (wasRunning) post({ type: "stopped" });
      if (c) { try { await c.close(); } catch (e) {} }
    }
    </script>
    """
}
