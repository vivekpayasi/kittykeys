import KeyboardCore
import UIKit

/// Haptics and the key click. iOS gives a keyboard extension haptics only with Full Access, so without it
/// the keys stay silent to the touch whatever the setting says.
@MainActor final class DeviceFeedback: FeedbackSink {
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()
    private var hapticsEnabled = false
    private var soundEnabled = false

    /// Takes the user's settings and whether Full Access is on. The keyboard calls it each time it appears.
    func configure(settings: KeyboardSettings, hasFullAccess: Bool) {
        hapticsEnabled = settings.haptics && hasFullAccess
        soundEnabled = settings.sound
        if hapticsEnabled {
            impact.prepare()
            selection.prepare()
        }
    }

    func keyDown() {
        if hapticsEnabled {
            impact.impactOccurred()
            // Prepared again for the next key, so its tap isn't late.
            impact.prepare()
        }
        // Plays only while an input view that enables input clicks is on screen (`ClickingInputView`),
        // and only if the iPhone's keyboard clicks are on.
        if soundEnabled { UIDevice.current.playInputClick() }
    }

    func cursorTick() {
        guard hapticsEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }
}

/// The keyboard extension's input view. It enables input clicks, without which `playInputClick()` stays silent.
final class ClickingInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
