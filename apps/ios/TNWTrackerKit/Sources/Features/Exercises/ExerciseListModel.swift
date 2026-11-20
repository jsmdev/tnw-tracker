import Foundation
import Observation

/// The exercises screen (#137 S7, T2b): every exercise of the account's local
/// store, its own and the catalogue's, sorted by name; each opens its sheet.
/// It reads only the local store, which the sync fills, so it works offline.
@Observable
@MainActor
public final class ExerciseListModel {
    public private(set) var exercises: [Exercise] = []
    /// True when the store could not be read.
    public private(set) var loadFailed = false
    /// The exercise whose sheet shows; nil when none does.
    public var selected: ExerciseSheetContent?

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

    /// Shows the sheet of the exercise with `id`, when the list has it.
    public func open(_ id: UUID) {
        guard let exercise = exercises.first(where: { $0.id == id }) else { return }
        selected = ExerciseSheetContent(exercise)
    }
}
