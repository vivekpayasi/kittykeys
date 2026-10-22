/// What kind of text a field takes, from its keyboard type. It picks the bottom row and the first page.
public enum FieldKind: Sendable { case text, email, url, number }

/// What the return key says, from the field's return key type.
public enum ReturnKeyKind: Sendable { case standard, go, search, join, next, route, send, done, emergencyCall, `continue` }

/// The text field's traits that change the keyboard, as the host reads them from iOS.
public struct FieldTraits: Equatable, Sendable {
    public var kind: FieldKind
    public var autoCap: AutoCapMode
    public var returnKey: ReturnKeyKind

    public init(kind: FieldKind = .text, autoCap: AutoCapMode = .sentences, returnKey: ReturnKeyKind = .standard) {
        self.kind = kind
        self.autoCap = autoCap
        self.returnKey = returnKey
    }
}
