import SwiftUI
import TNWTrackerKit

// MARK: - HistoryListView

/// The Historial tab: finished workouts, newest first (#174 S6), with a search by
/// exercise, filters by kind, period and source, and one section per month (#174 S8).
struct HistoryListView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var model: HistoryListModel
    @State private var sessionToDelete: TrainingSession?
    @State private var deleteFailed = false

    init(sessionRepository: any SessionRepositoryProtocol, exerciseRepository: any ExerciseRepositoryProtocol) {
        _model = State(initialValue: HistoryListModel(sessions: sessionRepository, exercises: exerciseRepository))
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
                list
            }
        }
        .navigationTitle(Text("history.title"))
        .navigationBarTitleDisplayMode(.large)
        .deleteWorkoutAlert(isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            guard let session = sessionToDelete else { return }
            sessionToDelete = nil
            do {
                try model.delete(session.id)
            } catch {
                deleteFailed = true
            }
        }
        .deleteWorkoutFailedAlert(isPresented: $deleteFailed)
        .task { await model.load() }
        .refreshable { await model.load() }
        // A workout just ended: it joins the list.
        .onChange(of: appEnv.router.presentedActiveWorkout == nil) { _, closed in
            if closed { Task { await model.load() } }
        }
    }

    private var list: some View {
        let months = model.months
        return List {
            Section {
                filters
            } header: {
                summary
            }
            if months.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("history.no-results")
                            .accessibilityIdentifier(AXID.History.noResults)
                        clearFiltersButton
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
            ForEach(months) { month in
                Section {
                    // A row, not a section header: the system header fails the Dynamic Type audit.
                    Text(verbatim: Self.monthTitle(month.id, calendar: model.calendar))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AXID.History.month)
                    ForEach(month.sessions) { session in
                        row(session)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $model.filter.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("history.search-prompt")
        )
        .accessibilityIdentifier(AXID.History.list)
    }

    @ViewBuilder
    private var summary: some View {
        if let first = model.firstWorkoutDate {
            Text("history.summary \(model.sessions.count) \(Self.sinceText(first, calendar: model.calendar))")
                .textCase(nil)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ChipRow(label: "history.filter.kind", options: model.kinds, selection: $model.filter.kind) { kind in
                switch kind {
                case .all: Text("history.filter.kind.all")
                case let .named(name): Text(verbatim: name)
                case .free: Text("free-session.name")
                }
            } identifier: { kind in
                switch kind {
                case .all: AXID.History.kindChip("all")
                case let .named(name): AXID.History.kindChip(name)
                case .free: AXID.History.kindChip("free")
                }
            }
            ChipRow(
                label: "history.filter.period",
                options: [.month, .quarter, .year, .all],
                selection: $model.filter.period
            ) { period in
                switch period {
                case .month: Text("history.filter.period.month")
                case .quarter: Text("history.filter.period.quarter")
                case .year: Text("history.filter.period.year")
                case .all: Text("history.filter.period.all")
                }
            } identifier: { AXID.History.periodChip("\($0)") }
            ChipRow(
                label: "history.filter.source",
                options: HistoryFilter.Source.allCases,
                selection: $model.filter.source
            ) { source in
                switch source {
                case .all: Text("history.filter.source.all")
                case .machines: Text("history.filter.source.machines")
                case .manual: Text("history.filter.source.manual")
                }
            } identifier: { AXID.History.sourceChip("\($0)") }
            HStack {
                Text("history.count \(model.filteredSessions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AXID.History.count)
                Spacer()
                if model.filter.isActive {
                    clearFiltersButton
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var clearFiltersButton: some View {
        Button {
            model.clearFilters()
        } label: {
            Text("history.filter.clear")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(AXID.History.clearFilters)
    }

    private func row(_ session: TrainingSession) -> some View {
        NavigationLink(value: Route.workoutDetail(sessionID: session.id)) {
            HistoryRow(session: session)
        }
        .swipeActions(edge: .trailing) {
            if HistoryListModel.canDelete(session) {
                Button(role: .destructive) {
                    sessionToDelete = session
                } label: {
                    Label("history.delete.button", systemImage: "trash")
                }
                .accessibilityIdentifier(AXID.History.deleteAction)
            }
        }
    }

    /// "Noviembre de 2026".
    static func monthTitle(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let text = date.formatted(style)
        return text.prefix(1).localizedUppercase + text.dropFirst()
    }

    /// "junio", or "junio de 2025" before the current year.
    static func sinceText(_ date: Date, calendar: Calendar, now: Date = Date()) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

// MARK: - ChipRow

/// Selectable chips that wrap onto more lines: one choice of a filter.
private struct ChipRow<Option: Hashable>: View {
    let label: LocalizedStringKey
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> Text
    let identifier: (Option) -> String

    init(
        label: LocalizedStringKey,
        options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> Text,
        identifier: @escaping (Option) -> String
    ) {
        self.label = label
        self.options = options
        _selection = selection
        self.title = title
        self.identifier = identifier
    }

    var body: some View {
        WrappingLayout(spacing: Spacing.sm) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    Button {
                        selection = option
                    } label: {
                        title(option)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            // Selected: the label colour as fill, the most contrast in both themes.
                            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                            .background(
                                Capsule().fill(isSelected ? Color.primary : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier(identifier(option))
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - HistoryRow

/// One finished workout: name, day, duration, exercises and volume.
private struct HistoryRow: View {
    let session: TrainingSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side, or one under another at the accessibility text sizes,
    /// where side by side squeezes each value into a column of letters.
    private var statsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
    }

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

            statsLayout {
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
            // Wraps instead of truncating at the accessibility sizes.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AXID.History.row(session.id))
    }
}

// MARK: - WrappingLayout

/// Lays its views out left to right, starting a new line when one does not fit.
private struct WrappingLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
