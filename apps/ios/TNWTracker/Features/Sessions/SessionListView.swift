import SwiftUI
import TNWTrackerKit

// MARK: - SessionListView

/// Displays a paginated, filterable, searchable list of routines.
/// REQ-SESSLIST-01, REQ-SESSLIST-02, REQ-SESSLIST-03, REQ-SESSLIST-04, REQ-SESSLIST-05.
struct SessionListView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var model: SessionListModel

    init(routineRepository: any RoutineRepositoryProtocol) {
        _model = State(initialValue: SessionListModel(routines: routineRepository))
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

    private func sessionRow(_ session: Routine) -> some View {
        Button {
            appEnv.router.push(.sessionDetail(sessionID: session.id))
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: session.name)
                        .font(.headline)

                    Text("session-list.row.exercises-count \(session.items.count)")
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

#if DEBUG
#Preview("SessionListView — with data") {
    let appEnv = AppEnvironment.preview()
    NavigationStack {
        SessionListView(routineRepository: appEnv.routineRepository)
    }
    .environment(appEnv)
}

#Preview("SessionListView — empty") {
    let appEnv = AppEnvironment.preview(withSampleData: false)
    NavigationStack {
        SessionListView(routineRepository: appEnv.routineRepository)
    }
    .environment(appEnv)
}
#endif
