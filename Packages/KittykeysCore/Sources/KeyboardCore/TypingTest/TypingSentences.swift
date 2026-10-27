import Foundation

/// One sentence the typing test asks for. `language` is a BCP 47 tag: "en" for English, "hi-Latn" for Hinglish.
public struct TypingSentence: Equatable, Sendable {
    public var text: String
    public var language: String

    public init(text: String, language: String) {
        self.text = text
        self.language = language
    }
}

/// The typing test's sentences, bundled as `TypingTest/sentences.json`: short, invented chat messages, half English
/// and half Hinglish, each starting with a capital as both keyboards type it.
public enum TypingSentences {
    public enum LoadError: Error {
        case missingFile(String)
    }

    private struct Entry: Decodable {
        var text: String
        var language: String
    }

    /// Reads the bundled sentences, in file order.
    public static func bundled() throws -> [TypingSentence] {
        guard let url = Bundle.module.url(forResource: "sentences", withExtension: "json") else {
            throw LoadError.missingFile("sentences.json")
        }
        let entries = try JSONDecoder().decode([Entry].self, from: try Data(contentsOf: url))
        return entries.map { TypingSentence(text: $0.text, language: $0.language) }
    }

    /// `count` different sentences drawn at random, alternating languages: `majority` first, then the others, so 5
    /// gives 3 in `majority` and 2 in the others. When one side runs out, the other fills in.
    public static func balancedDraw<G: RandomNumberGenerator>(
        _ sentences: [TypingSentence], count: Int, majority: String, using generator: inout G
    ) -> [TypingSentence] {
        var major = sentences.filter { $0.language == majority }.shuffled(using: &generator)
        var minor = sentences.filter { $0.language != majority }.shuffled(using: &generator)
        var drawn: [TypingSentence] = []
        for slot in 0..<min(max(count, 0), sentences.count) {
            let fromMajor = slot.isMultiple(of: 2) ? !major.isEmpty : minor.isEmpty
            drawn.append(fromMajor ? major.removeLast() : minor.removeLast())
        }
        return drawn
    }

    /// The language to get the extra sentence in the next draw: the one after `last` among the languages of
    /// `sentences`, in alphabetical order and wrapping round, so runs take turns. The first language if `last` is
    /// nil or not among them; nil if there are no sentences.
    public static func nextMajority(after last: String?, in sentences: [TypingSentence]) -> String? {
        let languages = Set(sentences.map(\.language)).sorted()
        guard let last, let index = languages.firstIndex(of: last) else { return languages.first }
        return languages[(index + 1) % languages.count]
    }
}
