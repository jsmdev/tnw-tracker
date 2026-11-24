import SafariServices
import TNWTrackerKit
import UIKit

/// The system's in-app browser for a related link (#182 S10 T5d). It is
/// presented by UIKit on top of whatever shows, not through a SwiftUI cover,
/// since its own Done button dismisses it.
@MainActor
enum InAppBrowser {
    static func present(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let browser = SFSafariViewController(url: url)
        browser.dismissButtonStyle = .done
        // A page sheet over the exercise sheet: presented full screen, its Done
        // closed the exercise sheet as well (seen in the UI test); a page sheet does not.
        browser.modalPresentationStyle = .pageSheet
        browser.view.accessibilityIdentifier = AXID.ExerciseSheet.inAppBrowser
        top.present(browser, animated: true)
    }
}
