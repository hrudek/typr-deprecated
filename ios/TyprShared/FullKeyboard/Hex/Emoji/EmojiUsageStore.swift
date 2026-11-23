import Foundation

/// The emoji you use, kept in the App Group on this iPhone: a count that fades by half every
/// ten days (so both how often and how lately count) and the skin tone you last picked for
/// each emoji. Only emoji and their usage metadata are stored.
@MainActor
final class EmojiUsageStore {
    static let halfLife: TimeInterval = 10 * 86_400
    /// The most emoji remembered; the faintest go first.
    static let capacity = 120

    private enum Key {
        static let usage = "hex.emoji.usage"
        static let tones = "hex.emoji.tones"
    }

    private let defaults: UserDefaults?
    private let now: () -> Date
    /// Base emoji to [score at `last`, last use as seconds since 1970].
    private var usage: [String: [Double]]
    /// Base emoji to the skin tone picked for it: 1 (light) to 5 (dark).
    private var tones: [String: Int]

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup), now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        usage = defaults?.dictionary(forKey: Key.usage) as? [String: [Double]] ?? [:]
        tones = defaults?.dictionary(forKey: Key.tones) as? [String: Int] ?? [:]
    }

    /// You picked `base` (the emoji without a skin tone).
    func record(_ base: String) {
        let time = now().timeIntervalSince1970
        usage[base] = [score(of: base, at: time) + 1, time]
        if usage.count > Self.capacity {
            let faintest = usage.keys.min { score(of: $0, at: time) < score(of: $1, at: time) }
            if let faintest { usage[faintest] = nil }
        }
        defaults?.set(usage, forKey: Key.usage)
    }

    private func score(of base: String, at time: TimeInterval) -> Double {
        guard let stored = usage[base], stored.count == 2 else { return 0 }
        return stored[0] * pow(0.5, max(0, time - stored[1]) / Self.halfLife)
    }

    /// Your emoji, most used first, with scores scaled so the first is 1.
    func ranked(limit: Int = 40) -> [(emoji: String, score: Float)] {
        let time = now().timeIntervalSince1970
        let scored = usage.keys
            .map { ($0, score(of: $0, at: time)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
        guard let top = scored.first?.1, top > 0 else { return [] }
        return scored.map { ($0.0, Float($0.1 / top)) }
    }

    /// 0 for the default yellow, else 1 (light) to 5 (dark).
    func tone(for base: String) -> Int {
        tones[base] ?? 0
    }

    func setTone(_ tone: Int, for base: String) {
        tones[base] = tone == 0 ? nil : tone
        defaults?.set(tones, forKey: Key.tones)
    }

    var isEmpty: Bool { usage.isEmpty && tones.isEmpty }

    func clear() {
        usage = [:]
        tones = [:]
        defaults?.removeObject(forKey: Key.usage)
        defaults?.removeObject(forKey: Key.tones)
    }
}
