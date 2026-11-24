import Foundation

let usage = """
Usage: keyboard-replay EXPORT.json [--engine typr|hex | --parity] [--show-words] [--json]
Replays a Typr typing log export through the keyboard's own engine.
  --engine      typr (default): Typr's typing engine; hex: Hex's keyboard and autocorrect
  --parity      replay every word through both engines and report where their commits differ
  --show-words  list the words that did not reproduce, differ from the meant word, or differ
                between the engines (private text)
  --json        print the report as JSON
       keyboard-replay --make-fixture FILE
Types the invented test text through the engine and writes it as an export to FILE.
       keyboard-replay --touch-posterior
Prints the learned touch densities after fixed labels as JSON, for the touch-model tests.
       keyboard-replay --tap-mapping
Logs taps on Hex's keys as Hex's keyboard does and replays them, as JSON, for the mapping tests.
"""

func readExport(_ path: String) throws -> TypingLogExport {
    let url = URL(fileURLWithPath: path)
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    guard size <= 256 * 1024 * 1024 else { throw ReplayError("\(path) is larger than 256 MB") }
    struct Header: Decodable { let format: String?; let version: Int? }
    let data = try Data(contentsOf: url)
    let header: Header
    do { header = try JSONDecoder().decode(Header.self, from: data) } catch {
        throw ReplayError("\(path) is not valid JSON")
    }
    guard header.format == TypingLogExport.format else { throw ReplayError("\(path) is not a Typr typing log export") }
    guard header.version == TypingLogExport.version else {
        throw ReplayError("Export version \(header.version.map(String.init) ?? "?") is not supported"
                          + " (expected \(TypingLogExport.version)); export again from the matching Typr build")
    }
    do { return try TypingLogExport.decoder().decode(TypingLogExport.self, from: data) } catch {
        throw ReplayError("\(path) does not match the typing log format: \(error)")
    }
}

enum ReplayEngine: String { case typr, hex }

@MainActor
func run(_ arguments: [String]) async throws {
    var input: String?
    var showWords = false, json = false, parity = false
    var engine = ReplayEngine.typr
    var fixture: URL?
    var tapMapping = false
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "--show-words": showWords = true
        case "--json": json = true
        case "--parity": parity = true
        case "--engine":
            guard let name = rest.popFirst(), let chosen = ReplayEngine(rawValue: name) else { throw ReplayError(usage) }
            engine = chosen
        case "--make-fixture":
            guard let path = rest.popFirst() else { throw ReplayError(usage) }
            fixture = URL(fileURLWithPath: path)
        case "-h", "--help": print(usage); return
        case "--touch-posterior": print(try touchPosteriorReport(), terminator: ""); return
        case "--tap-mapping": tapMapping = true
        default:
            guard input == nil, !argument.hasPrefix("-") else { throw ReplayError(usage) }
            input = argument
        }
    }
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
        throw ReplayError("Cannot locate the WordData folder next to keyboard-replay")
    }
    let words = try WordData(directory: executable.deletingLastPathComponent().appendingPathComponent("WordData"))
    if let fixture {
        return try await makeFixture(words: words, to: fixture)
    }
    if tapMapping {
        try Replayer.requireHexResources()
        let empty = TypingLogExport(exportedAt: Date(), appBuild: "tap-mapping", learning: nil, words: [])
        return print(try Replayer(words: words, export: empty).tapMappingReport(), terminator: "")
    }
    guard let input else { throw ReplayError(usage) }
    let export = try readExport(input)

    let replayer = try Replayer(words: words, export: export)
    if parity || engine == .hex { try Replayer.requireHexResources() }

    var results: [Result<(PreparedWord, ReplayedWord), SkipReason>] = []
    var pairs: [ParityResult] = []
    var previous: [String] = []
    for word in export.words {
        let context = previous.joined()
        switch replayer.prepare(word) {
        case .success(let prepared):
            if parity {
                let typr = try await replayer.replay(word, prepared, context: context)
                pairs.append(.success((prepared, typr, replayer.replayHex(word, prepared, context: context))))
            } else if engine == .hex {
                results.append(replayer.replayHex(word, prepared, context: context).map { (prepared, $0) })
            } else {
                results.append(try await replayer.replay(word, prepared, context: context).map { (prepared, $0) })
            }
        case .failure(let reason):
            results.append(.failure(reason))
            pairs.append(.failure(reason))
        }
        if Replayer.separators.contains(word.end), !word.meant.isEmpty {
            previous = Array((previous + [word.meant + word.end]).suffix(3))
        } else {
            previous = []
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if parity {
        let report = ParityReport.build(words: export.words, results: pairs, showWords: showWords)
        print(json ? String(decoding: try encoder.encode(report), as: UTF8.self) + "\n" : report.text(), terminator: "")
        return
    }
    let report = Report.build(engine: engine, words: export.words, results: results, showWords: showWords)
    print(json ? String(decoding: try encoder.encode(report), as: UTF8.self) + "\n" : report.text(), terminator: "")
}

do {
    try await run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("keyboard-replay: \(error)\n".utf8))
    exit(1)
}
