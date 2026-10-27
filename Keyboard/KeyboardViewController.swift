import KeyboardCore
import KeyboardUI
import OSLog
import UIKit

/// The keyboard extension's entry point. It hosts a `KeyboardView` over a `KeyboardController` that edits the
/// host app's field through a `ProxyTextDocument`, and passes iOS's events on to them.
///
/// A crash here silently kills the keyboard, so every failure falls back: no layouts shows an empty keyboard,
/// and no App Group means the default settings.
final class KeyboardViewController: UIInputViewController {
    private static let logger = Logger(subsystem: "kittykeys", category: "keyboard")
    /// Speed measurements for Instruments. They cost next to nothing while nothing records them.
    private static let signposter = OSSignposter(subsystem: "kittykeys", category: "perf")
    /// The App Group, resolved once per process: iOS creates a controller each time the keyboard appears, and
    /// when SideStore has renamed the group, resolving it reads the provisioning profile.
    private static let appGroupID = AppGroupResolver.resolve(
        canonical: Bundle.main.object(forInfoDictionaryKey: "KittykeysAppGroup") as? String)
    /// The settings on that group, also made once per process. A resolved id resolves to itself.
    private static let appGroupStore = SettingsStore.appGroup(id: appGroupID)
    /// Which code field kittykeys last handed to the next keyboard, in the extension's own defaults.
    private static let codeFieldHandOff = CodeFieldHandOff(defaults: .standard)

    private let feedback = DeviceFeedback()
    /// The settings shared with the app. nil without the App Group, when the defaults apply.
    private var settingsStore: SettingsStore?
    private var document: ProxyTextDocument?
    private var controller: KeyboardController?
    private var keyboardView: KeyboardView?
    private var heightConstraint: NSLayoutConstraint?
    /// From `viewDidLoad` until the first keys are drawn.
    private var startupInterval: OSSignpostIntervalState?
    /// From `viewDidAppear` to `viewWillDisappear`: the keyboard only switches away while it shows.
    private var isShowing = false

    /// iOS creates a view controller each time the keyboard appears, and keeps the old input view alive after
    /// its controller goes (seen on the iOS 26.4 simulator). Taking the keys out of it frees them, their layers
    /// and the keyboard controller; otherwise memory grows by about 1 MB per appearance.
    isolated deinit {
        keyboardView?.removeFromSuperview()
    }

    /// The input view must enable input clicks for `playInputClick()` to sound.
    override func loadView() {
        inputView = ClickingInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startupInterval = Self.signposter.beginInterval("startup")
        settingsStore = Self.appGroupStore
        if let group = Self.appGroupID, settingsStore != nil {
            Self.logger.notice("App Group: \(group, privacy: .public)")
        } else {
            Self.logger.notice("No App Group; using the default settings")
        }

        let layouts: LayoutSet
        do {
            layouts = try LayoutSet.bundled()
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Couldn't load the layouts, so the keyboard stays empty: \(reason, privacy: .public)")
            return
        }

        let signposter = Self.signposter
        let document = ProxyTextDocument(host: self, signposter: signposter)
        let controller = KeyboardController(
            document: document, layouts: layouts, settings: settingsStore?.load() ?? KeyboardSettings(),
            feedback: feedback)
        controller.onGlobe = { [weak self] in self?.advanceToNextInputMode() }
        // Recent and the skin tones live in the extension's own defaults, which need no Full Access.
        let keyboardView = KeyboardView(
            controller: controller, feedback: feedback, emojiPreferences: EmojiPreferences(defaults: .standard))
        // How long iOS took to deliver the touch: the bottom-row delay shows up here, so the bottom row is marked
        // (only a 0 or 1, never where the touch was or which key).
        keyboardView.onTouchDown = { timestamp, isBottomRow in
            let latency = (ProcessInfo.processInfo.systemUptime - timestamp) * 1000
            let bottomRow = isBottomRow ? 1 : 0
            signposter.emitEvent(
                "keyDown", "latencyMs=\(latency, format: .fixed(precision: 2)) bottomRow=\(bottomRow)")
        }
        // "touch": each batch of touches through the touch processor and the controller; "render": each redraw;
        // "emojiInsert": each emoji the panel or search's results type.
        keyboardView.measure = { name, work in
            signposter.withIntervalSignpost(name, around: work)
        }
        // "emojiPanelOpen": the emoji panel opening, to its first frame committed with the emoji drawn.
        // "emojiSearchOpen": a touch on the search field, to search's first frame committed with its keys and results.
        // "emojiSearchQuery": a change to the search query, to the later frame committed with its results drawn.
        // "emojiSearchDraw": drawing results' first-seen emoji off the main thread, before they show.
        keyboardView.startMeasure = { name in
            let state = signposter.beginInterval(name)
            return { signposter.endInterval(name, state) }
        }
        keyboardView.onFirstKeysDrawn = { [weak self] in self?.endStartupInterval() }
        // The view redraws from onChange; the height follows the page too.
        let redraw = controller.onChange
        controller.onChange = { [weak self] in
            redraw?()
            self?.updateHeight()
        }

        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        // Just below required, so it yields to the system's own height constraint while the keyboard animates in
        // instead of logging conflicts.
        let height = view.heightAnchor.constraint(equalToConstant: CGFloat(controller.height))
        height.priority = .required - 1
        NSLayoutConstraint.activate([
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (viewController: KeyboardViewController, _: UITraitCollection) in
            viewController.updateTheme()
        }

        self.document = document
        self.controller = controller
        self.keyboardView = keyboardView
        heightConstraint = height
    }

    /// Picks up settings changed in the app and text replacements changed in iOS Settings, records that the keyboard
    /// opened, and starts afresh for the field.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let controller, let document else { return }
        if let settingsStore {
            controller.settings = settingsStore.load()
            settingsStore.lastKeyboardOpen = Date()
        }
        feedback.configure(settings: controller.settings, hasFullAccess: hasFullAccess)
        controller.keyboardWillAppear(document.traits)
        updateTheme()
        loadTextReplacements()
    }

    /// Design §9's bottom-row workaround: the window's system gesture recognizers can hold back touches near the
    /// screen's bottom edge. The device check measures whether this helps.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let recognizers = view.window?.gestureRecognizers ?? []
        for recognizer in recognizers { recognizer.delaysTouchesBegan = false }
        Self.logger.notice(
            "Turned off delaysTouchesBegan on \(recognizers.count, privacy: .public) window gesture recognizers")
        isShowing = true
        handOffIfCodeField()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isShowing = false
    }

    /// `needsInputModeSwitchKey` is reliable only once the view is being laid out.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let controller, controller.needsGlobeKey != needsInputModeSwitchKey else { return }
        controller.needsGlobeKey = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        guard let controller, let document else { return }
        controller.fieldDidChange(document.traits)
        controller.documentDidChange()
        updateTheme()
        // Focus can move to a code field while the keyboard stays up.
        if isShowing { handOffIfCodeField() }
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        controller?.documentDidChange()
    }

    /// Frees what the emoji panel and search keep while they are closed: search's keywords and results unless search
    /// shows, and the panel and its decoded emoji while the keys show. The layouts and the key layers are in use.
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        Self.logger.notice("Memory warning")
        keyboardView?.didReceiveMemoryWarning()
    }

    /// Reads the user's text replacements from iOS. They arrive a moment later; until then the last ones read apply.
    /// Only their number is logged, never a shortcut or a phrase.
    /// iOS calls back on its own queue, and Swift traps a main-actor closure run there (seen on the simulator), so the
    /// closure is `@Sendable` and hops to the main actor; the SDK marks `UILexicon` as main-actor only.
    private func loadTextReplacements() {
        requestSupplementaryLexicon { @Sendable [weak self] lexicon in
            Task { @MainActor in
                guard let controller = self?.controller else { return }
                let pairs = lexicon.entries.map { (shortcut: $0.userInput, phrase: $0.documentText) }
                controller.textReplacements = TextReplacements(pairs: pairs)
                Self.logger.notice("Text replacements: \(pairs.count, privacy: .public) lexicon entries")
            }
        }
    }

    /// Dark for a field that asks for a dark keyboard, and in dark mode.
    private func updateTheme() {
        let isDark = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        keyboardView?.theme = isDark ? .dark : .light
    }

    /// A one-time code field goes to the next keyboard, where Apple's keyboard can offer the code from Messages,
    /// unless `CodeFieldHandOff` says kittykeys stays. Stays are logged at info level, not notice: every keystroke in
    /// a code field asks again.
    private func handOffIfCodeField() {
        guard let controller, controller.settings.handOffCodeFields,
              textDocumentProxy.textContentType == .oneTimeCode
        else { return }
        let decision = Self.codeFieldHandOff.decide(document: documentIdentifier, now: Date())
        guard decision == .handOff else {
            Self.logger.info("Staying in a one-time code field: \(String(describing: decision), privacy: .public)")
            return
        }
        Self.logger.notice("Handing a one-time code field to the next keyboard")
        // This controller is on its way out; it doesn't switch again.
        isShowing = false
        advanceToNextInputMode()
    }

    /// The field's `documentIdentifier`, or nil. While focus moves between fields iOS reports none, though the SDK
    /// declares it non-null, and reading it as a Swift `UUID` then traps; asking the proxy as an object doesn't.
    private var documentIdentifier: UUID? {
        let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
        guard let proxy = textDocumentProxy as? NSObject, proxy.responds(to: getter) else { return nil }
        return (proxy.perform(getter)?.takeUnretainedValue() as? NSUUID) as UUID?
    }

    private func updateHeight() {
        guard let controller, let heightConstraint else { return }
        let height = CGFloat(controller.height)
        if heightConstraint.constant != height { heightConstraint.constant = height }
    }

    private func endStartupInterval() {
        guard let startupInterval else { return }
        Self.signposter.endInterval("startup", startupInterval)
        self.startupInterval = nil
    }
}
