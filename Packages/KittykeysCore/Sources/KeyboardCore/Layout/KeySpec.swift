/// A page a key can switch to.
public enum PageRef: Equatable, Sendable {
    /// The letters page of the current layout set.
    case letters
    /// A page by its id, such as `symbols-1`.
    case named(String)
}

/// What a key does when activated.
///
/// In JSON it is a string: `character` (the default), `shift`, `backspace`,
/// `space`, `return`, `emoji`, `globe`, `page:letters` or `page:<id>`.
public enum KeyAction: Equatable, Sendable, Decodable {
    case character, shift, backspace, space, returnKey, emoji, globe
    case switchPage(PageRef)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "character": self = .character
        case "shift": self = .shift
        case "backspace": self = .backspace
        case "space": self = .space
        case "return": self = .returnKey
        case "emoji": self = .emoji
        case "globe": self = .globe
        case "page:letters": self = .switchPage(.letters)
        default:
            let pagePrefix = "page:"
            guard raw.hasPrefix(pagePrefix), raw.count > pagePrefix.count else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown key action \"\(raw)\"")
            }
            self = .switchPage(.named(String(raw.dropFirst(pagePrefix.count))))
        }
    }
}

/// One key as a layout file describes it.
public struct KeySpec: Equatable, Sendable, Decodable {
    /// The text the key shows, and its fallback and accessibility text when it has an `icon`.
    public var label: String
    /// The text a character key types. Defaults to `label`.
    public var output: String
    /// Long-press options, in popup order. Defaults to none.
    public var longPress: [String]
    /// The width of each long-press option's cell, in `TouchTiming.alternateWidth` units, for options wider than a
    /// symbol such as ".com". Defaults to 1.
    public var longPressWidth: Double
    /// Width in key units. Defaults to 1; 0 fills the space left in the row.
    public var width: Double
    public var action: KeyAction
    /// An SF Symbol the key shows in place of `label`, such as the emoji key's smiley. Defaults to none.
    public var icon: String?

    /// The symbol drawn in the key's corner: its first long-press option, for character keys only.
    public var cornerHint: String? {
        action == .character ? longPress.first : nil
    }

    /// Whether the key switches pages, as 123 and ABC do.
    var isPageKey: Bool {
        if case .switchPage = action { true } else { false }
    }
}

extension KeySpec {
    private enum CodingKeys: String, CodingKey {
        case label, output, longPress, longPressWidth, width, action, icon
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        output = try container.decodeIfPresent(String.self, forKey: .output) ?? label
        longPress = try container.decodeIfPresent([String].self, forKey: .longPress) ?? []
        longPressWidth = try container.decodeIfPresent(Double.self, forKey: .longPressWidth) ?? 1
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 1
        action = try container.decodeIfPresent(KeyAction.self, forKey: .action) ?? .character
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
    }
}
