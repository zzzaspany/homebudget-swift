import HomeBudgetCore
import SwiftUI

/// Adds a recurring expense, or edits one.
///
/// Validation mirrors the server's rather than trusting it: a name, an amount above zero and a
/// category. The server would reject the same things, but a form that only finds out after a round
/// trip is a worse form.
struct ExpenseEditor: View {
    /// Nil when adding. Editing keeps the identifier so the caller knows which endpoint to use.
    let existing: Expense?
    let onSave: (ExpenseInput) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String
    @State private var frequency: Frequency
    @State private var dueDay: Int
    @State private var dueMonth: Int
    @State private var category: String
    @State private var active: Bool
    @State private var isVariable: Bool

    private var language: Language { .device }

    init(existing: Expense?, onSave: @escaping (ExpenseInput) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        // Empty rather than "0" when adding: a zero the user has to clear first is a papercut.
        _amount = State(initialValue: existing.map { NumberFormatting.plain($0.amount) } ?? "")
        _frequency = State(initialValue: existing?.frequency ?? .monthly)
        _dueDay = State(initialValue: existing?.dueDay ?? 1)
        _dueMonth = State(initialValue: existing?.dueMonth ?? 1)
        _category = State(
            initialValue: existing?.category ?? Localization.knownCategories.first ?? "Inne")
        _active = State(initialValue: existing?.active ?? true)
        _isVariable = State(initialValue: existing?.isVariable ?? false)
    }

    /// The amount as typed. Both separators are accepted — a Polish keyboard offers a comma and it
    /// would be perverse to reject it.
    private var parsedAmount: Double? {
        Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return UIString.validationName(language)
        }
        guard let parsedAmount, parsedAmount > 0 else {
            return UIString.validationAmount(language)
        }
        if category.trimmingCharacters(in: .whitespaces).isEmpty {
            return UIString.validationCategory(language)
        }
        return nil
    }

    /// Categories already in use that are not in the built-in list — an expense migrated from the
    /// old app must not silently lose its category by being edited.
    private var categories: [String] {
        var all = Localization.knownCategories
        if let existing, !all.contains(existing.category) { all.append(existing.category) }
        return all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(UIString.columnName(language), text: $name)
                    HStack {
                        TextField(UIString.columnAmount(language), text: $amount)
                            .keyboardType(.decimalPad)
                        Text("zł").foregroundStyle(.secondary)
                    }
                    Picker(UIString.columnCategory(language), selection: $category) {
                        ForEach(categories, id: \.self) { name in
                            Text(Localization.category(name, language: language)).tag(name)
                        }
                    }
                }

                Section {
                    Picker(UIString.columnFrequency(language), selection: $frequency) {
                        ForEach(Frequency.allCases, id: \.self) { option in
                            Text(option.label(language: language)).tag(option)
                        }
                    }
                    Picker(UIString.fieldDueDay(language), selection: $dueDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                    // Only the cycles longer than a month need to say which month they land in.
                    if frequency.requiresDueMonth {
                        Picker(UIString.fieldDueMonth(language), selection: $dueMonth) {
                            ForEach(1...12, id: \.self) {
                                Text(Localization.monthName($0, language: language)).tag($0)
                            }
                        }
                    }
                } footer: {
                    if dueDay > 28 {
                        Text(shortMonthNote)
                    }
                }

                Section {
                    Toggle(UIString.fieldActive(language), isOn: $active)
                    Toggle(UIString.fieldVariable(language), isOn: $isVariable)
                }
            }
            .navigationTitle(
                existing == nil
                    ? UIString.addExpenseTitle(language) : UIString.editExpenseTitle(language)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UIString.actionCancel(language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UIString.actionSave(language)) { save() }
                        .disabled(problem != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.bar)
                }
            }
        }
    }

    /// Says out loud what the clamping rule does, rather than letting a bill due on the 31st look
    /// like it will be skipped in February.
    private var shortMonthNote: String {
        language == .pl
            ? "W krótszych miesiącach termin wypadnie ostatniego dnia."
            : "In shorter months the due date falls on the last day."
    }

    private func save() {
        guard let parsedAmount, problem == nil else { return }
        onSave(
            ExpenseInput(
                name: name.trimmingCharacters(in: .whitespaces),
                amount: parsedAmount,
                frequency: frequency,
                dueDay: dueDay,
                dueMonth: frequency.requiresDueMonth ? dueMonth : nil,
                category: category,
                active: active,
                isVariable: isVariable))
        dismiss()
    }
}
