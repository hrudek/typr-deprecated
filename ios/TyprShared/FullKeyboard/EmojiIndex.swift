import Foundation

// Adapted from anomalyco/hex ios/HEXShared/FullKeyboard/Emoji/EmojiLibrary.swift and
// EmojiSuggester.swift at d65b02d36efbaf1ff771420e89c0632dea4706cb (MIT).

/// The emoji panel's categories, in the order its bar shows them.
nonisolated enum EmojiCategory: Int, CaseIterable, Sendable {
    case smileysPeople
    case animalsNature
    case foodDrink
    case activity
    case travelPlaces
    case objects
    case symbols
    case flags

    var title: String {
        switch self {
        case .smileysPeople: "Smileys and people"
        case .animalsNature: "Animals and nature"
        case .foodDrink: "Food and drink"
        case .activity: "Activity"
        case .travelPlaces: "Travel and places"
        case .objects: "Objects"
        case .symbols: "Symbols"
        case .flags: "Flags"
        }
    }

    var symbol: String {
        switch self {
        case .smileysPeople: "face.smiling"
        case .animalsNature: "teddybear"
        case .foodDrink: "fork.knife"
        case .activity: "soccerball"
        case .travelPlaces: "car"
        case .objects: "lightbulb"
        case .symbols: "music.note"
        case .flags: "flag"
        }
    }
}

/// The emoji catalog and the words that suggest them, read from WordData/emoji-index.txt
/// (ios/tools/emoji/build.py). The file is memory-mapped and its words are searched in place,
/// so only the catalog's strings and one offset per word sit on the keyboard's heap.
nonisolated final class EmojiIndex: @unchecked Sendable {
    let emoji: [String]
    let categories: [EmojiCategory]
    private let entryByEmoji: [String: Int]
    private let data: Data
    /// Where each word line's key starts, in file (UTF-8) order.
    private let wordLines: [Int32]

    private init(data: Data, emoji: [String], categories: [EmojiCategory], wordLines: [Int32]) {
        self.data = data
        self.emoji = emoji
        self.categories = categories
        self.wordLines = wordLines
        entryByEmoji = Dictionary(emoji.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func load(bundle: Bundle = .main) -> EmojiIndex? {
        guard let url = bundle.url(forResource: "emoji-index", withExtension: "txt", subdirectory: "WordData"),
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return load(data: data)
    }

    static func load(data: Data) -> EmojiIndex? {
        var emoji: [String] = []
        var categories: [EmojiCategory] = []
        var wordLines: [Int32] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var lineStart = 0
            while lineStart < bytes.count {
                var lineEnd = lineStart
                while lineEnd < bytes.count, bytes[lineEnd] != 10 { lineEnd += 1 }
                defer { lineStart = lineEnd + 1 }
                guard lineEnd - lineStart > 2, bytes[lineStart + 1] == 9 else { continue }
                let body = lineStart + 2
                switch bytes[lineStart] {
                case UInt8(ascii: "W"):
                    wordLines.append(Int32(body))
                case UInt8(ascii: "E"):
                    var tab = body
                    while tab < lineEnd, bytes[tab] != 9 { tab += 1 }
                    guard tab + 1 < lineEnd,
                          let category = EmojiCategory(rawValue: Int(bytes[tab + 1]) - Int(UInt8(ascii: "0"))) else { continue }
                    emoji.append(String(decoding: UnsafeBufferPointer(rebasing: bytes[body..<tab]), as: UTF8.self))
                    categories.append(category)
                default:
                    break
                }
            }
        }
        guard !emoji.isEmpty else { return nil }
        return EmojiIndex(data: data, emoji: emoji, categories: categories, wordLines: wordLines)
    }

    func entry(for emoji: String) -> Int? { entryByEmoji[emoji] }

    /// The emoji a folded word suggests, best first; empty when none.
    func emoji(forWord word: String) -> [String] {
        var key = word
        return key.withUTF8 { needle in
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [String] in
                let bytes = raw.bindMemory(to: UInt8.self)
                var low = 0
                var high = wordLines.count - 1
                while low <= high {
                    let mid = (low + high) / 2
                    let start = Int(wordLines[mid])
                    let order = Self.compare(needle, bytes, at: start)
                    if order == 0 { return entries(bytes, from: start + needle.count + 1).map { self.emoji[$0] } }
                    if order < 0 { high = mid - 1 } else { low = mid + 1 }
                }
                return []
            }
        }
    }

    /// Compares `needle` with the tab-ended key at `start`, byte by byte (the file sorts keys by UTF-8).
    private static func compare(_ needle: UnsafeBufferPointer<UInt8>, _ bytes: UnsafeBufferPointer<UInt8>, at start: Int) -> Int {
        var i = 0
        while true {
            let k = start + i < bytes.count ? bytes[start + i] : 9
            let keyEnded = k == 9
            let needleEnded = i == needle.count
            if keyEnded && needleEnded { return 0 }
            if needleEnded { return -1 }
            if keyEnded { return 1 }
            if needle[i] != k { return needle[i] < k ? -1 : 1 }
            i += 1
        }
    }

    /// Reads "12,40,7" up to the line's end.
    private func entries(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> [Int] {
        var out: [Int] = []
        var value = 0
        var i = start
        while i <= bytes.count {
            let byte: UInt8 = i < bytes.count ? bytes[i] : 10
            if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            } else {
                if value < emoji.count { out.append(value) }
                value = 0
                if byte == 10 { break }
            }
            i += 1
        }
        return out
    }

    /// Up to `limit` emoji for the word just finished ("Herz " → ❤️). Nothing mid-word, after
    /// two spaces, or when the word ends in a digit or punctuation.
    func suggestions(before: String?, limit: Int = 3) -> [String] {
        guard let before, before.hasSuffix(" "), !before.hasSuffix("  ") else { return [] }
        let trimmed = before.dropLast()
        guard trimmed.last?.isLetter == true, let word = Self.words(in: String(trimmed.suffix(40))).last else { return [] }
        for form in Self.forms(of: word) {
            let found = emoji(forWord: form)
            if !found.isEmpty { return Array(found.prefix(limit)) }
        }
        return []
    }

    /// NFD, combining marks dropped, lowercased, curly apostrophes straightened (as build.py folds).
    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.replacingOccurrences(of: "\u{2019}", with: "'").decomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.properties.canonicalCombiningClass.rawValue == 0 {
            scalars.append(scalar)
        }
        return String(scalars).lowercased()
    }

    static func words(in text: String) -> [String] {
        fold(text).split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// The word, then the stems German and English endings leave ("Herzen" → "herz", "hearts" → "heart").
    static func forms(of word: String) -> [String] {
        var out = [word]
        func add(_ form: String) {
            if form.count >= 2, !out.contains(form) { out.append(form) }
        }
        guard word.count >= 4 else { return out }
        for suffix in ["en", "er", "es", "e", "s", "n"] where word.hasSuffix(suffix) {
            add(String(word.dropLast(suffix.count)))
        }
        if word.hasSuffix("ies") { add(String(word.dropLast(3)) + "y") }
        return out
    }
}
