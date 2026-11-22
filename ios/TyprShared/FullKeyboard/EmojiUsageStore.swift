import Foundation

// Adapted from anomalyco/hex ios/HEXShared/FullKeyboard/Emoji/EmojiUsageStore.swift at
// d65b02d36efbaf1ff771420e89c0632dea4706cb (MIT).

/// The emoji you pick, for the panel's Frequently used: a count per emoji that halves every ten
/// days, so both how often and how lately count. Only emoji, never words; kept in the App Group.
@MainActor
final class EmojiUsageStore {
    static let halfLife: TimeInterval = 10 * 86_400
    /// The most emoji remembered; the faintest go first.
    static let capacity = 120
    private static let key = "keyboard.emojiUsage"

    private let defaults: UserDefaults?
    private let now: () -> Date
    /// Emoji to [score at the last use, last use as seconds since 1970].
    private var usage: [String: [Double]]

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup), now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        usage = defaults?.dictionary(forKey: Self.key) as? [String: [Double]] ?? [:]
    }

    func record(_ emoji: String) {
        let time = now().timeIntervalSince1970
        usage[emoji] = [score(of: emoji, at: time) + 1, time]
        if usage.count > Self.capacity,
           let faintest = usage.keys.min(by: { score(of: $0, at: time) < score(of: $1, at: time) }) {
            usage[faintest] = nil
        }
        defaults?.set(usage, forKey: Self.key)
    }

    private func score(of emoji: String, at time: TimeInterval) -> Double {
        guard let stored = usage[emoji], stored.count == 2 else { return 0 }
        return stored[0] * pow(0.5, max(0, time - stored[1]) / Self.halfLife)
    }

    /// Your emoji, most used first; ties in emoji order.
    func ranked(limit: Int) -> [String] {
        let time = now().timeIntervalSince1970
        return usage.keys
            .map { ($0, score(of: $0, at: time)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit)
            .map(\.0)
    }
}
