import Foundation

/// Dictated lists and line breaks as lines, with string rules and no model, in German and
/// English. With Settings › Style › Format lists on, runs inside every style but Verbatim, after
/// its fillers and before spoken punctuation and the style's own capitalization and final
/// period (`TranscriptFormatter.format(_:style:language:lists:punctuation:)`).
/// Ported from Hex (anomalyco/hex `ios/HEXShared/SpokenLists.swift` at d65b02d3, MIT), English
/// table unchanged, German table added; see THIRD_PARTY_NOTICES.md.
///
/// - "neue Zeile", "neuer Absatz", "Zeilenumbruch" ("new line", "new paragraph", "line break")
///   become one or two line breaks, and the commas around them go (in German the comma before
///   one line break stays: "Hallo Anna,"). Never at the very start,
///   after a determiner ("eine neue Zeile", "a new line of shoes"), after a German lowercase
///   word that could modify a noun ("eine völlig neue Zeile"), or before a word that continues
///   the noun ("neue Zeile einfügen", "new line of").
/// - Numbered lists: "erstens … zweitens …" ("als Erstes …", "first … second …", "1st … 2nd …"),
///   "Punkt eins … Punkt zwei …" ("Nummer", "Schritt", "number", "step", "item", "point"), or
///   "eins, … zwei, …" ("one, … two, …", English "1. … 2. …") become "1. …" lines. The markers
///   count up from one, there are at least two items, none is empty, and every marker starts a
///   clause: the start, after a mark (".", ",", ";", ":", …) or a line break, or after
///   connectors ("und", "dann", "and", "then") that do. In German only the first marker must:
///   "Erstens Milch zweitens Eier" is a list, "Das ist erstens teuer und zweitens hässlich"
///   stays prose. A bare number needs its comma ("eins, …"); "zu guter
///   Letzt" or "finally" ends a list of two or more.
/// - Bullets: "Spiegelstrich", "Aufzählungspunkt", "bullet", "bullet point", "next item",
///   "dash" said at least twice become "- …" lines, as the Notes style writes bullets.
/// - Text before the first marker is its own line, given a colon unless it ends a sentence;
///   a last item ends at its first sentence, and what follows is its own line. Items start
///   with a capital and lose a trailing comma, period, "und", "oder", "and" or "or".
nonisolated enum SpokenLists {
    /// `language` picks the word table; Automatic uses English only for text that reads as
    /// English (`TranscriptFormatter.readsAsEnglish`), else German.
    static func format(_ text: String, language: DictationLanguage) -> String {
        guard !text.isEmpty else { return text }
        let table = Table.forLanguage(language, text: text)
        return listing(breaking(text, table), table)
    }

    private struct Token {
        let text: String
        let isWord: Bool
        /// Lowercased, accents folded: "Aufzählungspunkt" reads "aufzahlungspunkt".
        let folded: String
    }

    fileprivate static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Alternating words (letters, digits, apostrophes) and the separators between them.
    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsWord: Bool?
        func flush() {
            guard let isWord = currentIsWord else { return }
            let folded = isWord ? fold(current) : current
            tokens.append(Token(text: current, isWord: isWord, folded: folded))
        }
        for character in text {
            let isWord = character.isLetter || character.isNumber || character == "'" || character == "’"
            if currentIsWord == isWord {
                current.append(character)
            } else {
                flush()
                current = String(character)
                currentIsWord = isWord
            }
        }
        flush()
        return tokens
    }

    private static func joined(_ tokens: ArraySlice<Token>) -> String {
        tokens.map(\.text).joined()
    }

    /// Marks that end a clause, so a marker after them starts one.
    private static let clauseBoundaries: Set<Character> = [".", ",", ";", ":", "!", "?", "…", "—", "–", "\n", "(", "¿", "¡"]

    private struct Words {
        let tokens: [Token]
        let table: Table

        func isWord(_ index: Int) -> Bool { tokens.indices.contains(index) && tokens[index].isWord }

        func spacesOnly(_ index: Int) -> Bool {
            tokens.indices.contains(index) && !tokens[index].isWord
                && tokens[index].text.allSatisfy { $0 == " " || $0 == "\t" }
        }

        /// Where `words` said one after another (spaces between) starting at `index` end.
        func phrase(_ words: [String], at index: Int) -> Int? {
            var position = index
            for (number, word) in words.enumerated() {
                if number > 0 {
                    guard spacesOnly(position) else { return nil }
                    position += 1
                }
                guard isWord(position), tokens[position].folded == word else { return nil }
                position += 1
            }
            return position
        }

        /// The word right after the separator at `end`, when only spaces come between.
        func nextWord(after end: Int) -> String? {
            spacesOnly(end) && isWord(end + 1) ? tokens[end + 1].folded : nil
        }

        /// The word right before `index`, when only spaces come between.
        func previousWord(before index: Int) -> String? {
            index >= 2 && spacesOnly(index - 1) && isWord(index - 2) ? tokens[index - 2].folded : nil
        }

        /// Whether the word at `index` starts a clause: the text's start, after a mark or a
        /// line break, or after connectors ("and then") that start one.
        func startsClause(_ index: Int) -> Bool {
            var position = index
            while position >= 2 {
                if tokens[position - 1].text.contains(where: clauseBoundaries.contains) { return true }
                guard table.connectors.contains(tokens[position - 2].folded) else { return false }
                position -= 2
            }
            return true
        }

        /// Whether a command word at `index` reads as a command, not part of a noun phrase: at a
        /// clause start, or not after a determiner ("a new line"). In German not after a
        /// lowercase word that could modify a noun ("eine völlig neue Zeile", "ganz neuer Absatz").
        func commandMayFollow(_ index: Int) -> Bool {
            if startsClause(index) { return true }
            guard let previous = previousWord(before: index) else { return true }
            if table.determiners.contains(previous) || table.modifiers.contains(previous) { return false }
            guard let first = tokens[index - 2].text.first, first.isLowercase else { return true }
            return !(previous.count > 3 && table.modifierEndings.contains { previous.hasSuffix($0) })
        }

        /// The separator after the word ending at `end`, "" at the end of the text.
        func separator(at end: Int) -> String {
            tokens.indices.contains(end) && !tokens[end].isWord ? tokens[end].text : ""
        }

        /// A number said as a word or written in digits ("zwei", "two", "2"), 1 to 20.
        func number(at index: Int) -> Int? {
            guard isWord(index) else { return nil }
            let word = tokens[index].folded
            if let value = table.cardinals[word] { return value }
            guard word.count <= 2, word.allSatisfy(\.isASCII), let value = Int(word), (1...20).contains(value) else { return nil }
            return value
        }
    }

    private static func breaking(_ text: String, _ table: Table) -> String {
        let words = Words(tokens: tokenize(text), table: table)
        let tokens = words.tokens
        var out = ""
        var index = 0
        var sawWord = false
        while index < tokens.count {
            if tokens[index].isWord, sawWord, let (breaks, end) = lineBreak(at: index, words) {
                while let last = out.last, last == " " || last == "\t" || last == ";"
                    || (last == "," && !(table.keepsCommaBeforeBreak && breaks == "\n")) {
                    out.removeLast()
                }
                out += breaks
                index = end
                if index < tokens.count, !tokens[index].isWord {
                    out += tokens[index].text.drop { " \t,.;:".contains($0) }
                    index += 1
                }
                continue
            }
            sawWord = sawWord || tokens[index].isWord
            out += tokens[index].text
            index += 1
        }
        return out
    }

    private static func lineBreak(at index: Int, _ words: Words) -> (String, Int)? {
        for (phrase, breaks) in words.table.breaks {
            guard let end = words.phrase(phrase, at: index) else { continue }
            if !words.commandMayFollow(index) { return nil }
            if let next = words.nextWord(after: end), words.table.breakFollowers.contains(next) { return nil }
            return (breaks, end)
        }
        return nil
    }

    private enum Family: Equatable {
        case ordinal
        case cardinal
        case keyword(String)
        case bullet
    }

    private struct Marker {
        let family: Family
        /// The item's number; 0 for "finally".
        let value: Int
        let start: Int
        let end: Int
    }

    private static func markers(_ words: Words) -> [Marker] {
        var found: [Marker] = []
        var index = 0
        while index < words.tokens.count {
            if words.isWord(index), let marker = marker(at: index, words) {
                found.append(marker)
                index = marker.end
            } else {
                index += 1
            }
        }
        return found
    }

    private static func marker(at index: Int, _ words: Words) -> Marker? {
        let table = words.table
        let word = words.tokens[index].folded

        for (phrase, needsMark) in table.finals {
            guard let end = words.phrase(phrase, at: index),
                  words.startsClause(index) || (table.laterMarkersFollowWords && !needsMark) else { continue }
            let after = words.separator(at: end)
            if needsMark, !after.hasPrefix(","), !after.hasPrefix(":") { continue }
            return Marker(family: .ordinal, value: 0, start: index, end: end)
        }
        for (phrase, value) in table.ordinalPhrases {
            guard let end = words.phrase(phrase, at: index), words.startsClause(index) else { continue }
            return Marker(family: .ordinal, value: value, start: index, end: end)
        }
        if table.keywords.contains(word), words.spacesOnly(index + 1), let value = words.number(at: index + 2),
           words.startsClause(index) || (table.laterMarkersFollowWords && value > 1 && words.commandMayFollow(index)) {
            return Marker(family: .keyword(word), value: value, start: index, end: index + 3)
        }
        for (phrase, strict) in table.bullets {
            guard let end = words.phrase(phrase, at: index) else { continue }
            if !(strict ? words.startsClause(index) : words.commandMayFollow(index)) { return nil }
            if let next = words.nextWord(after: end), table.bulletFollowers.contains(next) { return nil }
            return Marker(family: .bullet, value: 1, start: index, end: end)
        }
        if let value = table.ordinal(word), words.startsClause(index) || (table.laterMarkersFollowWords && value > 1) {
            if !table.ofAll.isEmpty, words.spacesOnly(index + 1), words.phrase(table.ofAll, at: index + 2) != nil {
                return Marker(family: .ordinal, value: value, start: index, end: index + 1 + 2 * table.ofAll.count)
            }
            if let next = words.nextWord(after: index + 1), table.ordinalFollowers.contains(next) { return nil }
            return Marker(family: .ordinal, value: value, start: index, end: index + 1)
        }
        if let value = words.number(at: index), words.startsClause(index) {
            // A bare number counts only with its mark and a space after: "one, eggs", "1. eggs",
            // never "1:30" or "1.5"; in German never "1." ("1. Mai, 2. Juni").
            let separator = words.separator(at: index + 1)
            guard let mark = separator.first, table.cardinalMarks.contains(mark),
                  separator.dropFirst().first?.isWhitespace ?? (index + 2 >= words.tokens.count) else { return nil }
            return Marker(family: .cardinal, value: value, start: index, end: index + 1)
        }
        return nil
    }

    /// The lists among `markers` in order: numbered runs counting up from 1, and two bullets or
    /// more.
    private static func lists(_ markers: [Marker]) -> [[Marker]] {
        var runs: [[Marker]] = []
        for (position, first) in markers.enumerated() {
            if first.family == .bullet {
                let run = markers[position...].filter { $0.family == .bullet }
                if run.count >= 2 { runs.append(Array(run)) }
                continue
            }
            guard first.value == 1 else { continue }
            var run = [first]
            for marker in markers[(position + 1)...] where marker.family == first.family {
                if marker.value == run.count + 1 {
                    run.append(marker)
                } else if marker.value == 0, run.count >= 2 {
                    run.append(marker)
                    break
                }
            }
            if run.count >= 2 { runs.append(run) }
        }
        return runs
    }

    private static func listing(_ text: String, _ table: Table) -> String {
        let words = Words(tokens: tokenize(text), table: table)
        for run in lists(markers(words)) {
            // A run with an empty item ("one, two, three, go") is no list; a later one may be.
            if let formatted = format(run, words) { return formatted }
        }
        return text
    }

    private static func format(_ run: [Marker], _ words: Words) -> String? {
        let tokens = words.tokens
        let table = words.table
        guard let last = run.last else { return nil }

        // The last item ends at its first sentence (or line); what follows is its own line.
        var itemsEnd = tokens.count
        var tailBreak = "\n"
        var sawWord = false
        for index in last.end..<tokens.count {
            if tokens[index].isWord {
                sawWord = true
                continue
            }
            guard sawWord, index + 1 < tokens.count else { continue }
            let separator = tokens[index].text
            if separator.contains("\n") || endsSentence(separator, after: tokens[index - 1].folded) {
                itemsEnd = index
                tailBreak = separator.contains("\n\n") ? "\n\n" : "\n"
                break
            }
        }

        var items: [String] = []
        for (number, marker) in run.enumerated() {
            let end = number + 1 < run.count ? run[number + 1].start : itemsEnd
            var raw = joined(tokens[marker.end..<end])
            // The last item keeps its sentence's mark ("?", "!") but not what follows.
            if number + 1 == run.count, itemsEnd < tokens.count {
                let separator = tokens[itemsEnd].text
                raw += separator.prefix { !$0.isWhitespace }
            }
            let item = cleanItem(raw, table)
            guard !item.isEmpty else { return nil }
            items.append(item)
        }

        var output = ""
        let leadIn = joined(tokens[..<run[0].start])
        let leadTrimmed = String(leadIn.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        if leadTrimmed.hasSuffix("\n") {
            output = leadTrimmed
        } else {
            var lead = stripTrailingConnectors(leadIn.trimmingCharacters(in: .whitespacesAndNewlines), table)
            while let mark = lead.last, ",;-–—".contains(mark) {
                lead.removeLast()
                lead = lead.trimmingCharacters(in: .whitespaces)
            }
            if let mark = lead.last {
                if mark.isLetter || mark.isNumber { lead += ":" }
                output = lead + "\n"
            }
        }

        let isBullet = run[0].family == .bullet
        output += items.enumerated()
            .map { isBullet ? "- " + $0.element : "\($0.offset + 1). " + $0.element }
            .joined(separator: "\n")

        if itemsEnd < tokens.count {
            let tail = joined(tokens[(itemsEnd + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                output += tailBreak + listing(tail, table)
            }
        }
        return output
    }

    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "st", "jr", "sr", "prof", "vs", "etc", "inc", "ltd", "approx", "bzw", "ca", "usw",
        "evtl", "ggf", "vgl", "inkl", "bspw", "nr", "str",
    ]

    /// Whether `separator` ends a sentence after `word`: ".", "!", "?" or "…" then a space,
    /// never after "Dr" or an initial.
    private static func endsSentence(_ separator: String, after word: String) -> Bool {
        guard let markIndex = separator.firstIndex(where: { ".!?…".contains($0) }),
              separator[separator.index(after: markIndex)...].first?.isWhitespace == true else { return false }
        if separator[markIndex] == "." && (abbreviations.contains(word) || (word.count == 1 && word.first?.isLetter == true)) {
            return false
        }
        return true
    }

    /// An item's text: no leading marks, no trailing comma, period, "and" or "or", and a capital
    /// first letter (never on "iPhone" or an address).
    private static func cleanItem(_ raw: String, _ table: Table) -> String {
        var item = String(raw.drop { " \t\n,:.;)-–—".contains($0) })
        var previous = ""
        while previous != item {
            previous = item
            item = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.hasSuffix("..."), let mark = item.last, ",;:.".contains(mark) {
                item.removeLast()
            }
            item = stripTrailingConnectors(item, table)
        }
        return capitalizingFirstWord(item)
    }

    /// `text` without the connectors ("und", "and then") a next item's marker leaves at its end.
    private static func stripTrailingConnectors(_ text: String, _ table: Table) -> String {
        var text = text
        while let space = text.lastIndex(where: { $0 == " " || $0 == "," }) {
            let last = fold(String(text[text.index(after: space)...]))
            guard table.connectors.contains(last) || table.alternatives.contains(last) else { break }
            text = String(text[..<space]).trimmingCharacters(in: .whitespaces)
            while text.last == "," { text.removeLast() }
        }
        return text
    }

    private static func capitalizingFirstWord(_ text: String) -> String {
        guard let first = text.firstIndex(where: \.isLetter) else { return text }
        let word = text[first...].prefix { !$0.isWhitespace }
        if word.contains("@") || word.dropFirst().contains(where: \.isUppercase) { return text }
        var result = text
        result.replaceSubrange(first...first, with: String(text[first]).uppercased())
        return result
    }

    private struct Table {
        /// Phrases that break a line.
        let breaks: [([String], String)]
        /// Words before a phrase that make it a noun, not a command: "a new line", "the bullet".
        let determiners: Set<String>
        /// Words after "new line" that make it a noun: "new line of shoes".
        let breakFollowers: Set<String>
        let connectors: Set<String>
        /// "or", stripped from an item's end like a connector.
        let alternatives: Set<String>
        let ordinals: [String: Int]
        /// Ordinal suffixes written after digits: "1st", "2nd".
        let digitOrdinalSuffixes: [String]
        let ordinalPhrases: [([String], Int)]
        /// Words right after an ordinal that keep it prose: "first time", "second guess".
        let ordinalFollowers: Set<String>
        /// Words an ordinal marker takes along: "first of all", "erstens mal".
        let ofAll: [String]
        /// "finally", "lastly"; the flag asks for a comma after ("last, …").
        let finals: [([String], Bool)]
        let cardinals: [String: Int]
        /// Marks after a bare number that make it a marker: "eins, Eier", "1. eggs".
        let cardinalMarks: String
        /// "number one", "Punkt eins".
        let keywords: Set<String>
        /// Bullet phrases, longest first; the flag asks for a clause start.
        let bullets: [([String], Bool)]
        /// Words right after "bullet" that keep it prose: "bullet points", "bullet train".
        let bulletFollowers: Set<String>
        /// Lowercase words before a line break or bullet that make it a noun: "ganz neue Zeile".
        let modifiers: Set<String>
        /// Endings of a lowercase word (over three letters) that could modify a noun: "völlig".
        let modifierEndings: [String]
        /// "Hallo Anna, neue Zeile" keeps its comma before one line break, as a German letter's
        /// greeting does.
        let keepsCommaBeforeBreak: Bool
        /// Markers after the first ("zweitens", "Punkt zwei") may follow a word, not only start
        /// a clause: German says "Erstens Milch zweitens Eier" without commas.
        let laterMarkersFollowWords: Bool

        init(
            breaks: [([String], String)], determiners: Set<String>, breakFollowers: Set<String>,
            connectors: Set<String>, alternatives: Set<String>, ordinals: [String: Int], digitOrdinalSuffixes: [String],
            ordinalPhrases: [([String], Int)], ordinalFollowers: Set<String>, ofAll: [String],
            finals: [([String], Bool)], cardinals: [String: Int], cardinalMarks: String, keywords: Set<String>,
            bullets: [([String], Bool)], bulletFollowers: Set<String>, modifiers: Set<String> = [],
            modifierEndings: [String] = [], keepsCommaBeforeBreak: Bool = false, laterMarkersFollowWords: Bool = false
        ) {
            let words = { (phrase: [String]) in phrase.map(SpokenLists.fold) }
            let set = { (words: Set<String>) in Set(words.map(SpokenLists.fold)) }
            self.breaks = breaks.map { (words($0.0), $0.1) }
            self.determiners = set(determiners)
            self.breakFollowers = set(breakFollowers)
            self.connectors = set(connectors)
            self.alternatives = set(alternatives)
            self.ordinals = Dictionary(uniqueKeysWithValues: ordinals.map { (SpokenLists.fold($0.key), $0.value) })
            self.digitOrdinalSuffixes = digitOrdinalSuffixes
            self.ordinalPhrases = ordinalPhrases.map { (words($0.0), $0.1) }
            self.ordinalFollowers = set(ordinalFollowers)
            self.ofAll = words(ofAll)
            self.finals = finals.map { (words($0.0), $0.1) }
            self.cardinals = Dictionary(uniqueKeysWithValues: cardinals.map { (SpokenLists.fold($0.key), $0.value) })
            self.cardinalMarks = cardinalMarks
            self.keywords = set(keywords)
            self.bullets = bullets.map { (words($0.0), $0.1) }
            self.bulletFollowers = set(bulletFollowers)
            self.modifiers = set(modifiers)
            self.modifierEndings = modifierEndings
            self.keepsCommaBeforeBreak = keepsCommaBeforeBreak
            self.laterMarkersFollowWords = laterMarkersFollowWords
        }

        func ordinal(_ word: String) -> Int? {
            if let value = ordinals[word] { return value }
            for suffix in digitOrdinalSuffixes where word.hasSuffix(suffix) {
                let digits = word.dropLast(suffix.count)
                if !digits.isEmpty, digits.count <= 2, digits.allSatisfy(\.isASCII), let value = Int(digits),
                   (1...20).contains(value) {
                    return value
                }
            }
            return nil
        }

        static func forLanguage(_ language: DictationLanguage, text: String) -> Table {
            switch language {
            case .german: german
            case .english: english
            case .automatic: TranscriptFormatter.readsAsEnglish(text) ? english : german
            }
        }

        static let german = Table(
            breaks: [(["neuer", "Absatz"], "\n\n"), (["neue", "Zeile"], "\n"), (["Zeilenumbruch"], "\n")],
            determiners: [
                "ein", "eine", "einen", "einem", "einer", "eines", "der", "die", "das", "den", "dem", "des", "dieser",
                "diese", "dieses", "diesen", "jede", "jeder", "jedes", "jeden", "kein", "keine", "keinen", "mein",
                "meine", "dein", "deine", "sein", "seine", "ihr", "ihre", "unser", "unsere", "euer", "eure", "im",
                "am", "zum", "zur", "vom", "beim", "ins", "mit", "für", "von", "zu", "in", "an", "auf", "aus", "nach",
                "ohne", "um", "pro", "als", "wie", "per",
            ],
            breakFollowers: [
                "ist", "war", "wird", "hat", "haben", "sind", "gibt", "kommt", "beginnt", "fängt", "der", "des", "die",
                "das", "im", "in", "mit", "für", "von", "vom", "zum", "zur", "auf", "an", "und", "oder", "einfügen",
                "hinzufügen", "beginnen", "anfangen", "schreiben", "machen", "eingefügt", "setzen", "drücken",
            ],
            connectors: ["und", "dann", "sowie"],
            alternatives: ["oder"],
            ordinals: [
                "erstens": 1, "zweitens": 2, "drittens": 3, "viertens": 4, "fünftens": 5, "sechstens": 6,
                "siebtens": 7, "siebentens": 7, "achtens": 8, "neuntens": 9, "zehntens": 10,
            ],
            digitOrdinalSuffixes: [],
            ordinalPhrases: [
                (["als", "Erstes"], 1), (["als", "Zweites"], 2), (["als", "Drittes"], 3), (["als", "Viertes"], 4),
                (["als", "Fünftes"], 5),
            ],
            ordinalFollowers: ["als", "wie"],
            ofAll: ["mal"],
            finals: [(["zu", "guter", "Letzt"], false), (["last", "but", "not", "least"], false), (["zuletzt"], true)],
            cardinals: [
                "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
                "zehn": 10,
            ],
            cardinalMarks: ",:)",
            keywords: ["Nummer", "Punkt", "Schritt"],
            bullets: [
                (["Aufzählungspunkt"], false), (["Spiegelstrich"], false), (["Bullet", "Point"], false),
                (["Bullet"], false),
            ],
            bulletFollowers: [
                "ist", "war", "wird", "hat", "sind", "der", "des", "im", "in", "mit", "für", "von", "und", "oder",
                "als", "points", "Liste", "Listen",
            ],
            modifiers: [
                "ganz", "völlig", "komplett", "total", "sehr", "wieder", "noch", "so", "zu", "nur", "auch", "extra",
                "wirklich", "echt", "gar", "fast", "eher", "ziemlich", "recht", "etwas", "mehr", "weitere", "andere",
            ],
            modifierEndings: ["e", "er", "en", "es", "em", "ig", "lich", "isch", "bar", "sam", "haft"],
            keepsCommaBeforeBreak: true,
            laterMarkersFollowWords: true
        )

        static let english = Table(
            breaks: [(["new", "paragraph"], "\n\n"), (["new", "line"], "\n"), (["line", "break"], "\n")],
            determiners: [
                "a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their",
                "one", "another", "every", "each", "any", "some", "no", "to", "of", "in", "on", "with", "for", "at",
                "by", "from", "silver", "magic", "rubber", "plastic", "stray", "whole", "entire",
            ],
            breakFollowers: [
                "of", "items", "item", "is", "was", "are", "were", "has", "had", "will", "would", "that", "which",
                "for", "from", "cook", "cooks", "worker", "workers", "manager", "managers", "up", "breaks",
            ],
            connectors: ["and", "then", "also", "plus"],
            alternatives: ["or"],
            ordinals: [
                "first": 1, "firstly": 1, "second": 2, "secondly": 2, "third": 3, "thirdly": 3, "fourth": 4,
                "fourthly": 4, "fifth": 5, "fifthly": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
                "tenth": 10,
            ],
            digitOrdinalSuffixes: ["st", "nd", "rd", "th"],
            ordinalPhrases: [],
            ordinalFollowers: [
                "time", "times", "place", "thing", "things", "one", "ones", "day", "days", "week", "weeks", "month",
                "months", "year", "years", "half", "class", "person", "people", "hand", "floor", "grade", "round",
                "prize", "guess", "guessed", "guessing", "nature", "rate", "aid", "base", "cousin", "cousins", "date",
                "name", "impression", "choice", "language", "lady", "world", "edition", "gear", "love", "sight",
                "glance", "mate", "chance", "try", "attempt", "look", "night", "kiss", "draft", "opinion", "wave",
                "quarter", "season", "episode", "chapter", "page", "row", "team", "degree", "letter", "word", "words",
                "course", "act", "part", "period", "hour", "minute", "thought", "thoughts", "off", "up", "to", "in",
                "on", "at", "and", "or", "is", "was", "came", "come", "served", "last", "of", "string", "fiddle",
                "semester", "term", "born", "child", "son", "daughter", "baby", "wife", "husband", "job", "line",
                "generation", "step", "steps", "officer", "lieutenant", "amendment", "street", "avenue", "best",
                "most", "largest", "biggest",
            ],
            ofAll: ["of", "all"],
            finals: [(["last", "but", "not", "least"], false), (["finally"], false), (["lastly"], false), (["last"], true)],
            cardinals: [
                "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
                "ten": 10,
            ],
            cardinalMarks: ",:.)",
            keywords: ["number", "step", "item", "point"],
            bullets: [
                (["bullet", "point"], false), (["next", "bullet"], false), (["next", "item"], false),
                (["bullet"], false), (["dash"], true),
            ],
            bulletFollowers: [
                "points", "proof", "proofs", "train", "trains", "wound", "wounds", "hole", "holes", "journal",
                "journals", "casing", "casings", "shell", "shells", "ant", "ants", "is", "was", "hit", "hits",
                "went", "flew", "of", "in", "list", "lists",
            ]
        )
    }
}
