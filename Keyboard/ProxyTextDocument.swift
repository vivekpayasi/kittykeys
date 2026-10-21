import KeyboardCore
import OSLog
import UIKit

/// The host app's text field, edited through the keyboard extension's `UITextDocumentProxy`.
/// iOS reports only part of the text around the cursor, and nil for a side it doesn't know.
@MainActor final class ProxyTextDocument: TextDocument {
    /// Held weakly and asked for its proxy on each call: the view controller owns this document through the
    /// keyboard controller, and a strong reference back could keep a dismissed keyboard alive.
    private weak var host: UIInputViewController?
    private let signposter: OSSignposter

    init(host: UIInputViewController, signposter: OSSignposter) {
        self.host = host
        self.signposter = signposter
    }

    private var proxy: (any UITextDocumentProxy)? { host?.textDocumentProxy }

    var textBefore: String? { proxy?.documentContextBeforeInput }

    var textAfter: String? { proxy?.documentContextAfterInput }

    func insert(_ text: String) {
        let interval = signposter.beginInterval("insert")
        proxy?.insertText(text)
        signposter.endInterval("insert", interval)
    }

    func deleteBackward(count: Int) {
        guard let proxy, count > 0 else { return }
        for _ in 0..<count { proxy.deleteBackward() }
    }

    /// iOS moves the cursor in UTF-16 units, so the grapheme count is converted with the text either side.
    func moveCursor(by graphemes: Int) {
        guard let proxy else { return }
        let offset = TextOffsets.utf16Offset(
            graphemes: graphemes, before: proxy.documentContextBeforeInput, after: proxy.documentContextAfterInput)
        if offset != 0 { proxy.adjustTextPosition(byCharacterOffset: offset) }
    }

    /// The field's traits that change the keyboard. A trait the field doesn't report takes `FieldTraits`' default.
    var traits: FieldTraits {
        guard let proxy else { return FieldTraits() }
        return FieldTraits(
            kind: Self.kind(of: proxy.keyboardType), autoCap: Self.autoCap(of: proxy.autocapitalizationType),
            returnKey: Self.returnKey(of: proxy.returnKeyType))
    }

    private static func kind(of keyboardType: UIKeyboardType?) -> FieldKind {
        switch keyboardType {
        case .emailAddress?: .email
        case .URL?, .webSearch?: .url
        case .numberPad?, .decimalPad?, .asciiCapableNumberPad?, .numbersAndPunctuation?: .number
        default: .text
        }
    }

    private static func autoCap(of type: UITextAutocapitalizationType?) -> AutoCapMode {
        switch type {
        case .some(.none): .none
        case .words?: .words
        case .allCharacters?: .all
        default: .sentences
        }
    }

    /// Search engines' return keys say Search; a return key type added later says return.
    private static func returnKey(of type: UIReturnKeyType?) -> ReturnKeyKind {
        switch type {
        case .go?: .go
        case .search?, .google?, .yahoo?: .search
        case .join?: .join
        case .next?: .next
        case .route?: .route
        case .send?: .send
        case .done?: .done
        case .emergencyCall?: .emergencyCall
        case .continue?: .continue
        default: .standard
        }
    }
}
