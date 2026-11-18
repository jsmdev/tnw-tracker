import SwiftUI
import TNWTrackerKit

struct SettingsView: View {
    #if DEBUG
        @Environment(AppEnvironment.self) private var appEnv
        @State private var showReseedConfirmation = false
        @State private var reseedError: String?
    #endif
    @AppStorage(RIRScale.storageKey) private var rirMaximum = RIRScale.defaultMaximum
    @AppStorage(ChangeExerciseRestPreference.enabledKey)
    private var changeExerciseRestEnabled = ChangeExerciseRestPreference.defaultEnabled
    @AppStorage(ChangeExerciseRestPreference.secondsKey)
    private var changeExerciseRestSeconds = ChangeExerciseRestPreference.defaultSeconds

    var body: some View {
        Form {
            Section {
                Toggle("settings.change-exercise-rest-toggle", isOn: $changeExerciseRestEnabled)
                    .accessibilityIdentifier(AXID.Settings.changeExerciseRestToggle)
                RestDurationControl(
                    seconds: $changeExerciseRestSeconds,
                    durationIdentifier: AXID.Settings.changeExerciseRestDurationLabel,
                    decreaseIdentifier: AXID.Settings.changeExerciseRestDecreaseButton,
                    increaseIdentifier: AXID.Settings.changeExerciseRestIncreaseButton
                )
                .disabled(!changeExerciseRestEnabled)
            } header: {
                Text("settings.rest-section")
            } footer: {
                Text("settings.change-exercise-rest-footer")
            }
            Section {
                Stepper(value: $rirMaximum, in: RIRScale.allowedMaximums) {
                    Text("settings.rir-maximum \(rirMaximum)")
                }
                .accessibilityIdentifier(AXID.Settings.rirMaximumStepper)
            } header: {
                Text("settings.effort-section")
            } footer: {
                Text("settings.rir-maximum-footer")
            }
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
                            do {
                                try appEnv.replaceWithSampleData()
                            } catch {
                                reseedError = error.localizedDescription
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will delete all local data and re-insert the invented sample data.")
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

#if DEBUG
#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AppEnvironment.preview())
}
#endif
