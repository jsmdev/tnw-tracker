import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - SessionListView

/// Displays a paginated, filterable, searchable list of session templates.
/// REQ-SESSLIST-01, REQ-SESSLIST-02, REQ-SESSLIST-03, REQ-SESSLIST-04, REQ-SESSLIST-05.
struct SessionListView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext
    @State private var model: SessionListModel

    init(container: ModelContainer) {
        _model = State(initialValue: SessionListModel(container: container))
    }

    var body: some View {
        Group {
            if model.isLoading && model.sessions.isEmpty {
                LoadingState(message: "session-list.loading")
            } else if model.sessions.isEmpty {
                EmptyState(
                    systemImage: "calendar.badge.exclamationmark",
                    title: "session-list.empty-title",
                    message: "session-list.empty-message"
                )
            } else {
                sessionList
            }
        }
        .navigationTitle(Text("session-list.title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.searchQuery, prompt: Text("session-list.search-placeholder"))
        .task(id: model.searchQuery) {
            await model.loadFirstPage()
        }
        .toolbar {
            filterMenu
        }
    }

    // MARK: - List

    private var sessionList: some View {
        List {
            ForEach(model.sessions) { session in
                sessionRow(session)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if model.hasNextPage {
                loadMoreRow
            }
        }
        .listStyle(.plain)
    }

    private func sessionRow(_ session: Session) -> some View {
        Button {
            appEnv.router.push(.sessionDetail(sessionID: session.id))
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: session.name)
                        .font(.headline)

                    Text("session-list.row.exercises-count \(session.sessionExercises.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, Spacing.sm)
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .task {
            await model.loadMore()
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                ForEach(SessionListModel.Filter.allCases, id: \.self) { filterCase in
                    Button {
                        model.filter = filterCase
                    } label: {
                        HStack {
                            Text(filterLabel(filterCase))
                            if model.filter == filterCase {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("a11y.filter-button")
        }
    }

    private func filterLabel(_ filter: SessionListModel.Filter) -> LocalizedStringKey {
        switch filter {
        case .all: "session-list.filter.all"
        case .withWorkouts: "session-list.filter.with-workouts"
        }
    }
}

// MARK: - Preview

#Preview("SessionListView — with data") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let userId = UUID()
    let push = Session(userId: userId, name: "Push Day")
    let pull = Session(userId: userId, name: "Pull Day")
    context.insert(push)
    context.insert(pull)
    let se = SessionExercise(sessionId: push.id, exerciseId: UUID(), orderIndex: 0)
    context.insert(se)
    push.sessionExercises = [se]
    try! context.save()

    return NavigationStack {
        SessionListView(container: container)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}

#Preview("SessionListView — empty") {
    let container = try! ModelContainerFactory.makeContainer(inMemory: true)
    return NavigationStack {
        SessionListView(container: container)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}
