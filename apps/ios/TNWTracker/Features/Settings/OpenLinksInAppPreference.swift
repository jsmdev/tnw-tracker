import Foundation

/// «Abrir enlaces en la app» (#182 S10 T5d): a device preference, not synced
/// and not part of the training data format. While on, related links to sites
/// other than YouTube open in the in-app browser; off, outside the app.
struct OpenLinksInAppPreference {
    static let enabledKey = "settings.openLinksInApp"
    static let defaultEnabled = true

    let defaults: UserDefaults

    /// On unless the user turned it off. A missing key means the default.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled
    }
}
