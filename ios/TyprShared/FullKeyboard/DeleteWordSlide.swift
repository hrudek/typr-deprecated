/// Words as Option-Delete counts them on a Mac, for the delete-key slide: the spaces and punctuation
/// before the cursor go with the word in front of them. From Hex's `DeleteWordSwipe`
/// (anomalyco/hex #2080, d65b02d3).
enum DeleteWordSlide {
    /// How many characters at the end of `before` make up its last word with the spaces and
    /// punctuation after it ("Hallo, Welt. " ends in "Welt. "); nil when nothing is before the
    /// cursor. Only spaces and punctuation go at once.
    static func wordLength(before: String) -> Int? {
        guard !before.isEmpty else { return nil }
        var count = 0
        var index = before.endIndex
        while index > before.startIndex, !isWordCharacter(before[before.index(before: index)]) {
            index = before.index(before: index)
            count += 1
        }
        while index > before.startIndex, isWordCharacter(before[before.index(before: index)]) {
            index = before.index(before: index)
            count += 1
        }
        return count
    }

    /// Letters, digits, emoji and the apostrophe inside "don't" belong to a word.
    private static func isWordCharacter(_ character: Character) -> Bool {
        if character.isLetter || character.isNumber || character == "_" { return true }
        if character == "'" || character == "’" { return true }
        return character.unicodeScalars.first?.properties.isEmojiPresentation == true
    }
}
