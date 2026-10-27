import Foundation

/// When kittykeys steps aside for a one-time code field. iOS offers a code from Messages only on Apple's keyboard
/// and gives other keyboards no way to read it, so in such a field kittykeys switches to the next keyboard, once.
/// When the user comes back with 🌐, they chose kittykeys: it stays in that field, and in any other code field
/// within a minute of the last one, which covers a code split over several boxes. It never hands off a field it
/// stayed in.
///
/// The memory sits in a `UserDefaults`, since iOS starts a new keyboard process when it likes. In the keyboard
/// that is the extension's own `.standard` defaults, which need no Full Access. Never traps: missing or corrupt
/// values read as no hand-off.
public struct CodeFieldHandOff {
    /// What to do in a code field.
    public enum Decision: Equatable, Sendable {
        /// Switch to the next keyboard.
        case handOff
        /// Stay: kittykeys handed this field off, so the user came back, or it already stayed in it.
        case sameField
        /// Stay: another code field within a minute of the last one.
        case quietPeriod
        /// Stay for now: iOS names no field, as it does for a moment while focus moves between fields.
        case noDocument
    }

    private static let documentKey = "catkeys.codeHandOff.document"
    private static let dateKey = "catkeys.codeHandOff.date"
    /// Seconds after the last code field in which another one isn't handed off.
    private static let quietPeriod: TimeInterval = 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Decides for the code field `document`, which iOS names with `UITextDocumentProxy.documentIdentifier`, at
    /// `now`, and remembers the field and the time for every decision but `noDocument`. So a user who came back
    /// after minutes still keeps kittykeys for the next box, and the field kittykeys stays in is never handed off later.
    public func decide(document: UUID?, now: Date) -> Decision {
        guard let document else { return .noDocument }
        let decision = reasonToStay(in: document, now: now) ?? .handOff
        defaults.set(document.uuidString, forKey: Self.documentKey)
        defaults.set(now, forKey: Self.dateKey)
        return decision
    }

    /// Why kittykeys stays in `document`, or nil to hand it off. A clock set back ends the quiet period.
    private func reasonToStay(in document: UUID, now: Date) -> Decision? {
        guard let last = defaults.object(forKey: Self.dateKey) as? Date else { return nil }
        if defaults.string(forKey: Self.documentKey) == document.uuidString { return .sameField }
        return (0..<Self.quietPeriod).contains(now.timeIntervalSince(last)) ? .quietPeriod : nil
    }
}
