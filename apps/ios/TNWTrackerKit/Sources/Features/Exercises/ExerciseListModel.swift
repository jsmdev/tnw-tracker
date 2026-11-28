import Foundation
import Observation

/// The exercises screen (#137 S7, T2b): every exercise of the account's local
/// store, its own and the catalogue's, sorted by name; each opens its sheet
/// (`Router.presentExercise`).
/// It reads only the local store, which the sync fills, so it works offline.
@Observable
@MainActor
public final class ExerciseListModel {
    public private(set) var exercises: [Exercise] = []
    /// True when the store could not be read.
    public private(set) var loadFailed = false
    /// The search field's text (fast-add-exercise S8).
    public var query = ""

    /// The exercises whose name contains the search, ignoring case, accents
    /// and spaces around it; all of them while the search is empty.
    public var visibleExercises: [Exercise] {
        let search = Self.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !search.isEmpty else { return exercises }
        return exercises.filter { Self.folded($0.name).contains(search) }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private let repository: any ExerciseRepositoryProtocol

    public init(exercises: any ExerciseRepositoryProtocol) {
        repository = exercises
    }

    public func load() {
        do {
            exercises = try repository.exercises().sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
