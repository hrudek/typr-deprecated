import Foundation

struct Score: Codable {
    var words = 0
    var wordErrors = 0
    var letters = 0
    var letterErrors = 0

    mutating func add(committed: String, meant: String) {
        words += 1
        letters += meant.count
        let distance = editDistance(Array(committed), Array(meant))
        letterErrors += distance
        if distance > 0 { wordErrors += 1 }
    }
}

struct Split: Codable {
    var known = Score()
    var unknown = Score()

    subscript(known isKnown: Bool) -> Score {
        get { isKnown ? known : unknown }
        set { if isKnown { known = newValue } else { unknown = newValue } }
    }
}

struct Reproduction: Codable {
    var literals = 0
    var literalMatches = 0
    var commits = 0
    var commitMatches = 0
    /// Committed by a strip pick; replayed with the same pick.
    var picked = 0
    /// Corrected by system spelling, which the replay does not have.
    var systemSpelling = 0
}

struct WordLine: Codable {
    var meant: String
    var known: Bool
    var logged: String
    var replayed: String
    var replayedLetters: String?
}

struct Report: Codable {
    var engine: String
    var exported = 0
    var replayed = 0
    var skipped: [String: Int] = [:]
    var reproduction = Reproduction()
    var score = Split()
    var words: [WordLine]?

    /// `results[i]`: the preparation and replay of `logged[i]`, or why it was skipped.
    static func build(engine: ReplayEngine, words logged: [TypingLogWord],
                      results: [Result<(PreparedWord, ReplayedWord), SkipReason>], showWords: Bool) -> Report {
        var report = Report(engine: engine.rawValue, exported: logged.count)
        var lines: [WordLine] = []
        for (word, result) in zip(logged, results) {
            let prepared: PreparedWord, replay: ReplayedWord
            switch result {
            case .success(let replayed): (prepared, replay) = replayed
            case .failure(let reason): report.skipped[reason.rawValue, default: 0] += 1; continue
            }
            report.replayed += 1
            var reproduced = true
            report.reproduction.literals += 1
            if replay.literal == prepared.plan.literal { report.reproduction.literalMatches += 1 } else { reproduced = false }
            if let commit = word.commit {
                if commit.correction == .spelling {
                    report.reproduction.systemSpelling += 1
                } else if commit.kind == .pick {
                    report.reproduction.picked += 1
                } else {
                    report.reproduction.commits += 1
                    if replay.committed == commit.text { report.reproduction.commitMatches += 1 } else { reproduced = false }
                }
            }
            report.score[known: prepared.known].add(committed: replay.committed, meant: word.meant)
            if showWords, !reproduced || replay.committed != word.meant {
                lines.append(WordLine(meant: word.meant, known: prepared.known, logged: word.commit?.text ?? word.literal,
                                      replayed: replay.committed,
                                      replayedLetters: replay.literal == prepared.plan.literal ? nil : replay.literal))
            }
        }
        if showWords { report.words = lines }
        return report
    }

    func text() -> String {
        var out = "Typing log replay\(engine == ReplayEngine.hex.rawValue ? " through Hex's engine" : ""):"
        out += " \(exported) words exported, \(replayed) replayed\n"
        let r = reproduction
        out += "Reproduction: committed word matches the iPhone for"
        out += " \(r.commitMatches)/\(r.commits) words, \(Self.percent(r.commitMatches, r.commits))\n"
        out += "  not compared: \(r.systemSpelling) fixed by system spelling, \(r.picked) picked from the strip\n"
        out += "  letters at the first boundary match for \(r.literalMatches)/\(r.literals) words\n"
        if !skipped.isEmpty {
            out += "Skipped: " + skipped.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                .joined(separator: ", ") + "\n"
        }
        out += "\nVs meant word:\n" + Self.line("known", score.known) + Self.line("unknown", score.unknown)
        if let words {
            out += "\nNot reproduced or not the meant word (\(words.count)):\n"
            for line in words {
                out += "  meant \(line.meant) | logged \(line.logged) | replayed \(line.replayed)"
                if let letters = line.replayedLetters { out += " | replayed letters \(letters)" }
                out += line.known ? "\n" : " (unknown)\n"
            }
        }
        return out
    }

    static func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "-" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
    }

    static func line(_ name: String, _ score: Score) -> String {
        return "  \(name) \(score.words) words: word errors \(percent(score.wordErrors, score.words))"
            + " (\(score.wordErrors)), letter errors \(percent(score.letterErrors, score.letters))"
            + " (\(score.letterErrors)/\(score.letters))\n"
    }
}

struct ParityLine: Codable {
    var meant: String
    var literal: String
    var typr: String
    var hex: String
}

typealias ParityResult = Result<(PreparedWord, typr: Result<ReplayedWord, SkipReason>,
                                 hex: Result<ReplayedWord, SkipReason>), SkipReason>

struct ParityReport: Codable {
    var exported = 0
    var compared = 0
    var sameCommit = 0
    var skipped: [String: Int] = [:]
    var typr = Split()
    var hex = Split()
    var differences: [ParityLine]?

    static func build(words logged: [TypingLogWord], results: [ParityResult], showWords: Bool) -> ParityReport {
        var report = ParityReport(exported: logged.count)
        var lines: [ParityLine] = []
        for (word, result) in zip(logged, results) {
            let prepared: PreparedWord, typr: ReplayedWord, hex: ReplayedWord
            switch result {
            case .failure(let reason):
                report.skipped[reason.rawValue, default: 0] += 1
                continue
            case .success(let (ready, typrResult, hexResult)):
                switch (typrResult, hexResult) {
                case (.success(let t), .success(let h)): (prepared, typr, hex) = (ready, t, h)
                case (.failure(let reason), _): report.skipped["Typr: " + reason.rawValue, default: 0] += 1; continue
                case (_, .failure(let reason)): report.skipped["Hex: " + reason.rawValue, default: 0] += 1; continue
                }
            }
            report.compared += 1
            report.typr[known: prepared.known].add(committed: typr.committed, meant: word.meant)
            report.hex[known: prepared.known].add(committed: hex.committed, meant: word.meant)
            if typr.committed == hex.committed {
                report.sameCommit += 1
            } else if showWords {
                lines.append(ParityLine(meant: word.meant, literal: prepared.plan.literal, typr: typr.committed,
                                        hex: hex.committed))
            }
        }
        if showWords { report.differences = lines }
        return report
    }

    func text() -> String {
        var out = "Engine parity: \(exported) words exported, \(compared) replayed through both engines\n"
        out += "Hex runs on the bundled word lists, not system spelling: words whose commit asks for guesses,"
        out += " completions or capitalised spellings are skipped\n"
        out += "Same commit: \(sameCommit)/\(compared) words, \(Report.percent(sameCommit, compared))\n"
        if !skipped.isEmpty {
            out += "Skipped: " + skipped.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                .joined(separator: ", ") + "\n"
        }
        out += "\nVs meant word, Typr's engine:\n" + Report.line("known", typr.known) + Report.line("unknown", typr.unknown)
        out += "Vs meant word, Hex's engine:\n" + Report.line("known", hex.known) + Report.line("unknown", hex.unknown)
        if let differences {
            out += "\nCommits differ (\(differences.count)):\n"
            for line in differences {
                out += "  meant \(line.meant) | typed \(line.literal) | Typr \(line.typr) | Hex \(line.hex)\n"
            }
        }
        return out
    }
}

func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
    var previous = Array(0...b.count)
    for (i, x) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, y) in b.enumerated() {
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
        }
        previous = current
    }
    return previous[b.count]
}
