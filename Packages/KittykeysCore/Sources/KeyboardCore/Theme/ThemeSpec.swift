/// A keyboard theme: what the gallery lists and the app saves. It has a look for light mode and, if the user added
/// one, its own look for dark mode; the keyboard draws the one for the appearance (`Themes.active`).
public struct ThemeSpec: Hashable, Sendable, Identifiable {
    /// A ready-made theme's name, such as "neon", or `custom-<UUID>` for one of the user's.
    public var id: String
    public var name: String
    public var light: ThemeStyle
    /// The look in dark mode; nil for the light look in both.
    public var dark: ThemeStyle?

    public init(id: String, name: String, light: ThemeStyle, dark: ThemeStyle?) {
        self.id = id
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// The look for dark mode or light mode.
    public func style(isDark: Bool) -> ThemeStyle {
        isDark ? dark ?? light : light
    }
}

extension ThemeSpec: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, light, dark
    }

    /// Saved as `{"id", "name", "light", "dark"}`. Version 0.5.0 saved the look's fields flat beside the id and name;
    /// such a theme loads as its light look. A dark look that can't be read is dropped. The id is required: a theme
    /// without one can't be picked.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "A theme needs an id")
        }
        self.id = id
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Theme"
        if container.contains(.light) {
            light = (try? container.decode(ThemeStyle.self, forKey: .light)) ?? Themes.automaticLight
        } else {
            light = try ThemeStyle(from: decoder)
        }
        dark = (try? container.decodeIfPresent(ThemeStyle.self, forKey: .dark)) ?? nil
    }
}
