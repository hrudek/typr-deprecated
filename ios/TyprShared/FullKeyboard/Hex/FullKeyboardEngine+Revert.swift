import UIKit

// Hex's file without its `FullKeyboardEngine` extension, which arrives with Hex's engine.
extension AutocorrectEngine {
    /// The latest autocorrection, which the strip offers to revert while the cursor is right
    /// after it, as Apple's keyboard offers its bubble (black box, iOS 27.2): delete takes only
    /// the space or mark after it, and the cursor may come back to it later.
    struct AppliedCorrection: Equatable {
        /// One word the revert puts back as typed (`from`), and what autocorrect made it.
        struct Change: Equatable {
            let from: String
            let to: String
            /// The language the fix was made in, for what the keys learn from reverting it.
            var language: KeyboardLanguage? = nil
        }

        /// What you typed ("teh", "well see", "ofthe").
        let original: String
        /// What autocorrect put in its place, without the space or mark after it.
        let corrected: String
        /// The words in `original` that autocorrect changed; the revert keeps each as typed.
        let changes: [Change]
        /// The text before the cursor right after `corrected`.
        let anchor: String

        /// How much of the text before the cursor must read as `anchor`: hosts give a window of
        /// it, which may start elsewhere once the text is long.
        static let anchorTail = 64

        /// Whether the cursor is right after `corrected`, with the same text before it.
        func isAtEnd(of before: String?) -> Bool {
            guard let before, before.hasSuffix(corrected) else { return false }
            guard anchor.count >= Self.anchorTail, before.count >= Self.anchorTail else { return before == anchor }
            return before.suffix(Self.anchorTail) == anchor.suffix(Self.anchorTail)
        }
    }
}
