import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseSheetView

/// The exercise sheet (#137 S7): the video, else the image, else a neutral
/// placeholder; then the name, type and equipment, how to do it (setup and
/// execution steps) and the muscles it works. Exercise text shows as stored.
struct ExerciseSheetView: View {
    let content: ExerciseSheetContent
    @State private var hero: ExerciseHeroModel
    @Environment(\.dismiss) private var dismiss

    init(content: ExerciseSheetContent, library: ExerciseMediaLibrary) {
        self.content = content
        _hero = State(initialValue: ExerciseHeroModel(content: content, library: library))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ExerciseHeroView(model: hero, exerciseName: content.name)
                    header
                    howTo
                    muscles
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .background(Color.surfacePrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier(AXID.ExerciseSheet.closeButton)
                }
            }
        }
        .task {
            await hero.load()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(content.type.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(verbatim: content.name)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AXID.ExerciseSheet.name)
            if let equipment = content.equipment {
                Text(equipment.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AXID.ExerciseSheet.equipment)
            }
        }
    }

    // MARK: - How to

    private var howTo: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionTitle("exercise-sheet.how-to")
            if content.hasNoSteps {
                Text("exercise-sheet.no-steps")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        steps("exercise-sheet.setup", content.setupSteps, id: AXID.ExerciseSheet.setupStep)
                        steps("exercise-sheet.execution", content.executionSteps, id: AXID.ExerciseSheet.executionStep)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func steps(_ title: LocalizedStringKey, _ steps: [String], id: @escaping (Int) -> String) -> some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(index + 1, format: .number)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(verbatim: step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(id(index + 1))
                }
            }
        }
    }

    // MARK: - Muscles

    @ViewBuilder
    private var muscles: some View {
        if !content.primaryMuscles.isEmpty || !content.secondaryMuscles.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                sectionTitle("exercise-sheet.muscles")
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        muscleRow("exercise-sheet.muscles.primary", content.primaryMuscles)
                            .accessibilityIdentifier(AXID.ExerciseSheet.primaryMuscles)
                        muscleRow("exercise-sheet.muscles.secondary", content.secondaryMuscles)
                            .accessibilityIdentifier(AXID.ExerciseSheet.secondaryMuscles)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func muscleRow(_ title: LocalizedStringKey, _ muscles: [Muscle]) -> some View {
        if !muscles.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: muscles.map { String(localized: $0.label) }.formatted(.list(type: .and)))
                    .font(.body)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("ExerciseSheetView — steps, no media") {
        if let squat = SampleTrainingData.exercises.first {
            ExerciseSheetView(content: ExerciseSheetContent(squat), library: .offlineForTesting())
        }
    }

    #Preview("ExerciseSheetView — invented image") {
        if let press = SampleTrainingData.exercises.first(where: { $0.media != nil }) {
            ExerciseSheetView(content: ExerciseSheetContent(press), library: .sampleForUITesting())
        }
    }
#endif
