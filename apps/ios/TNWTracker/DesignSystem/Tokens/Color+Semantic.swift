import SwiftUI

// MARK: - Semantic Colors

extension Color {
    // Surface: card and sheet backgrounds — uses system material via .regularMaterial in views.
    // Fallback for contexts that need a Color value (e.g., overlay tints).
    static let surface = Color(.secondarySystemGroupedBackground)
    static let surfacePrimary = Color(.systemGroupedBackground)
}
