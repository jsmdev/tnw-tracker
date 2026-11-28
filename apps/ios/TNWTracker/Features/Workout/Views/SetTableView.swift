import SwiftUI
import TNWTrackerKit

// MARK: - SetTableView

/// The set table of the current exercise (fast-add-exercise S5), like a paper
/// log: the sets done today, then the rows still to do, ready with last time's
/// reps and kg. A check logs a row; «Añadir serie» adds one. The row's number
/// opens the full set sheet, for effort (RIR) and warm-up.
struct SetTableView: View {
    let coordinator: ActiveWorkoutCoordinator
    let entry: SessionEntry
    /// Opens the full set sheet for pending row `index`, with its values.
    let onDetails: (_ index: Int, _ number: Int, _ values: SetValues) -> Void

    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At accessibility text sizes the columns do not fit: each row stacks its
    /// cells, each value under its own label, and the column header goes.
    private var stacked: Bool {
        typeSize.isAccessibilitySize
    }

    private var rowLayout: AnyLayout {
        stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.sm))
    }

    private enum Field: Hashable {
        case reps(Int), weight(Int)
    }

    private var done: [ExerciseSet] {
        entry.manualSets
    }

    private var pending: [SetValues] {
        coordinator.pendingSets(for: entry)
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            VStack(spacing: Spacing.sm) {
                if !stacked {
                    header
                }
                ForEach(done) { set in
                    doneRow(set)
                }
                ForEach(Array(pending.enumerated()), id: \.offset) { index, values in
                    pendingRow(index: index, values: values)
                }
            }
            .animation(reduceMotion ? nil : .smooth, value: done.count)

            Button {
                coordinator.addPendingSet(to: entry)
            } label: {
                Label("set-table.add-set", systemImage: "plus.circle")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: numberWidth)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(AXID.ActiveWorkout.addSetButton)
        }
        .padding(.horizontal, Spacing.md)
        // A prefilled value is selected when its field gets focus, so typing
        // replaces it instead of adding to it (fast-add-exercise S3).
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            // Only the table's own number fields: not, say, the picker's search field.
            guard let field = note.object as? UITextField, !(field is UISearchTextField),
                  field.keyboardType == .numberPad || field.keyboardType == .decimalPad else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("set-table.keyboard-done") { focused = nil }
                    .accessibilityIdentifier(AXID.ActiveWorkout.keyboardDoneButton)
            }
        }
    }

    // MARK: - Rows

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Text("set-table.header.set")
                .frame(width: numberWidth)
            Text("set-table.header.reps")
                .frame(maxWidth: .infinity)
            Text("set-table.header.kg")
                .frame(maxWidth: .infinity)
            Text("set-table.header.done")
                .frame(width: numberWidth)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(AXID.ActiveWorkout.setTableHeader)
    }

    /// Working sets are numbered; warm-ups show "C" and are not counted.
    private func number(of set: ExerciseSet) -> Int {
        done.filter { !$0.warmup && $0.order <= set.order }.count
    }

    private func doneRow(_ set: ExerciseSet) -> some View {
        Group {
            if stacked {
                HStack(alignment: .firstTextBaseline) {
                    doneLabel(set)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.sm)
            } else {
                HStack(spacing: Spacing.sm) {
                    Group {
                        if set.warmup {
                            Text("set.warmup-short")
                        } else {
                            Text(verbatim: "\(number(of: set))")
                        }
                    }
                    .font(.headline)
                    .frame(width: numberWidth)
                    Text(verbatim: set.values.reps.map(String.init) ?? "–")
                        .frame(maxWidth: .infinity)
                    Text(set.values.weight?.kilograms ?? 0, format: .number.precision(.fractionLength(0 ... 2)))
                        .frame(maxWidth: .infinity)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: numberWidth)
                        .accessibilityHidden(true)
                }
            }
        }
        .monospacedDigit()
        .padding(.vertical, Spacing.xs)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.sm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(doneLabel(set))
        .accessibilityIdentifier(
            set.warmup ? AXID.ActiveWorkout.doneWarmupRow(set.order) : AXID.ActiveWorkout.doneSetRow(number(of: set))
        )
        .contextMenu {
            // The user's warm-up annotation, editable after logging.
            Toggle("set-log.warmup-toggle", isOn: Binding(
                get: { set.warmup },
                set: { try? coordinator.setWarmup($0, setId: set.id) }
            ))
            .accessibilityIdentifier(AXID.ActiveWorkout.setWarmupToggle)

            Button(role: .destructive) {
                Task { try? await coordinator.deleteSet(id: set.id) }
            } label: {
                Label("active-workout.set.delete-button", systemImage: "trash")
            }
            .accessibilityIdentifier(AXID.ActiveWorkout.deleteSetButton)
        }
    }

    private func doneLabel(_ set: ExerciseSet) -> Text {
        let reps = set.values.reps ?? 0
        let kg = (set.values.weight?.kilograms ?? 0).formatted(.number.precision(.fractionLength(0 ... 2)))
        if set.warmup {
            return Text("set-table.done-warmup-label \(reps) \(kg)")
        }
        return Text("set-table.done-label \(number(of: set)) \(reps) \(kg)")
    }

    private func pendingRow(index: Int, values: SetValues) -> some View {
        let number = done.filter { !$0.warmup }.count + index + 1
        return rowLayout {
            Button {
                onDetails(index, number, values)
            } label: {
                Group {
                    if stacked {
                        Text("set-log.set-section-header \(number)")
                    } else {
                        Text(verbatim: "\(number)")
                    }
                }
                .font(.headline)
                .frame(width: stacked ? nil : numberWidth)
                .frame(minHeight: numberWidth)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("set-table.details \(number)"))
            .accessibilityIdentifier(AXID.ActiveWorkout.setDetailsButton(number))

            labelled("set-table.header.reps") {
                TextField("0", value: repsBinding(index: index, values: values), format: .number)
                    .keyboardType(.numberPad)
                    .focused($focused, equals: .reps(index))
                    .fieldStyle()
                    .accessibilityLabel(Text("set-table.reps-field \(number)"))
                    .accessibilityIdentifier(AXID.ActiveWorkout.setRepsField(number))
            }

            labelled("set-table.header.kg") {
                TextField("0", value: weightBinding(index: index, values: values), format: .number)
                    .keyboardType(.decimalPad)
                    .focused($focused, equals: .weight(index))
                    .fieldStyle()
                    .accessibilityLabel(Text("set-table.weight-field \(number)"))
                    .accessibilityIdentifier(AXID.ActiveWorkout.setWeightField(number))
            }

            Button {
                focused = nil
                Task { try? await coordinator.logPendingSet(at: index, of: entry) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .frame(width: numberWidth, height: numberWidth)
            }
            .buttonStyle(.borderless)
            .disabled((values.reps ?? 0) <= 0)
            .accessibilityLabel(Text("set-table.check \(number)"))
            .accessibilityIdentifier(AXID.ActiveWorkout.setCheckButton(number))
        }
        .monospacedDigit()
        .contextMenu {
            Button(role: .destructive) {
                coordinator.removePendingSet(at: index, of: entry)
            } label: {
                Label("set-table.remove-row", systemImage: "minus.circle")
            }
            .accessibilityIdentifier(AXID.ActiveWorkout.removePendingSetButton)
        }
    }

    /// A value cell; stacked, its column name goes above it.
    @ViewBuilder
    private func labelled(_ title: LocalizedStringKey, @ViewBuilder field: () -> some View) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                field()
            }
        } else {
            field()
        }
    }

    // MARK: - Bindings

    private func repsBinding(index: Int, values: SetValues) -> Binding<Int?> {
        Binding(
            get: { values.reps },
            set: { reps in
                var changed = values
                changed.reps = reps
                coordinator.updatePendingSet(changed, at: index, of: entry)
            }
        )
    }

    private func weightBinding(index: Int, values: SetValues) -> Binding<Double?> {
        Binding(
            get: { values.weight.map { ($0.kilograms * 100).rounded() / 100 } },
            set: { kilograms in
                var changed = values
                changed.weight = .kg(max(kilograms ?? 0, 0))
                coordinator.updatePendingSet(changed, at: index, of: entry)
            }
        )
    }
}

private extension View {
    /// A number cell of the table: centred, on a light field background.
    func fieldStyle() -> some View {
        multilineTextAlignment(.center)
            .font(.body.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.surfacePrimary, in: RoundedRectangle(cornerRadius: Radius.sm))
    }
}
