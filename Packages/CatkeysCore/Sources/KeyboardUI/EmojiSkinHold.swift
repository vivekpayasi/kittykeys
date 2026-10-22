// UIKit only, so that `swift test` still builds the package on macOS.
#if canImport(UIKit)
import KeyboardCore
import UIKit

/// Holding an emoji that has skin tones, in the emoji panel's list or in search's results. After the long-press delay a
/// `SkinTonePopup` shows its base and skins above it, inside the keyboard view, opening on the variant the cell shows
/// and placing it under the finger (ruling M3-R10), so a hold lifted without sliding keeps that tone. Sliding picks
/// another, and the lift picks the one highlighted.
///
/// Its long-press recognizer goes on the list. A hold on an emoji without skin tones never begins, so its lift types it
/// as a tap does, and while a hold is recognised the list can't scroll.
@MainActor final class EmojiSkinHold: NSObject, UIGestureRecognizerDelegate {
    /// What a hold landed on: the emoji's catalog item, the variant its cell shows, and the cell's frame in the host's
    /// coordinates.
    struct Target {
        var item: EmojiItem
        var shown: String
        var cell: CGRect
    }

    /// The popup's widest cell.
    private static let preferredCellWidth = 40.0

    /// The emoji under a point in the host's coordinates. nil where there is none, and while nothing may be typed.
    var target: ((CGPoint) -> Target?)?
    /// The lift picked `variant`, one of `item`'s base and skins. The host types it if it still may.
    var onPick: ((_ variant: String, _ item: EmojiItem) -> Void)?
    /// The popup showed, for a haptic.
    var onShow: (() -> Void)?
    var theme = KeyboardTheme.light

    /// The hold's delay, which the host takes from the settings' long-press delay.
    var delay: TimeInterval {
        get { recognizer.minimumPressDuration }
        set { recognizer.minimumPressDuration = newValue }
    }

    private let recognizer = UILongPressGestureRecognizer()
    private let popup = SkinTonePopup()
    /// The view the popup is placed in. Its superview is the keyboard view, which the popup stays inside.
    private weak var host: UIView?
    /// The emoji held with its popup showing, its options (the base, then its skins) and what the finger has picked.
    private var holding: (item: EmojiItem, options: [String], pick: SkinTonePick)?

    /// Puts the recognizer on `list` and the popup on top of `host`'s subviews. `host` must not clip its subviews:
    /// the popup reaches up past its top.
    func attach(to host: UIView, list: UIView) {
        self.host = host
        recognizer.addTarget(self, action: #selector(changed(_:)))
        recognizer.delegate = self
        list.addGestureRecognizer(recognizer)
        host.addSubview(popup)
    }

    /// Ends a hold: the popup hides, and its lift types nothing.
    func cancel() {
        // Disabling a recognizer cancels it.
        recognizer.isEnabled = false
        recognizer.isEnabled = true
        holding = nil
        popup.hide()
    }

    /// For the app's preview: shows the popup for `target` as if a finger held it at `fingerX`.
    func showForPreview(_ target: Target, fingerX: Double) {
        showPopup(for: target, fingerX: fingerX)
    }

    // MARK: The gesture

    /// Only an emoji with skin tones can be held.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let host, let target = target?(gestureRecognizer.location(in: host)) else { return false }
        return !target.item.skins.isEmpty
    }

    @objc private func changed(_ recognizer: UILongPressGestureRecognizer) {
        guard let host else { return }
        let location = recognizer.location(in: host)
        let x = Double(location.x)
        switch recognizer.state {
        case .began:
            guard let target = target?(location), !target.item.skins.isEmpty else { return }
            showPopup(for: target, fingerX: x)
            if holding != nil { onShow?() }
        case .changed:
            guard var holding else { return }
            holding.pick.move(toX: x)
            self.holding = holding
            popup.select(holding.pick.selected)
        case .ended:
            guard var holding else { return }
            self.holding = nil
            popup.hide()
            holding.pick.move(toX: x)
            let option = holding.pick.selected
            guard holding.options.indices.contains(option) else { return }
            onPick?(holding.options[option], holding.item)
        default:
            holding = nil
            popup.hide()
        }
    }

    /// Shows the target's base and skins above its cell, inside the keyboard view, with the variant the cell shows under
    /// `fingerX` and highlighted.
    private func showPopup(for target: Target, fingerX: Double) {
        guard let host else { return }
        let options = [target.item.base] + target.item.skins
        let keyboard = host.superview.map { host.convert($0.bounds, from: $0) } ?? host.bounds
        let minX = Double(keyboard.minX + SkinTonePopup.padding), maxX = Double(keyboard.maxX - SkinTonePopup.padding)
        let cellWidth = SkinTonePopupLayout.cellWidth(
            count: options.count, available: maxX - minX, preferred: Self.preferredCellWidth)
        let layout = SkinTonePopupLayout(
            count: options.count, anchor: options.firstIndex(of: target.shown) ?? 0, cellWidth: cellWidth,
            fingerX: fingerX, minX: minX, maxX: maxX)
        popup.show(options, layout: layout, above: target.cell, minY: keyboard.minY, theme: theme)
        guard !popup.isHidden else { return }
        let pick = SkinTonePick(layout: layout, fingerX: fingerX)
        popup.select(pick.selected)
        holding = (target.item, options, pick)
    }
}
#endif
