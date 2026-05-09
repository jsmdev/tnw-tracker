import SwiftUI

// MARK: - Typography

/// Semantic font extensions — Dynamic Type compliant by default.
/// Apple's built-in text styles (.title, .body, etc.) scale automatically.
/// Only timerLarge uses a custom size (timer display) — intentional, documented.
extension Font {
    /// Large monospaced timer display (rest timer, active workout countdown).
    /// Uses .system(size: 64) intentionally — the only allowed custom size in Typography.
    /// Clients that need Dynamic Type scaling should use @ScaledMetric privately.
    static let timerLarge: Font = .system(size: 64, weight: .bold, design: .rounded)
        .monospacedDigit()
}
