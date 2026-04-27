import SwiftData
import SwiftUI
import TNWTrackerKit
import WidgetKit

// MARK: - Timeline entry

struct NextSessionEntry: TimelineEntry {
    let date: Date
    let sessionName: String?
}

// MARK: - Timeline provider

struct NextSessionProvider: TimelineProvider {
    func placeholder(in _: Context) -> NextSessionEntry {
        NextSessionEntry(date: Date(), sessionName: "Pecho + Tríceps")
    }

    func getSnapshot(in _: Context, completion: @escaping (NextSessionEntry) -> Void) {
        completion(NextSessionEntry(date: Date(), sessionName: queryNextSession()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<NextSessionEntry>) -> Void) {
        let entry = NextSessionEntry(date: Date(), sessionName: queryNextSession())
        let nextRefresh = Calendar.current
            .date(byAdding: .hour, value: 1, to: Date()) ?? Date(timeIntervalSinceNow: 3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func queryNextSession() -> String? {
        guard
            let container = try? ModelContainerFactory.makeContainer(),
            let context = Optional(ModelContext(container))
        else { return nil }
        return NextSessionQuery(modelContext: context).nextSessionName()
    }
}

// MARK: - Entry view

struct NextSessionWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextSessionEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Próxima sesión")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.sessionName ?? "Sin sesión")
                .font(.headline)
                .lineLimit(2)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "tnwtracker://start-workout"))
    }

    private var mediumView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Label("Próxima sesión", systemImage: "dumbbell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.sessionName ?? "Sin sesión planificada")
                    .font(.title3.bold())
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "tnwtracker://start-workout"))
    }
}

// MARK: - Widget

@main
struct TNWTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextSessionWidget()
        ActiveWorkoutLiveActivity()
    }
}

struct NextSessionWidget: Widget {
    let kind = "NextSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextSessionProvider()) { entry in
            NextSessionWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Próxima Sesión")
        .description("Muestra tu próxima sesión planificada.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
