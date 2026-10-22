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
}
