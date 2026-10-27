import Foundation

/// The numbers the app's typing test reports. Text is measured in `Character`s (graphemes), so an emoji with a
/// skin tone, a flag or a family counts as one character, as it does for the person typing.
public enum TypingMetrics {
    /// The fewest characters to insert, delete or replace to turn `a` into `b` (Levenshtein distance).
    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        // Two rows of the usual table: the distances from a[..<i-1] and from a[..<i] to each prefix of b.
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let replace = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(replace, previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Typing speed in the usual words of 5 characters: (characters / 5) per minute. 0 if `seconds` isn't above 0.
    public static func wordsPerMinute(characters: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(characters) / 5 / (seconds / 60)
    }

    /// What the test compares with the target: `typed` without spaces or new lines at its end, and with curly quotes
    /// and apostrophes made straight. Some keyboards add a space after a word, and iOS's Smart Punctuation may curl a
    /// typed `'`, so neither counts as an error. A space at the start was tapped by mistake, so it stays and counts.
    /// The bundled sentences are already in this form.
    public static func normalized(_ typed: String) -> String {
        let end = typed.lastIndex { !$0.isWhitespace }.map(typed.index(after:)) ?? typed.startIndex
        return String(typed[..<end].map { straightQuotes[$0] ?? $0 })
    }

    private static let straightQuotes: [Character: Character] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
    ]
}
