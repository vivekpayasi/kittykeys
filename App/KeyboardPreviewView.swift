import KeyboardCore
import KeyboardUI
import SwiftUI
import UIKit

/// The keyboard view hosted in the app, pinned to the bottom of the screen above a text view it types into.
/// The simulator screenshot script launches it with `-catkeysPreview`; see `PreviewScene` for the other arguments.
struct KeyboardPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        do {
            return KeyboardPreviewHost(layouts: try LayoutSet.bundled(), scene: PreviewScene(ProcessInfo.processInfo.arguments))
        } catch {
            let label = UILabel()
            label.text = "Couldn't load the layouts: \(error)"
            label.numberOfLines = 0
            return label
        }
    }

    func updateUIView(_ view: UIView, context: Context) {
        (view as? KeyboardPreviewHost)?.theme = context.environment.colorScheme == .dark ? .dark : .light
    }
}

/// What the preview shows, from launch arguments. Each step drives the controller as touches would.
/// - `-catkeysPreviewPage <id>`: taps page keys until page `id` shows.
/// - `-catkeysPreviewHold <label>`: holds the key with that label until its long-press options show.
/// - `-catkeysPreviewCursor`: holds space until cursor mode begins.
/// - `-catkeysPreviewEmoji`: taps the emoji key, opening the emoji panel.
/// - `-catkeysPreviewEmojiHold <emoji>`: opens the emoji panel, scrolls to `emoji` and holds it, so its skin-tone popup
///   shows if it has skin tones.
/// Held keys are never lifted.
struct PreviewScene {
    var pageID: String?
    var heldLabel: String?
    var holdsSpace: Bool
    var opensEmoji: Bool
    var heldEmoji: String?

    init(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        pageID = value(after: "-catkeysPreviewPage")
        heldLabel = value(after: "-catkeysPreviewHold")
        holdsSpace = arguments.contains("-catkeysPreviewCursor")
        heldEmoji = value(after: "-catkeysPreviewEmojiHold")
        opensEmoji = heldEmoji != nil || arguments.contains("-catkeysPreviewEmoji")
    }
}

/// A text view at the top and the keyboard at the bottom, sharing one controller.
/// The keyboard view is clear, so a grey like the system's keyboard backdrop goes behind it and below it.
final class KeyboardPreviewHost: UIView {
    /// Invented text, so the keyboard starts mid-sentence with shift off.
    private static let startingText = "Typing in the catkeys preview"
    /// How long each scripted tap is held, and the hold that outlasts the long-press and cursor-mode delays.
    private static let tapDuration = 0.05, holdDuration = 0.5
    /// The preview's one scripted finger. A real touch's id is a hash of its object, so a clash is vanishingly unlikely.
    private static let scriptedTouch: TouchID = 1
    /// The preview's own Recent and skin tones, emptied and filled with `sampleRecent` at each launch, so screenshots
    /// show the Recent section the same way every time.
    private static let emojiSuite = "catkeys.preview.emoji"
    /// Invented, most recent first.
    private static let sampleRecent = ["😂", "❤️", "👍🏽", "🙏", "🇮🇳", "👨‍👩‍👧", "🔥", "✅", "😭", "🎉"]

    var theme: KeyboardTheme = .light {
        didSet {
            keyboardView.theme = theme
            backdrop.backgroundColor = theme.backdrop
        }
    }

    private let layouts: LayoutSet
    private let controller: KeyboardController
    private let keyboardView: KeyboardView
    private let textView = UITextView()
    /// Behind the keyboard and the home-indicator area under it, as the system's backdrop is under a real one.
    private let backdrop = UIView()
    /// The scene still to play; it plays once the keyboard has laid out its keys.
    private var scene: PreviewScene?

    init(layouts: LayoutSet, scene: PreviewScene) {
        self.layouts = layouts
        self.scene = scene
        textView.text = Self.startingText
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isEditable = false
        controller = KeyboardController(
            document: TextViewDocument(textView), layouts: layouts, settings: KeyboardSettings(),
            feedback: SilentFeedback())
        controller.keyboardWillAppear(FieldTraits())
        keyboardView = KeyboardView(
            controller: controller, feedback: SilentFeedback(), emojiPreferences: Self.sampleEmojiPreferences())
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        backdrop.backgroundColor = theme.backdrop

        // The backdrop goes in first, so it sits behind the keyboard.
        for view in [backdrop, textView, keyboardView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: keyboardView.topAnchor, constant: -8),
            keyboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            backdrop.topAnchor.constraint(equalTo: keyboardView.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        keyboardView.layoutIfNeeded()
        guard let scene, !controller.frames.isEmpty else { return }
        self.scene = nil
        play(scene)
    }

    /// Opens the page, then holds one key: the labelled one, else space for cursor mode. Or opens the emoji panel and
    /// holds an emoji.
    private func play(_ scene: PreviewScene) {
        var clock = ProcessInfo.processInfo.systemUptime
        if let pageID = scene.pageID { open(page: pageID, clock: &clock) }
        if scene.opensEmoji, let emojiKey = controller.frames.first(where: { $0.key.action == .emoji }) {
            let centre = Self.centre(of: emojiKey)
            controller.touchDown(Self.scriptedTouch, at: centre, time: clock)
            controller.touchUp(Self.scriptedTouch, at: centre, time: clock + Self.tapDuration)
            if let emoji = scene.heldEmoji { keyboardView.showEmojiHoldForPreview(emoji) }
        } else if let label = scene.heldLabel {
            if let key = controller.frames.first(where: { $0.key.label == label }) { hold(key, at: clock) }
        } else if scene.holdsSpace, let space = controller.frames.first(where: { $0.key.action == .space }) {
            hold(space, at: clock)
        }
    }

    /// Taps page keys until page `id` shows: one that goes straight there, else one to a page not seen yet.
    private func open(page id: String, clock: inout Double) {
        var seen: Set<String> = [controller.state.pageID]
        while controller.state.pageID != id {
            let unseen: [(frame: KeyFrame, pageID: String)] = controller.frames.compactMap { frame in
                guard case .switchPage(let ref) = frame.key.action else { return nil }
                let pageID = layouts.resolve(ref)
                return seen.contains(pageID) ? nil : (frame, pageID)
            }
            guard let next = unseen.first(where: { $0.pageID == id }) ?? unseen.first else { return }
            seen.insert(next.pageID)
            let centre = Self.centre(of: next.frame)
            controller.touchDown(Self.scriptedTouch, at: centre, time: clock)
            clock += Self.tapDuration
            controller.touchUp(Self.scriptedTouch, at: centre, time: clock)
            clock += Self.tapDuration
        }
    }

    private func hold(_ frame: KeyFrame, at time: Double) {
        controller.touchDown(Self.scriptedTouch, at: Self.centre(of: frame), time: time)
        controller.advance(to: time + Self.holdDuration)
    }

    private static func sampleEmojiPreferences() -> EmojiPreferences {
        UserDefaults.standard.removePersistentDomain(forName: emojiSuite)
        let preferences = EmojiPreferences(defaults: UserDefaults(suiteName: emojiSuite) ?? .standard)
        for emoji in sampleRecent.reversed() { preferences.recordUse(emoji, base: emoji) }
        preferences.setPreferredVariant("👍🏽", for: "👍")
        return preferences
    }

    private static func centre(of frame: KeyFrame) -> KeyboardCore.Point {
        KeyboardCore.Point(x: frame.rect.midX, y: frame.rect.midY)
    }
}

/// A `TextDocument` over a `UITextView`, editing at a cursor of its own; the text view only displays the text.
/// Like iOS, it reports nil for a side of the cursor with no text.
@MainActor private final class TextViewDocument: TextDocument {
    private let textView: UITextView
    /// The cursor as a UTF-16 offset into the text.
    private var cursor: Int

    init(_ textView: UITextView) {
        self.textView = textView
        cursor = textView.text.utf16.count
    }

    var textBefore: String? {
        let text: String = textView.text
        return cursor == 0 ? nil : String(text[..<String.Index(utf16Offset: cursor, in: text)])
    }

    var textAfter: String? {
        let text: String = textView.text
        return cursor == text.utf16.count ? nil : String(text[String.Index(utf16Offset: cursor, in: text)...])
    }

    func insert(_ inserted: String) {
        var text: String = textView.text
        text.insert(contentsOf: inserted, at: String.Index(utf16Offset: cursor, in: text))
        textView.text = text
        cursor += inserted.utf16.count
    }

    func deleteBackward(count: Int) {
        var text: String = textView.text
        let end = String.Index(utf16Offset: cursor, in: text)
        let start = text[..<end].suffix(max(count, 0)).startIndex
        cursor -= text.utf16.distance(from: start, to: end)
        text.removeSubrange(start..<end)
        textView.text = text
    }

    func moveCursor(by graphemes: Int) {
        let offset = TextOffsets.utf16Offset(graphemes: graphemes, before: textBefore, after: textAfter)
        cursor = min(max(cursor + offset, 0), textView.text.utf16.count)
    }
}

/// The preview has no haptics or sound; the keyboard extension has the real ones.
@MainActor private final class SilentFeedback: FeedbackSink {
    func keyDown() {}
    func cursorTick() {}
}
