import SwiftUI
import TNWTrackerKit

// MARK: - HistoryListView

/// The Historial tab: finished workouts, newest first (#174 S6).
struct HistoryListView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var model: HistoryListModel

    init(sessionRepository: any SessionRepositoryProtocol) {
        _model = State(initialValue: HistoryListModel(sessions: sessionRepository))
    }

    var body: some View {
        Group {
            if model.isLoading && model.sessions.isEmpty {
                LoadingState(message: "history.loading")
            } else if model.sessions.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "history.empty-title",
                    message: "history.empty-message"
                )
            } else {
                List(model.sessions) { session in
                    HistoryRow(session: session)
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier(AXID.History.list)
            }
        }
        .navigationTitle(Text("history.title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await model.load() }
        .refreshable { await model.load() }
        // A workout just ended: it joins the list.
        .onChange(of: appEnv.router.presentedActiveWorkout == nil) { _, closed in
            if closed { Task { await model.load() } }
        }
    }
}

// MARK: - HistoryRow

/// One finished workout: name, day, duration, exercises and volume.
private struct HistoryRow: View {
    let session: TrainingSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Group {
                if let name = session.name {
                    Text(verbatim: name)
                } else {
                    Text("free-session.name")
                }
            }
            .font(.headline)

            if let completedAt = session.completedAt {
                Text(completedAt, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.sm) {
                if let seconds = session.durationSeconds {
                    Label {
                        Text(
                            Duration.seconds(seconds),
                            format: .units(allowed: [.hours, .minutes], width: .abbreviated)
                        )
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
                Label {
                    Text("history.row.exercises \(HistoryListModel.exerciseCount(session))")
                } icon: {
                    Image(systemName: "dumbbell")
                }
                if session.volumeKg > 0 {
                    Label {
                        Text("history.row.volume \(session.volumeKg.formatted(.number.precision(.fractionLength(0))))")
                    } icon: {
                        Image(systemName: "scalemass")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.History.row(session.id))
    }
}
