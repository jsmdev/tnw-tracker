import SwiftUI
import TNWTrackerKit

// The history of one exercise (fast-add-exercise S6): in its sheet, and from
// «La última vez» in the workout.

// MARK: - ExerciseHistorySection

/// «Historial» in the exercise sheet: the best set, the last sessions with their
/// sets and «Ver todo» for the rest.
struct ExerciseHistorySection: View {
    let items: [ExerciseHistoryItem]

    /// Sessions shown before «Ver todo».
    static let shownCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("exercise-history.title")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text("exercise-history.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AXID.ExerciseHistory.empty)
            } else {
                if let best = ExerciseHistoryItem.best(in: items) {
                    Text("exercise-history.best \(LastPerformanceView.describe(best))")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier(AXID.ExerciseHistory.best)
                }
                VStack(spacing: Spacing.sm) {
                    ForEach(items.prefix(Self.shownCount)) { item in
                        ExerciseHistoryRow(item: item)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                    }
                }
                if items.count > Self.shownCount {
                    NavigationLink {
                        ExerciseHistoryList(items: items)
                    } label: {
                        Text("exercise-history.see-all \(items.count)")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityIdentifier(AXID.ExerciseHistory.seeAllButton)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.ExerciseHistory.section)
    }
}

// MARK: - ExerciseHistoryRow

/// One session: its date (with the year) and name, then its sets.
struct ExerciseHistoryRow: View {
    let item: ExerciseHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.completedAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.subheadline.weight(.semibold))
                if let name = item.sessionName {
                    Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(verbatim: item.sets.map(LastPerformanceView.describe).joined(separator: " · "))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.ExerciseHistory.row(item.sessionId))
    }
}

// MARK: - ExerciseHistoryList

/// Every session of the exercise, most recent first.
struct ExerciseHistoryList: View {
    let items: [ExerciseHistoryItem]

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyState(systemImage: "clock", title: "exercise-history.title", message: "exercise-history.empty")
            } else {
                List {
                    if let best = ExerciseHistoryItem.best(in: items) {
                        Text("exercise-history.best \(LastPerformanceView.describe(best))")
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(items) { item in
                        ExerciseHistoryRow(item: item)
                    }
                }
                .accessibilityIdentifier(AXID.ExerciseHistory.list)
            }
        }
        .navigationTitle(Text("exercise-history.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ExerciseHistorySheet

/// The history of the current exercise, opened from the workout.
struct ExerciseHistorySheet: View {
    let exerciseName: String
    let items: [ExerciseHistoryItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseHistoryList(items: items)
                .navigationTitle(Text(verbatim: exerciseName))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .close) { dismiss() }
                            .accessibilityIdentifier(AXID.ExerciseHistory.closeButton)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
