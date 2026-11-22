import Foundation

/// Punctuation said by name written as the mark, with string rules and no model, in German and
/// English. With Experimental › Spoken punctuation on, runs inside every style but Verbatim, after
/// fillers (and Notes' spoken line breaks) and before the style's own capitalization and final
/// period (`TyprTranscriptFormatter.format(_:style:language:punctuation:)`). A mark the speech model
/// or AI cleanup already wrote beside a name is replaced, never doubled, and text without names
/// stays as it is.
/// Ported from Hex (anomalyco/hex `ios/HEXShared/SpokenPunctuation.swift` at d65b02d3, MIT),
/// German and English tables only; see THIRD_PARTY_NOTICES.md.
///
/// - Marks attach to the word before them ("Hallo, wie"), a dash is spaced ("gut – und dann"),
///   "Bindestrich", "Apostroph" and "At-Zeichen" join their words ("E-Mail", "John's",
///   "ana@gmail"), "Hashtag" and "dollar sign" go on the next word ("#blessed"), and a word after
///   ".", "?" or "!" starts with a capital.
/// - Quotes and brackets open and close: „ “ in German, “ ” in English, ( ). A closing name
///   counts only while one is open, and a bare "Anführungszeichen" or "quote" opens only with a
///   closing name later, never in "quote unquote".
/// - Guards keep prose and never turn a noun into a mark; a missed command stays as said. A
///   name is no command right after a determiner, a preposition, a number, a word like "Wort"
///   or "symbol", or a word that could be an adjective (German lowercase -e/-er/-en/-es/-em,
///   English -al/-ous/-ant/-ent/-ive/-ful/-ish/-ward/-ic/-ed/-ing/-y: "ein für mich sehr
///   wichtiger Punkt", "an important period"); after a determiner earlier in the same phrase
///   ("ein rosa Punkt", "a short, bizarre period"); when it repeats ("Punkt für Punkt") or
///   is listed with another name ("Punkt und Komma"); right before a word that continues the
///   noun ("Punkt ist", "colon cancer"); between two numbers ("zwei Komma fünf"); or inside a
///   compound ("comma-separated"). An opening bracket or quote needs its closing name later on
///   the line. The names that are everyday nouns ("Punkt", "Fragezeichen", "period", "question
///   mark", "dash") need command-like placement as well: the end of the line, a mark after
///   them, or a next word that starts a clause ("ich", "bis", "I", "see"). A colon needs words
///   after it.
nonisolated enum TyprSpokenPunctuation {
    /// `language` picks the word table; Automatic uses English only for text that reads as
    /// English (`TyprTranscriptFormatter.readsAsEnglish`), else German. `starters` are further words
    /// that start a clause after a name ("Milch Punkt zweitens"), lowercased and unaccented.
    static func format(_ text: String, language: DictationLanguage, starters: Set<String> = []) -> String {
        guard !text.isEmpty else { return text }
        var table = Table.forLanguage(language, text: text)
        table.starters.formUnion(starters)
        var writer = Writer(tokens: tokenize(text), table: table)
        return writer.write()
    }

    fileprivate struct Token {
        let text: String
        let isWord: Bool
        let folded: String
    }

    fileprivate static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "’", with: "'")
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsWord: Bool?
        func flush() {
            guard let isWord = currentIsWord else { return }
            tokens.append(Token(text: current, isWord: isWord, folded: isWord ? fold(current) : current))
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

    private static let pauseMarks = ",.;:!?…"
    private static let sentenceMarks = ".?!…"
    private static let openers: Set<Character> = ["(", "[", "“", "«", "„", "¿", "¡", "\"", "‘"]
    private static let closers: Set<Character> = [")", "]", "”", "»", "“", "\"", "’"]
    private static let contractions: Set<String> = ["s", "t", "d", "m", "ll", "re", "ve"]

    private struct Writer {
        let tokens: [Token]
        let table: Table
        var out = ""
        var capitalizeNext = false
        var lowercaseNext = false

        init(tokens: [Token], table: Table) {
            self.tokens = tokens
            self.table = table
        }

        mutating func write() -> String {
            var index = 0
            while index < tokens.count {
                if tokens[index].isWord, let (command, end) = command(at: index) {
                    if allows(command, from: index, to: end) {
                        index = apply(command, end: end)
                    } else {
                        for token in tokens[index..<end] {
                            emit(token)
                        }
                        index = end
                    }
                    continue
                }
                emit(tokens[index])
                index += 1
            }
            return out
        }

        private mutating func emit(_ token: Token) {
            guard token.isWord else {
                out += token.text
                return
            }
            if lowercaseNext, contractions.contains(token.folded) {
                out += token.text.lowercased()
            } else if capitalizeNext {
                out += capitalized(token.text)
            } else {
                out += token.text
            }
            capitalizeNext = false
            lowercaseNext = false
        }

        private func capitalized(_ word: String) -> String {
            guard let first = word.first, first.isLowercase,
                  !word.dropFirst().contains(where: \.isUppercase) else { return word }
            return first.uppercased() + word.dropFirst()
        }

        func command(at index: Int) -> (Command, Int)? {
            for command in table.commands {
                if let end = phraseEnd(command.words, at: index) { return (command, end) }
            }
            return nil
        }

        private func phraseEnd(_ words: [String], at index: Int) -> Int? {
            var position = index
            for (number, word) in words.enumerated() {
                if number > 0 {
                    guard position < tokens.count, !tokens[position].isWord else { return nil }
                    let separator = tokens[position].text
                    guard separator.count <= 3, separator.allSatisfy({ " -,".contains($0) }),
                          separator.filter({ $0 == "," }).count <= 1 else { return nil }
                    position += 1
                }
                guard position < tokens.count, tokens[position].isWord, tokens[position].folded == word else { return nil }
                position += 1
            }
            return position
        }

        private func count(_ character: Character) -> Int {
            out.reduce(0) { $1 == character ? $0 + 1 : $0 }
        }

        private func opens(_ character: Character, _ pair: Pair) -> Bool {
            switch pair {
            case .paren: character == "("
            case .quote: character == table.quotes.open || (character == "\"" && count("\"") % 2 == 0)
            }
        }

        private func closes(_ character: Character, _ pair: Pair) -> Bool {
            switch pair {
            case .paren: character == ")"
            case .quote: character == table.quotes.close || (character == "\"" && count("\"") % 2 == 1)
            }
        }

        private var lastWritten: Character? {
            out.last { $0 != " " && $0 != "\t" }
        }

        private func openedJustBefore(_ pair: Pair) -> Bool {
            guard let last = lastWritten else { return false }
            switch pair {
            case .paren: return last == "("
            case .quote: return last == table.quotes.open || (last == "\"" && count("\"") % 2 == 1)
            }
        }

        private func closedJustBefore(_ pair: Pair) -> Bool {
            guard !isOpen(pair), let last = lastWritten else { return false }
            return last == (pair == .paren ? ")" : table.quotes.close) || (pair == .quote && last == "\"")
        }

        private func firstWritten(in after: String) -> Character? {
            after.first { $0 != " " && $0 != "\t" }
        }

        private func opensNext(_ pair: Pair, after: String) -> Bool {
            firstWritten(in: after).map { opens($0, pair) } ?? false
        }

        private func closesNext(_ pair: Pair, after: String) -> Bool {
            firstWritten(in: after).map { closes($0, pair) } ?? false
        }

        private func alreadyOpened(_ pair: Pair, after: String) -> Bool {
            openedJustBefore(pair) || opensNext(pair, after: after)
        }

        private func alreadyClosed(_ pair: Pair, after: String) -> Bool {
            closedJustBefore(pair) || closesNext(pair, after: after)
        }

        private func quoteNameCloses(after: String) -> Bool {
            !alreadyOpened(.quote, after: after) && (alreadyClosed(.quote, after: after) || isOpen(.quote))
        }

        private func isOpen(_ pair: Pair) -> Bool {
            switch pair {
            case .paren:
                return count("(") > count(")")
            case .quote:
                return count(table.quotes.open) > count(table.quotes.close) || count("\"") % 2 == 1
            }
        }

        private func closingName(_ pair: Pair, after end: Int, toggles: Bool) -> Bool {
            var index = end
            var wordsBetween = false
            while index < tokens.count {
                if tokens[index].text.contains("\n") { return false }
                if tokens[index].isWord, let (found, commandEnd) = command(at: index) {
                    switch found.mark {
                    case .close(let closing) where closing == pair: return wordsBetween
                    case .toggleQuote where pair == .quote: return toggles && wordsBetween
                    default: index = commandEnd
                    }
                    wordsBetween = true
                    continue
                }
                wordsBetween = wordsBetween || tokens[index].isWord
                index += 1
            }
            return false
        }

        private func allows(_ command: Command, from index: Int, to end: Int) -> Bool {
            let before = index >= 1 ? tokens[index - 1].text : ""
            let after = end < tokens.count ? tokens[end].text : ""
            let previous: Token? = index >= 2 && !before.contains("\n") ? tokens[index - 2] : nil
            let next: Token? = end + 1 < tokens.count && !after.contains("\n") ? tokens[end + 1] : nil
            let nextDirect = next != nil && after.allSatisfy { $0 == " " || $0 == "\t" }
            let mark = command.mark
            let family = command.family

            if let first = after.first, first == "-" || first == "/" { return false }
            if family != .hyphen, let last = before.last, last == "-" || last == "/" { return false }

            switch mark {
            case .open(_, let pair):
                if alreadyOpened(pair, after: after) { return true }
            case .close(let pair):
                if alreadyClosed(pair, after: after) { return true }
            case .toggleQuote:
                if alreadyOpened(.quote, after: after) || alreadyClosed(.quote, after: after) { return true }
            default:
                break
            }

            if table.capitalizesSentences, tokens[index].text.first?.isUppercase == true, let previous {
                if family == .dash, !before.contains(where: { ".!?".contains($0) }) { return false }
                if family == .smiley, previous.text.first?.isUppercase == true { return false }
            }

            var opens = false
            var closes = false
            switch mark {
            case .open(_, let pair):
                opens = true
                guard closingName(pair, after: end, toggles: true) else { return false }
            case .prefix:
                opens = true
            case .toggleQuote(let toggles):
                opens = !quoteNameCloses(after: after)
                closes = !opens
                if opens {
                    guard next != nil, closingName(.quote, after: end, toggles: toggles) else { return false }
                }
            case .close(let pair):
                guard isOpen(pair) else { return false }
                closes = true
            default:
                break
            }

            if !opens {
                guard let previous else { return false }
                if !closes, isNounPhrase(before: previous, at: index, family: family, mark: mark) { return false }
            } else if case .prefix = mark, let previous, isNounPhrase(before: previous, at: index, family: family, mark: mark) {
                return false
            }

            if case .open = mark {
                if let previous, table.blockers.contains(previous.folded) { return false }
                if listsNames(around: index) { return false }
                if nextDirect, let next, table.followers.contains(next.folded) { return false }
                return next != nil
            }
            if case .toggleQuote = mark, opens {
                return true
            }

            if [.comma, .period, .colon].contains(family), let previous, nextDirect, let next,
               isNumber(previous), isNumber(next) {
                return false
            }

            if nextDirect, let next {
                if table.followers.contains(next.folded) || table.familyFollowers[family]?.contains(next.folded) == true {
                    return false
                }
            }

            switch mark {
            case .join:
                let joinable = family == .hyphen ? " \t-" : " \t"
                guard before.allSatisfy({ joinable.contains($0) }), nextDirect else { return false }
            case .prefix:
                guard nextDirect else { return false }
            default:
                break
            }

            if command.needsFollowing, next == nil { return false }
            if command.strict {
                let atLineEnd = next == nil
                let pauseAfter = after.first(where: { $0 != " " && $0 != "\t" }).map {
                    pauseMarks.contains($0) || closers.contains($0)
                } ?? false
                let startsClause = nextDirect && next.map {
                    table.starters.contains($0.folded)
                        || (table.capitalizesSentences && $0.text.first?.isUppercase == true)
                } ?? false
                let anotherCommand = next != nil && self.command(at: end + 1) != nil
                guard atLineEnd || pauseAfter || startsClause || anotherCommand else { return false }
            }
            return true
        }

        private func isNumber(_ token: Token) -> Bool {
            token.folded.allSatisfy(\.isNumber) || table.numbers.contains(token.folded)
        }

        private func isNounPhrase(before previous: Token, at index: Int, family: Family, mark: Mark) -> Bool {
            let word = previous.folded
            if table.blockers.contains(word) || table.familyBlockers[family]?.contains(word) == true { return true }
            if table.prepositions.contains(word), ![.question, .exclamation, .period].contains(family) {
                return true
            }
            if table.possessives, word.hasSuffix("'s"), !table.starters.contains(word) { return true }
            if index >= 4, tokens[index - 4].folded == tokens[index].folded { return true }
            if listsNames(around: index) { return true }
            guard lastWritten?.isLetter == true else { return false }
            if previous.text.first?.isLowercase == true, word.count > 3,
               table.adjectiveEndings.contains(where: word.hasSuffix) {
                return true
            }
            if case .join = mark { return false }
            return determinerOpensPhrase(endingAt: index - 2)
        }

        private func listsNames(around index: Int) -> Bool {
            if index >= 2, table.conjunctions.contains(tokens[index - 2].folded) {
                for start in stride(from: index - 4, through: max(index - 8, 0), by: -2)
                where tokens[start].isWord && command(at: start)?.1 == index - 3 {
                    return true
                }
            }
            guard let (_, end) = command(at: index), end + 3 < tokens.count,
                  table.conjunctions.contains(tokens[end + 1].folded) else { return false }
            return command(at: end + 3) != nil
        }

        private func determinerOpensPhrase(endingAt start: Int) -> Bool {
            var position = start
            while position >= 0 {
                if position < start, table.phraseBreakers.contains(tokens[position].folded) { return false }
                if table.phraseDeterminers.contains(tokens[position].folded) { return true }
                if !table.capitalizesSentences, tokens[position].text.first?.isLowercase != true || start - position >= 4 {
                    return false
                }
                guard position >= 2 else { return false }
                let separator = tokens[position - 1].text
                guard separator.allSatisfy({ " \t,".contains($0) }), separator.filter({ $0 == "," }).count <= 1,
                      command(at: position - 2) == nil else { return false }
                position -= 2
            }
            return false
        }

        private mutating func apply(_ command: Command, end: Int) -> Int {
            let after = end < tokens.count ? tokens[end].text : ""
            let resume = end < tokens.count ? end + 1 : end
            let wordAfter = end + 1 < tokens.count
            func rest(dropping set: String) -> String {
                String(after.drop { set.contains($0) })
            }
            func spaced(_ rest: String) -> String {
                rest.isEmpty && wordAfter ? " " : rest
            }

            switch command.mark {
            case .attach(let mark):
                trimEnd(" \t" + pauseMarks)
                if !(sentenceMarks.contains(mark) && endsSentenceInsideCloser) {
                    out += mark
                }
                out += spaced(rest(dropping: " \t" + pauseMarks))
                capitalizeNext = sentenceMarks.contains(mark)
            case .open(let mark, let pair):
                openWith(mark, pair: pair, after: after)
            case .close(let pair):
                out += spaced(closeWith(pair, after: after))
            case .toggleQuote:
                if quoteNameCloses(after: after) {
                    out += spaced(closeWith(.quote, after: after))
                } else {
                    openWith(String(table.quotes.open), pair: .quote, after: after)
                }
            case .join(let mark):
                trimEnd(command.family == .hyphen ? " \t-" : " \t")
                out += mark
                out += rest(dropping: " \t")
                lowercaseNext = command.family == .apostrophe
            case .prefix(let mark):
                openSpaced(mark)
                out += rest(dropping: " \t")
            case .spaced(let mark):
                trimEnd(" \t,;:")
                out += " " + mark
                out += spaced(rest(dropping: " \t,;:"))
            case .emoticon(let face):
                trimEnd(" \t,")
                out += " " + face
                out += spaced(rest(dropping: " \t,."))
            }
            return resume
        }

        private mutating func trimEnd(_ set: String) {
            while let last = out.last, set.contains(last) {
                out.removeLast()
            }
        }

        private mutating func openSpaced(_ mark: String) {
            trimEnd(" \t")
            if let last = out.last, !last.isNewline, !openers.contains(last) {
                out += " "
            }
            out += mark
        }

        private mutating func openWith(_ mark: String, pair: Pair, after: String) {
            let rest = after.drop { " \t".contains($0) || pauseMarks.contains($0) }
            let writtenAfter = rest.first.map { opens($0, pair) } ?? false
            if openedJustBefore(pair) {
                trimEnd(" \t")
            } else {
                openSpaced(writtenAfter ? "" : mark)
            }
            out += rest
        }

        private var endsSentenceInsideCloser: Bool {
            guard let last = out.last, closers.contains(last), let inner = out.dropLast().last else { return false }
            return sentenceMarks.contains(inner)
        }

        private mutating func closeWith(_ pair: Pair, after: String) -> String {
            let straight = pair == .quote && count("\"") % 2 == 1
            let writtenBefore = closedJustBefore(pair)
            let writtenAfter = closesNext(pair, after: after)
            trimEnd(" \t,;:")
            var rest = Substring(after)
            if writtenAfter {
                rest = rest.drop { $0 == " " || $0 == "\t" }
                let mark = rest.removeFirst()
                if !writtenBefore { out.append(mark) }
            } else if !writtenBefore {
                switch pair {
                case .paren: out += ")"
                case .quote: out.append(straight ? "\"" : table.quotes.close)
                }
            }
            if endsSentenceInsideCloser {
                rest = rest.drop { sentenceMarks.contains($0) }
            }
            return String(rest)
        }
    }

    fileprivate enum Pair: Equatable {
        case paren
        case quote
    }

    fileprivate enum Mark {
        case attach(String)
        case open(String, Pair)
        case close(Pair)
        case toggleQuote(toggles: Bool)
        case join(String)
        case prefix(String)
        case spaced(String)
        case emoticon(String)
    }

    fileprivate enum Family: Hashable {
        case comma, period, question, exclamation, colon, semicolon, ellipsis, dash, hyphen
        case apostrophe, at, hashtag, dollar, quote, paren, smiley
    }

    fileprivate struct Command {
        let words: [String]
        let mark: Mark
        let family: Family
        let strict: Bool
        let needsFollowing: Bool
    }

    private struct Table {
        let commands: [Command]
        let blockers: Set<String>
        let prepositions: Set<String>
        let numbers: Set<String>
        let familyBlockers: [Family: Set<String>]
        let followers: Set<String>
        let familyFollowers: [Family: Set<String>]
        var starters: Set<String>
        let quotes: (open: Character, close: Character)
        let capitalizesSentences: Bool
        let adjectiveEndings: [String]
        let phraseDeterminers: Set<String>
        let conjunctions: Set<String>
        let phraseBreakers: Set<String>
        let possessives: Bool

        init(
            commands: [(String, Mark, Family, Placement)],
            blockers: [String],
            numbers: [String],
            prepositions: [String],
            familyBlockers: [Family: [String]] = [:],
            followers: [String],
            familyFollowers: [Family: [String]] = [:],
            starters: [String],
            quotes: (open: Character, close: Character),
            capitalizesSentences: Bool = true,
            possessives: Bool = false,
            adjectiveEndings: [String],
            phraseDeterminers: [String] = [],
            conjunctions: [String],
            phraseBreakers: [String] = []
        ) {
            let fold = TyprSpokenPunctuation.fold
            self.commands = commands
                .map { phrase, mark, family, placement in
                    Command(
                        words: fold(phrase).split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init),
                        mark: mark,
                        family: family,
                        strict: placement == .strict,
                        needsFollowing: placement == .following
                    )
                }
                .sorted { $0.words.count > $1.words.count }
            self.blockers = Set(blockers.map(fold))
            self.prepositions = Set(prepositions.map(fold))
            self.numbers = Set(numbers.map(fold))
            self.familyBlockers = familyBlockers.mapValues { Set($0.map(fold)) }
            self.followers = Set(followers.map(fold))
            self.familyFollowers = familyFollowers.mapValues { Set($0.map(fold)) }
            self.starters = Set(starters.map(fold))
            self.quotes = quotes
            self.capitalizesSentences = capitalizesSentences
            self.adjectiveEndings = adjectiveEndings.map(fold)
            self.phraseDeterminers = Set(phraseDeterminers.map(fold))
            self.conjunctions = Set(conjunctions.map(fold))
            self.phraseBreakers = Set(phraseBreakers.map(fold))
            self.possessives = possessives
        }

        static func forLanguage(_ language: DictationLanguage, text: String) -> Table {
            switch language {
            case .german: german
            case .english: english
            case .automatic: TyprTranscriptFormatter.readsAsEnglish(text) ? english : german
            }
        }
    }

    private enum Placement {
        case lenient, strict, following
    }

    private static let english = Table(
        commands: [
            ("question mark", .attach("?"), .question, .strict),
            ("exclamation point", .attach("!"), .exclamation, .strict),
            ("exclamation mark", .attach("!"), .exclamation, .strict),
            ("full stop", .attach("."), .period, .lenient),
            ("period", .attach("."), .period, .strict),
            ("comma", .attach(","), .comma, .lenient),
            ("semicolon", .attach(";"), .semicolon, .lenient),
            ("semi colon", .attach(";"), .semicolon, .lenient),
            ("colon", .attach(":"), .colon, .following),
            ("ellipsis", .attach("…"), .ellipsis, .lenient),
            ("dot dot dot", .attach("…"), .ellipsis, .lenient),
            ("em dash", .join("—"), .dash, .strict),
            ("dash", .spaced("–"), .dash, .lenient),
            ("hyphen", .join("-"), .hyphen, .lenient),
            ("apostrophe", .join("'"), .apostrophe, .lenient),
            ("at sign", .join("@"), .at, .lenient),
            ("hashtag", .prefix("#"), .hashtag, .lenient),
            ("dollar sign", .prefix("$"), .dollar, .lenient),
            ("open quote", .open("“", .quote), .quote, .lenient),
            ("open quotes", .open("“", .quote), .quote, .lenient),
            ("begin quote", .open("“", .quote), .quote, .lenient),
            ("close quote", .close(.quote), .quote, .lenient),
            ("close quotes", .close(.quote), .quote, .lenient),
            ("end quote", .close(.quote), .quote, .lenient),
            ("end quotes", .close(.quote), .quote, .lenient),
            ("unquote", .close(.quote), .quote, .lenient),
            ("quote", .toggleQuote(toggles: false), .quote, .lenient),
            ("open paren", .open("(", .paren), .paren, .lenient),
            ("open parenthesis", .open("(", .paren), .paren, .lenient),
            ("open parentheses", .open("(", .paren), .paren, .lenient),
            ("close paren", .close(.paren), .paren, .lenient),
            ("close parenthesis", .close(.paren), .paren, .lenient),
            ("close parentheses", .close(.paren), .paren, .lenient),
            ("smiley face", .emoticon(":-)"), .smiley, .strict),
            ("smiley", .emoticon(":-)"), .smiley, .strict),
            ("frowny face", .emoticon(":-("), .smiley, .strict),
            ("frowny", .emoticon(":-("), .smiley, .strict),
            ("winky face", .emoticon(";-)"), .smiley, .strict),
            ("winky", .emoticon(";-)"), .smiley, .strict),
        ],
        blockers: [
            "a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their",
            "no", "every", "each", "any", "some", "another", "what", "which", "whose", "one", "of", "big", "huge", "giant", "little", "small",
            "large", "tiny", "red", "black", "blue", "green", "white", "yellow", "gold", "golden", "silver", "bold",
            "bright", "extra", "missing", "stray", "misplaced", "single", "double", "triple", "final", "last",
            "first", "second", "third", "next", "same", "whole", "entire", "upside", "inverted", "mad", "quick",
            "em", "en", "more", "fewer", "less", "word", "symbol", "sign", "key", "called", "named",
        ],
        numbers: ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"],
        prepositions: ["in", "on", "at", "to", "for", "with", "by", "from", "about", "into", "than", "like", "without", "per"],
        familyBlockers: [
            .comma: ["oxford", "serial", "decimal"],
            .period: [
                "trial", "grace", "time", "free", "waiting", "cooling", "notice", "billing", "school", "class",
                "study", "rest", "transition", "transitional", "warranty", "introductory", "honeymoon", "probation",
                "probationary", "historical", "victorian", "jurassic", "cretaceous", "triassic", "renaissance",
                "colonial", "medieval", "early", "late", "given", "certain", "limited", "specific", "extended",
                "brief", "reporting", "accounting", "fiscal", "lunch", "recovery", "adjustment", "settling",
                "initial", "current", "previous", "short", "long", "missed", "heavy", "light", "fourth", "fifth",
                "sixth", "seventh", "eighth", "dry", "rainy", "wet", "holiday", "summer", "winter", "spring",
                "fall", "lockdown", "quiet", "busy", "difficult", "hard", "tough", "rough", "happy", "sad",
            ],
            .colon: ["sigmoid", "transverse", "descending", "ascending", "inflamed", "spastic", "irritable", "healthy"],
            .dash: [
                "desperate", "frantic", "yard", "metre", "meter", "hundred", "fifty", "mile", "i", "you", "we",
                "they", "he", "she", "i'll", "we'll", "you'll", "they'll", "i'd", "will", "must", "gotta", "gonna",
                "can", "could", "should", "would", "might", "let's", "and",
            ],
            .hashtag: [
                "i", "you", "we", "they", "he", "she", "will", "can", "can't", "don't", "do", "didn't", "would",
                "should", "could", "must", "never", "always", "just", "popular", "trending", "viral", "new", "own",
                "official", "branded",
            ],
        ],
        followers: ["of", "is", "was", "are", "were", "isn't", "wasn't", "aren't", "weren't", "has", "hasn't", "had"],
        familyFollowers: [
            .comma: ["after", "before", "between", "in", "inside", "instead", "splice", "splices", "separated", "delimited", "key", "button", "placement", "rule", "rules", "usage", "sign", "symbol"],
            .period: [
                "after", "before", "in", "during", "when", "where", "for", "piece", "pieces", "drama", "dramas", "costume",
                "costumes", "cramps", "cramp", "pain", "pains", "tracker", "app", "poverty", "products", "product",
                "underwear", "blood", "end", "ends", "ended", "starts", "started", "begins", "began", "lasts", "lasted",
                "correct", "accurate", "film", "films", "features", "furniture", "room", "rooms", "key", "button",
                "sign", "symbol", "to",
            ],
            .question: ["tattoo", "tattoos", "key", "keys", "button", "sign", "symbol", "symbols", "icon", "emoji", "shape", "shaped", "necklace", "over", "hanging", "hangs", "hung", "on", "in", "after", "at"],
            .exclamation: ["tattoo", "tattoos", "key", "keys", "button", "sign", "symbol", "symbols", "icon", "emoji", "shape", "on", "in", "after", "at"],
            .colon: [
                "cancer", "cancers", "surgery", "health", "cleanse", "cleansing", "polyps", "polyp", "screening",
                "screenings", "exam", "problems", "problem", "issues", "wall", "lining", "tumor", "tumour", "disease",
                "inflammation", "function", "symbol", "sign", "key", "character", "in", "after", "between", "and", "or",
            ],
            .semicolon: ["in", "after", "between", "key", "sign", "symbol", "usage"],
            .ellipsis: ["in", "after", "key", "sign", "symbol", "usage"],
            .dash: [
                "for", "to", "cam", "cams", "board", "button", "light", "lights", "through", "across", "into", "out",
                "off", "away", "over", "around", "home", "back", "past", "down", "up", "in", "on", "mat",
            ],
            .hyphen: ["in", "after", "between", "key", "sign", "symbol", "usage"],
            .apostrophe: ["in", "after", "key", "sign", "symbol", "usage"],
            .at: ["key", "symbol"],
            .hashtag: ["on", "in", "for", "and", "or", "to"],
            .dollar: ["on", "in", "for", "and", "or", "key", "symbol"],
            .smiley: ["emoji", "emojis", "icon", "sticker", "stickers", "faces", "ball", "balls"],
        ],
        starters: [
            "i", "i'm", "i'll", "i've", "i'd", "you", "you're", "you'll", "we", "we're", "we'll", "he", "he's",
            "she", "she's", "they", "they're", "it", "it's", "that's", "there", "there's", "here", "here's", "this",
            "so", "and", "but", "or", "then", "because", "also", "plus", "thanks", "thank", "please", "see", "let",
            "let's", "talk", "call", "hope", "love", "cheers", "ok", "okay", "yes", "yeah", "no", "hi", "hey",
            "hello", "sorry", "maybe", "anyway", "what", "what's", "why", "how", "when", "where", "who", "if",
            "sure", "best", "regards", "just", "can", "could", "would", "will", "do", "did", "don't", "didn't",
            "not", "great", "cool", "talk", "speak", "bye", "goodbye", "kind", "warm",
        ],
        quotes: ("“", "”"),
        possessives: true,
        adjectiveEndings: ["al", "ous", "ant", "ent", "ive", "ful", "ish", "ward", "ic", "ed", "ing", "y"],
        phraseDeterminers: ["a", "an", "the", "this", "that", "my", "your", "his", "her", "our", "their", "any", "no", "every"],
        conjunctions: ["and", "or", "nor"]
    )

    private static let german = Table(
        commands: [
            ("komma", .attach(","), .comma, .lenient),
            ("punkt", .attach("."), .period, .strict),
            ("fragezeichen", .attach("?"), .question, .strict),
            ("ausrufezeichen", .attach("!"), .exclamation, .strict),
            ("ausrufungszeichen", .attach("!"), .exclamation, .strict),
            ("doppelpunkt", .attach(":"), .colon, .following),
            ("semikolon", .attach(";"), .semicolon, .lenient),
            ("strichpunkt", .attach(";"), .semicolon, .lenient),
            ("auslassungspunkte", .attach("…"), .ellipsis, .lenient),
            ("anführungszeichen unten", .open("„", .quote), .quote, .lenient),
            ("anführungszeichen auf", .open("„", .quote), .quote, .lenient),
            ("anführungszeichen oben", .close(.quote), .quote, .lenient),
            ("anführungszeichen zu", .close(.quote), .quote, .lenient),
            ("abführungszeichen", .close(.quote), .quote, .lenient),
            ("anführungszeichen", .toggleQuote(toggles: true), .quote, .lenient),
            ("klammer auf", .open("(", .paren), .paren, .lenient),
            ("öffnende klammer", .open("(", .paren), .paren, .lenient),
            ("klammer zu", .close(.paren), .paren, .lenient),
            ("schließende klammer", .close(.paren), .paren, .lenient),
            ("gedankenstrich", .spaced("–"), .dash, .strict),
            ("bindestrich", .join("-"), .hyphen, .lenient),
            ("at zeichen", .join("@"), .at, .lenient),
            ("klammeraffe", .join("@"), .at, .lenient),
            ("apostroph", .join("'"), .apostrophe, .lenient),
            ("hashtag", .prefix("#"), .hashtag, .lenient),
        ],
        blockers: [
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "kein",
            "keine", "keinen", "keinem", "keiner", "mein", "meine", "meinen", "meinem", "meiner", "dein", "deine",
            "deinen", "sein", "seine", "seinen", "seinem", "ihr", "ihre", "ihren", "ihrem", "unser", "unsere",
            "unseren", "euer", "eure", "dieser", "diese", "dieses", "diesen", "diesem", "jeder", "jede", "jedes",
            "jeden", "welcher", "welche", "welches", "zum", "zur", "im", "am", "um", "beim", "vom", "ins", "ans",
            "springende", "zeichen", "symbol", "taste", "wort", "begriff",
        ],
        numbers: ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn"],
        prepositions: ["mit", "ohne", "für", "auf", "an", "in", "nach", "vor", "bei", "von", "zu", "aus", "über", "unter", "gegen", "durch", "als"],
        followers: ["ist", "war", "sind", "waren", "hat", "hatte", "für", "der", "des", "von", "auf"],
        familyFollowers: [
            .period: [
                "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf",
                "uhr",
            ],
        ],
        starters: [
            "ich", "du", "er", "sie", "es", "wir", "ihr", "und", "aber", "oder", "dann", "also", "denn", "weil",
            "danke", "bitte", "hallo", "hi", "hey", "ja", "nein", "bis", "viele", "liebe", "lieber", "gruß",
            "grüße", "wie", "was", "wann", "wo", "warum", "wer", "wenn", "dass", "ok", "okay", "mal", "sorry",
            "tschüss", "schöne", "schönen", "mach", "machs",
        ],
        quotes: ("„", "“"),
        capitalizesSentences: false,
        adjectiveEndings: ["e", "er", "en", "es", "em", "ste", "sten"],
        phraseDeterminers: [
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "kein",
            "keine", "keinen", "keinem", "keiner", "mein", "meine", "meinen", "meinem", "meiner", "dein", "deine",
            "deinen", "sein", "seine", "seinen", "seinem", "ihr", "ihre", "ihren", "ihrem", "unser", "unsere",
            "unseren", "euer", "eure", "dieser", "diese", "dieses", "diesen", "diesem", "jeder", "jede", "jedes",
            "jeden", "welcher", "welche", "welches", "zum", "zur", "im", "am", "beim", "vom",
        ],
        conjunctions: ["und", "oder", "sowie", "bzw"],
        phraseBreakers: [
            "ist", "sind", "war", "waren", "bin", "bist", "seid", "hat", "habe", "hast", "haben", "hatte", "wird",
            "werden", "wurde", "kann", "muss", "soll", "will", "darf", "gibt", "geht", "ich", "du", "er", "es",
            "wir", "man",
        ]
    )
}
