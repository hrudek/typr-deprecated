import Foundation

/// Hex's Settings › Dictation language (BCP 47), in the App Group so the keyboard reads it.
/// Following the keyboard takes the keyboard's languages as BCP 47 identifiers.
nonisolated struct LanguageSettings {
    private enum Key {
        static let dictation = "settings.dictationLanguage"
        static let resolvedDictation = "settings.dictationLanguage.resolved"
        static let automaticDictation = "settings.dictationLanguage.automatic"
        static let recent = "settings.dictationLanguage.recent"
        static let removed = "settings.dictationLanguage.removed"
        static let supported = "settings.dictationLanguage.supported"
        static let keyboardLanguages = "settings.keyboardLanguages"
        static let currentKeyboardLanguage = "settings.keyboardLanguages.current"
        static let letterLayouts = "settings.keyboardLanguages.layouts"
        static let dictationFollowsKeyboard = "settings.keyboardLanguages.switchDictation"
        static let speechModuleFailed = "settings.dictationLanguage.speechModuleFailed"
        static let unavailable = "settings.dictationLanguage.unavailable"
        /// First failures, which set nothing aside until a second in a row.
        static let speechModuleStrikes = "settings.dictationLanguage.speechModuleStrikes"
        static let unavailableStrikes = "settings.dictationLanguage.unavailableStrikes"
    }

    static let maxRecent = 5
    /// How long a language whose speech model wouldn't install stays set aside before Typr
    /// tries it again: Apple's downloads that fail tend to keep failing for days.
    static let setAsideDuration: TimeInterval = 3 * 24 * 60 * 60

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: KeyboardBridge.appGroup)) {
        self.defaults = defaults
    }

    /// A BCP 47 identifier such as `nb-NO`, or nil for Automatic.
    var dictationLanguage: String? {
        get { defaults?.string(forKey: Key.dictation) }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictation) }
    }

    /// The language Apple Speech last resolved for dictation (the app or the keyboard), so
    /// translation can follow it without asking Speech again.
    var resolvedDictationLanguage: String? {
        get { defaults?.string(forKey: Key.resolvedDictation) }
        nonmutating set { defaults?.set(newValue, forKey: Key.resolvedDictation) }
    }

    /// What Automatic picks on this iPhone, when the app or keyboard last worked it out.
    var automaticDictationLanguage: String? {
        get { defaults?.string(forKey: Key.automaticDictation) }
        nonmutating set { defaults?.set(newValue, forKey: Key.automaticDictation) }
    }

    /// Languages picked lately, newest first, for the keyboard's quick switch.
    var recentDictationLanguages: [String] {
        get { defaults?.stringArray(forKey: Key.recent) ?? [] }
        nonmutating set { defaults?.set(Array(newValue.prefix(Self.maxRecent)), forKey: Key.recent) }
    }

    /// Languages taken off the keyboard's quick switch (as it listed them), so the iPhone's own
    /// languages stay off it too, until picked again.
    var removedDictationLanguages: [String] {
        get { defaults?.stringArray(forKey: Key.removed) ?? [] }
        nonmutating set { defaults?.set(newValue, forKey: Key.removed) }
    }

    /// Takes a language off the keyboard's quick switch: out of the recents, and kept off
    /// while it is one of the iPhone's languages. The one set goes back to Automatic.
    func removeDictationLanguage(_ identifier: String) {
        let supported = supportedDictationLanguages
        func same(_ other: String) -> Bool {
            other == identifier || DictationLanguageSwitch.supportedMatch(for: other, in: supported) == identifier
        }
        recentDictationLanguages = recentDictationLanguages.filter { !same($0) }
        if !removedDictationLanguages.contains(identifier) {
            removedDictationLanguages.append(identifier)
        }
        if let current = dictationLanguage, same(current) {
            dictationLanguage = nil
        }
    }

    /// Every language Apple Speech transcribes here (BCP 47), as last listed, so the
    /// keyboard can offer only those without asking Speech.
    var supportedDictationLanguages: [String] {
        get { defaults?.stringArray(forKey: Key.supported) ?? [] }
        nonmutating set { defaults?.set(newValue, forKey: Key.supported) }
    }

    /// The Hex keyboard's languages in order, the space bar switching between them; empty is
    /// Automatic (the dictation language's layout). Typr reads German and English only
    /// (`KeyboardLanguage.selectable`); another stored language is skipped, not rewritten.
    var keyboardLanguages: [KeyboardLanguage] {
        get {
            let stored = defaults?.stringArray(forKey: Key.keyboardLanguages) ?? []
            var seen = Set<KeyboardLanguage>()
            return stored.compactMap(KeyboardLanguage.init(rawValue:))
                .filter { KeyboardLanguage.selectable().contains($0) && seen.insert($0).inserted }
        }
        nonmutating set {
            var seen = Set<KeyboardLanguage>()
            defaults?.set(newValue.filter { seen.insert($0).inserted }.map(\.rawValue), forKey: Key.keyboardLanguages)
        }
    }

    /// How a language arranges its letters (`KeyboardLetterLayout`). A language never set, or
    /// set to one it no longer offers, types on its own layout.
    func letterLayout(for language: KeyboardLanguage) -> KeyboardLetterLayout {
        language.offered(letterLayouts[language.rawValue].flatMap(KeyboardLetterLayout.init(rawValue:)))
    }

    func setLetterLayout(_ letters: KeyboardLetterLayout, for language: KeyboardLanguage) {
        var all = letterLayouts
        all[language.rawValue] = language.offered(letters).rawValue
        defaults?.set(all, forKey: Key.letterLayouts)
    }

    var letterLayouts: [String: String] {
        defaults?.dictionary(forKey: Key.letterLayouts) as? [String: String] ?? [:]
    }

    /// The language the space bar last switched to, so the keyboard comes back in it.
    var currentKeyboardLanguage: KeyboardLanguage? {
        get {
            guard let language = defaults?.string(forKey: Key.currentKeyboardLanguage)
                .flatMap(KeyboardLanguage.init(rawValue:)) else { return nil }
            return KeyboardLanguage.selectable().contains(language) ? language : nil
        }
        nonmutating set { defaults?.set(newValue?.rawValue, forKey: Key.currentKeyboardLanguage) }
    }

    /// Switching the keyboard's language switches the dictation language to it. Off by default.
    var dictationFollowsKeyboard: Bool {
        get { defaults?.bool(forKey: Key.dictationFollowsKeyboard) ?? false }
        nonmutating set { defaults?.set(newValue, forKey: Key.dictationFollowsKeyboard) }
    }

    /// What Automatic dictates in while the keyboard switches between two or more languages:
    /// the one it types now (`current`, else the first of `keyboard`), in the iPhone's region
    /// where Apple Speech has it, so Spanish speech is never transcribed as English. `keyboard`
    /// is the keyboard's languages in order (BCP 47, such as `de-DE`). Nil with a dictation
    /// language picked by hand, with one keyboard language, and while the iPhone's own language
    /// (what Automatic picks otherwise) has no layout to type it (`hasLayout`, Hebrew), where
    /// dictating is how that language gets written, unless `dictationFollowsKeyboard` asks for it.
    /// `ignoringPick`: as on Automatic, whatever the setting holds.
    func keyboardDictationLanguage(
        keyboard: [String],
        current: String?,
        preferred: [String] = Locale.preferredLanguages,
        region: String? = Locale.current.region?.identifier,
        hasLayout: (String) -> Bool = LanguageSettings.hexHasLayout,
        ignoringPick: Bool = false
    ) -> String? {
        guard ignoringPick || dictationLanguage == nil, keyboard.count > 1 else { return nil }
        if !dictationFollowsKeyboard,
           let own = automaticDictationLanguage ?? preferred.first,
           !hasLayout(own) {
            return nil
        }
        let typing = current.flatMap { keyboard.contains($0) ? $0 : nil } ?? keyboard[0]
        return dictationLanguage(forKeyboard: typing, preferred: preferred, region: region)
    }

    /// Whether Hex has a keyboard layout for a language identifier (Hex's
    /// `KeyboardLanguage.matching`, Korean's experiment off): Serbian only in Latin script.
    static func hexHasLayout(_ identifier: String) -> Bool {
        let parts = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        switch parts.first ?? "" {
        case "nb", "no", "nn", "en", "es", "de", "it", "fr", "pt", "pl", "cs", "hu", "ro", "ru", "uk", "el": return true
        case "sr": return parts.contains("latn")
        default: return false
        }
    }

    /// What a keyboard language (BCP 47) dictates in on Automatic: the variant picked for that
    /// language last (`recentDictationLanguages`), then the iPhone's preferred variants, then
    /// the keyboard's own, among the languages Apple Speech has here (any while not listed yet).
    /// Spanish follows `DictationLanguageSwitch.spanishCandidates`. Canadian and Swiss French
    /// keep their own region. Nil when Apple Speech has none of it, and for Serbian before the
    /// list is known (Apple Speech has no Serbian).
    func dictationLanguage(
        forKeyboard keyboard: String,
        preferred: [String] = Locale.preferredLanguages,
        region: String? = Locale.current.region?.identifier
    ) -> String? {
        let base = DictationLanguageSwitch.languageCode(of: keyboard)
        func sameBase(_ identifier: String) -> Bool { DictationLanguageSwitch.languageCode(of: identifier) == base }
        let picked = recentDictationLanguages.first(where: sameBase)
        let supported = supportedDictationLanguages
        if base == "es" {
            let named = ([picked].compactMap { $0 } + preferred).first {
                sameBase($0) && Locale(identifier: $0).region != nil
            }
            guard !supported.isEmpty else { return named ?? DictationLanguageSwitch.spanish(forRegion: region) }
            return DictationLanguageSwitch.supportedMatch(for: named ?? "es", in: supported, region: region)
        }
        let keyboardRegion = Locale(identifier: keyboard).region?.identifier
        let ownRegion = base == "fr" && (keyboardRegion == "CA" || keyboardRegion == "CH")
        let mine = ownRegion ? [] : [picked].compactMap { $0 } + preferred.filter(sameBase)
        let candidates = mine + [keyboard]
        guard !supported.isEmpty else { return base == "sr" ? nil : candidates.first }
        func key(_ identifier: String) -> String {
            identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        }
        let offered = Dictionary(supported.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        for candidate in candidates {
            if let found = offered[key(candidate)] { return found }
        }
        if ownRegion { return nil }
        return supported.first(where: sameBase)
    }

    /// The language dictation uses, when known: the one set, else the keyboard's it follows,
    /// else what Automatic picks, else the last one it ran in.
    func effectiveDictationLanguage(keyboard: [String] = [], current: String? = nil) -> String? {
        dictationLanguage
            ?? keyboardDictationLanguage(keyboard: keyboard, current: current)
            ?? automaticDictationLanguage
            ?? resolvedDictationLanguage
    }

    /// `SpeechTranscriber`'s model for this language (BCP 47) wouldn't install, so dictation
    /// uses `DictationTranscriber`'s for a while.
    func markSpeechModuleFailed(_ identifier: String, at now: Date = Date()) {
        mark(identifier, key: Key.speechModuleFailed, at: now)
    }

    func speechModuleFailed(_ identifier: String, now: Date = Date()) -> Bool {
        isMarked(identifier, key: Key.speechModuleFailed, now: now)
    }

    /// `SpeechTranscriber`'s model for this language failed to install: set aside
    /// (`markSpeechModuleFailed`) the second time in a row, within `setAsideDuration`.
    func noteSpeechModuleFailure(_ identifier: String, at now: Date = Date()) {
        if strike(identifier, key: Key.speechModuleStrikes, at: now) {
            markSpeechModuleFailed(identifier, at: now)
        }
    }

    /// Neither module's model installed while online: set aside (`markUnavailable`) the
    /// second time in a row, within `setAsideDuration`.
    func noteUnavailable(_ identifier: String, at now: Date = Date()) {
        if strike(identifier, key: Key.unavailableStrikes, at: now) {
            markUnavailable(identifier, at: now)
        }
    }

    /// A model installed for this language: its failures so far no longer count.
    func clearFailureStrikes(_ identifier: String, speechModule: Bool) {
        let key = Locale(identifier: identifier).identifier(.bcp47)
        for strikes in speechModule ? [Key.speechModuleStrikes, Key.unavailableStrikes] : [Key.unavailableStrikes] {
            guard var marks = defaults?.dictionary(forKey: strikes) as? [String: Double],
                  marks.removeValue(forKey: key) != nil else { continue }
            defaults?.set(marks, forKey: strikes)
        }
    }

    /// Records a first failure and returns false, or clears it and returns true for a second.
    private func strike(_ identifier: String, key: String, at now: Date) -> Bool {
        if isMarked(identifier, key: key, now: now) {
            var marks = (defaults?.dictionary(forKey: key) as? [String: Double]) ?? [:]
            marks.removeValue(forKey: Locale(identifier: identifier).identifier(.bcp47))
            defaults?.set(marks, forKey: key)
            return true
        }
        mark(identifier, key: key, at: now)
        return false
    }

    /// Neither module's model for this language (BCP 47) would install while online, so
    /// Automatic passes over it for a while. An explicit choice still tries it.
    func markUnavailable(_ identifier: String, at now: Date = Date()) {
        mark(identifier, key: Key.unavailable, at: now)
    }

    func isUnavailable(_ identifier: String, now: Date = Date()) -> Bool {
        isMarked(identifier, key: Key.unavailable, now: now)
    }

    /// A language that installed after all.
    func clearUnavailable(_ identifier: String) {
        let key = Locale(identifier: identifier).identifier(.bcp47)
        guard var marks = defaults?.dictionary(forKey: Key.unavailable) as? [String: Double],
              marks.removeValue(forKey: key) != nil else { return }
        defaults?.set(marks, forKey: Key.unavailable)
    }

    private func mark(_ identifier: String, key: String, at now: Date) {
        var marks = (defaults?.dictionary(forKey: key) as? [String: Double]) ?? [:]
        marks = marks.filter { now.timeIntervalSince1970 - $0.value < Self.setAsideDuration }
        marks[Locale(identifier: identifier).identifier(.bcp47)] = now.timeIntervalSince1970
        defaults?.set(marks, forKey: key)
    }

    private func isMarked(_ identifier: String, key: String, now: Date) -> Bool {
        guard let marks = defaults?.dictionary(forKey: key) as? [String: Double],
              let at = marks[Locale(identifier: identifier).identifier(.bcp47)] else { return false }
        return now.timeIntervalSince1970 - at < Self.setAsideDuration
    }

    /// A choice made in Typr or the keyboard: the setting, and the front of the recents. The
    /// other variants of that language leave the recents (`DictationLanguageSwitch.variantKey`),
    /// so es-US and es-ES never both take a chip; Chinese's variants stay apart.
    func chooseDictationLanguage(_ identifier: String?) {
        dictationLanguage = identifier
        guard let identifier else { return }
        let key = DictationLanguageSwitch.variantKey(of: identifier)
        recentDictationLanguages = [identifier] + recentDictationLanguages.filter {
            guard $0 != identifier else { return false }
            guard let key else { return true }
            return DictationLanguageSwitch.variantKey(of: $0) != key
        }
        let match = DictationLanguageSwitch.supportedMatch(for: identifier, in: supportedDictationLanguages)
        let removed = removedDictationLanguages
        if removed.contains(where: { $0 == identifier || $0 == match }) {
            removedDictationLanguages = removed.filter { $0 != identifier && $0 != match }
        }
    }
}

extension LanguageSettings {
    /// The dictation language for the engine choice: German or English
    /// (`typrDictationLanguage`, which follows the keyboard on Automatic); nil is Automatic.
    func explicitDictationLanguage(typr: DictationLanguage) -> String? {
        typr.speechLocaleIdentifier
    }

    /// The languages Typr offers to dictate in.
    static let typrDictationLanguages = ["de-DE", "en-US"]

    /// Settings › Language's choice: German, English or Automatic (Hex's setting; Typr's own
    /// under the Typr fixed dictation language). Any other language stored there reads as
    /// Automatic; nothing is rewritten.
    func typrDictationChoice(typr: TyprSettings) -> DictationLanguage {
        typr[experiment: .typrFixedDictationLanguage] ? typr.dictationLanguage : DictationLanguage(identifier: dictationLanguage)
    }

    /// The language the next dictation uses: the choice, and on Automatic the keyboard's
    /// language while it switches between German and English (`keyboardDictationLanguage`).
    /// Typr fixed dictation language: Typr's choice only.
    func typrDictationLanguage(typr: TyprSettings) -> DictationLanguage {
        let choice = typrDictationChoice(typr: typr)
        guard choice == .automatic, !typr[experiment: .typrFixedDictationLanguage] else { return choice }
        return DictationLanguage(identifier: keyboardDictationLanguage(
            keyboard: keyboardLanguages.map(\.inputModeLanguage),
            current: currentKeyboardLanguage?.inputModeLanguage,
            ignoringPick: true
        ))
    }

    /// A choice from Settings or the Typr key menu, into the store `typrDictationChoice` reads.
    func chooseTyprDictationLanguage(_ language: DictationLanguage, typr: TyprSettings) {
        if typr[experiment: .typrFixedDictationLanguage] {
            typr.dictationLanguage = language
        } else {
            chooseDictationLanguage(language.speechLocaleIdentifier)
        }
    }
}

/// The Apple Speech module that transcribes a language. `SpeechTranscriber` is Apple's newer
/// model and the default; `DictationTranscriber` (the model behind the iOS keyboard's
/// dictation) covers languages it lacks, such as Norwegian, Danish, and Swedish.
nonisolated enum SpeechModuleKind: String, Codable, Sendable {
    case speech
    case dictation
}

nonisolated struct SpeechLanguage: Equatable, Sendable {
    let locale: Locale
    let module: SpeechModuleKind

    var identifier: String { locale.identifier(.bcp47) }
    var languageCode: String? { locale.language.languageCode?.identifier }
}

/// Which language and Apple Speech module a dictation uses.
nonisolated enum SpeechLanguagePicker {
    /// What Automatic tries, in order: the iPhone's preferred languages, its own locale, then
    /// US English. Norwegian Nynorsk also tries Bokmål, the only Norwegian Apple transcribes.
    /// Spanish tries its variants (`DictationLanguageSwitch.spanishCandidates`) in order.
    static func automaticCandidates(
        preferred: [String],
        current: String,
        region: String? = Locale.current.region?.identifier
    ) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func add(_ identifier: String) {
            let key = Locale(identifier: identifier).identifier(.bcp47)
            if seen.insert(key).inserted {
                result.append(identifier)
            }
        }
        for identifier in preferred + [current, "en-US"] {
            if Locale(identifier: identifier).language.languageCode?.identifier == "es" {
                for candidate in DictationLanguageSwitch.spanishCandidates(for: identifier, region: region) {
                    add(candidate)
                }
                continue
            }
            add(identifier)
            if Locale(identifier: identifier).language.languageCode?.identifier == "nn" {
                add("nb-NO")
            }
        }
        return result
    }

    /// An explicit choice wins: `SpeechTranscriber` when it has that language, else
    /// `DictationTranscriber`. Automatic takes the first candidate either module has,
    /// preferring `SpeechTranscriber` for the same language, so a Norwegian iPhone gets
    /// Norwegian from `DictationTranscriber` rather than English from `SpeechTranscriber`.
    /// `speech` and `dictation` return each module's equivalent locale, or nil. An explicit
    /// choice neither module has falls through to Automatic's candidates. Automatic passes over
    /// a language `skip` names (one whose model wouldn't install here); when every one was set
    /// aside it tries the first of them again: nil means neither module has any of them.
    static func pick(
        explicit: String?,
        candidates: [String],
        region: String? = Locale.current.region?.identifier,
        speech: (Locale) async -> Locale?,
        dictation: (Locale) async -> Locale?,
        skip: (Locale) -> Bool = { _ in false }
    ) async -> SpeechLanguage? {
        if let explicit, !explicit.isEmpty {
            let spanish = Locale(identifier: explicit).language.languageCode?.identifier == "es"
            let wanted = spanish
                ? DictationLanguageSwitch.spanishCandidates(for: explicit, region: region)
                : [explicit]
            for identifier in wanted {
                let candidate = Locale(identifier: identifier)
                if let found = await speech(candidate), sameLanguage(found, candidate) {
                    return SpeechLanguage(locale: found, module: .speech)
                }
                if let found = await dictation(candidate), !spanish || sameLanguage(found, candidate) {
                    return SpeechLanguage(locale: found, module: .dictation)
                }
            }
        }
        var setAside: SpeechLanguage?
        for identifier in candidates {
            let candidate = Locale(identifier: identifier)
            let spanish = Locale(identifier: identifier).language.languageCode?.identifier == "es"
            if let found = await speech(candidate), !spanish || sameLanguage(found, candidate) {
                let language = SpeechLanguage(locale: found, module: .speech)
                guard skip(found) else { return language }
                setAside = setAside ?? language
                continue
            }
            if let found = await dictation(candidate), !spanish || sameLanguage(found, candidate) {
                let language = SpeechLanguage(locale: found, module: .dictation)
                guard skip(found) else { return language }
                setAside = setAside ?? language
            }
        }
        return setAside
    }

    /// The same language and, when both name one, the same region.
    private static func sameLanguage(_ a: Locale, _ b: Locale) -> Bool {
        guard a.language.languageCode == b.language.languageCode else { return false }
        guard let ra = a.region, let rb = b.region else { return true }
        return ra == rb
    }

    /// Whether a language identifier is English, for the English-only steps. nil (unknown)
    /// counts as English.
    static func isEnglish(_ identifier: String?) -> Bool {
        guard let identifier else { return true }
        return Locale(identifier: identifier).language.languageCode?.identifier == "en"
    }
}

/// How dictation languages match Apple Speech's list: aliases, variants and Spanish regions.
nonisolated enum DictationLanguageSwitch {
    /// The supported locale for an identifier: the same region, else the language's usual
    /// region ("es" is Spain's), else any. Nynorsk maps to Bokmål. With no list, itself.
    /// Spanish follows `spanishCandidates`.
    static func supportedMatch(
        for identifier: String,
        in supported: [String],
        region: String? = Locale.current.region?.identifier
    ) -> String? {
        let wanted = Locale(identifier: identifier)
        guard !supported.isEmpty else { return wanted.identifier(.bcp47) }
        var code = wanted.language.languageCode?.identifier
        if code == "nn" || code == "no" { code = "nb" }
        let candidates = supported.filter { Locale(identifier: $0).language.languageCode?.identifier == code }
        guard !candidates.isEmpty, let code else { return nil }
        if code == "es" {
            for fallback in spanishCandidates(for: identifier, region: region) {
                let wantedRegion = Locale(identifier: fallback).region?.identifier
                if let exact = candidates.first(where: { Locale(identifier: $0).region?.identifier == wantedRegion }) {
                    return exact
                }
            }
            return candidates.first
        }
        if let region = wanted.region?.identifier,
           let exact = candidates.first(where: { Locale(identifier: $0).region?.identifier == region }) {
            return exact
        }
        let usual = Locale.Language(identifier: Locale.Language(identifier: code).maximalIdentifier).region?.identifier
        return candidates.first { Locale(identifier: $0).region?.identifier == usual } ?? candidates.first
    }

    /// The iPhone's regions whose Spanish Apple Speech calls Latin American: es-US serves the
    /// United States, Puerto Rico and Latin America, and Mexico has es-MX.
    private static let latinAmericanSpanishRegions: Set<String> = [
        "419", "AR", "BO", "CL", "CO", "CR", "CU", "DO", "EC", "SV", "GT", "HN", "NI", "PA",
        "PY", "PE", "PR", "US", "UY", "VE",
    ]

    /// The Spanish variant the iPhone's Region dictates in when nothing else names one: es-MX
    /// for Mexico, es-US for the United States, Puerto Rico and Latin America, else es-ES.
    static func spanish(forRegion region: String?) -> String {
        let code = region?.uppercased()
        if code == "MX" { return "es-MX" }
        if let code, latinAmericanSpanishRegions.contains(code) { return "es-US" }
        return "es-ES"
    }

    /// Apple's Spanish locales for an identifier, best first: its own (Apple may have it), then
    /// es-US and es-MX for a region that is neither Spain's nor Equatorial Guinea's, and Spain's
    /// es-ES. Plain Spanish (no region) starts from the iPhone's Region's variant.
    static func spanishCandidates(
        for identifier: String,
        region: String? = Locale.current.region?.identifier
    ) -> [String] {
        let wanted = Locale(identifier: identifier).region?.identifier
        var result: [String] = []
        if let wanted {
            result = ["es-\(wanted)"]
            if wanted == "ES" || wanted == "GQ" {
                result.append("es-ES")
            } else {
                result += ["es-US", "es-MX", "es-ES"]
            }
        } else {
            result = [spanish(forRegion: region), "es-US", "es-MX", "es-ES"]
        }
        var seen = Set<String>()
        return result.filter { seen.insert(Locale(identifier: $0).identifier(.bcp47)).inserted }
    }

    /// The language an identifier belongs to, with Apple's aliases: Nynorsk and Norwegian are
    /// Bokmål, and a script (Srpski's Latin) stays out of it.
    static func languageCode(of identifier: String) -> String? {
        let code = Locale(identifier: identifier).language.languageCode?.identifier
        return code == "nn" || code == "no" ? "nb" : code
    }

    /// Which languages count as one in the recents: es-US and es-ES are one. Chinese is never
    /// one: Mandarin's zh-CN, Taiwan's zh-TW and Cantonese's zh-HK each keep their identifier.
    static func variantKey(of identifier: String) -> String? {
        guard let code = languageCode(of: identifier) else { return nil }
        guard code == "zh" || code == "yue" else { return code }
        return Locale(identifier: identifier).identifier(.bcp47)
    }
}
