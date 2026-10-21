import UIKit

final class KeyboardViewController: UIInputViewController {
    private static let keyboardHeight: CGFloat = 292

    override func viewDidLoad() {
        super.viewDidLoad()
        // Just below required, so it yields to the system's own height
        // constraint while the keyboard animates in instead of logging conflicts.
        let height = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
        height.priority = .required - 1
        height.isActive = true
    }
}
