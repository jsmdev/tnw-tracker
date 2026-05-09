import SwiftData
import SwiftUI
import TNWTrackerKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context

    #if DEBUG
        @State private var showReseedConfirmation = false
        @State private var reseedError: String?
    #endif

    var body: some View {
        Form {
            #if DEBUG
                Section("Developer") {
                    Button("Reset & seed", role: .destructive) {
                        showReseedConfirmation = true
                    }
                    .confirmationDialog(
                        "Reset & seed",
                        isPresented: $showReseedConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Reset & seed", role: .destructive) {
                            let container = context.container
                            Task {
                                do {
                                    try await SeedService(container: container).reseed()
                                } catch {
                                    reseedError = error.localizedDescription
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all local data and re-insert canonical seed data.")
                    }

                    if let err = reseedError {
                        Text(verbatim: err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            #endif
        }
        .navigationTitle(Text("settings.title"))
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(try! ModelContainerFactory.makeContainer(inMemory: true))
}
