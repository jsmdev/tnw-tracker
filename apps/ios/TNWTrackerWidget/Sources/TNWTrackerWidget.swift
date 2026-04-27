import SwiftData
import SwiftUI
import WidgetKit

struct NextSessionEntry: TimelineEntry {
    let date: Date
    let sessionName: String?
}

struct NextSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextSessionEntry {
        NextSessionEntry(date: Date(), sessionName: "Pecho + Tríceps")
    }

    func getSnapshot(in context: Context, completion: @escaping (NextSessionEntry) -> Void) {
        completion(NextSessionEntry(date: Date(), sessionName: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextSessionEntry>) -> Void) {
        let entry = NextSessionEntry(date: Date(), sessionName: nil)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

struct NextSessionWidgetView: View {
    let entry: NextSessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Próxima sesión")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.sessionName ?? "Sin sesión planificada")
                .font(.headline)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct TNWTrackerWidget: Widget {
    let kind = "NextSessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextSessionProvider()) { entry in
            NextSessionWidgetView(entry: entry)
        }
        .configurationDisplayName("Próxima Sesión")
        .description("Muestra tu próxima sesión planificada.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
