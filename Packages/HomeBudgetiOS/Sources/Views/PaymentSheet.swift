import HomeBudgetCore
import SwiftUI

/// Confirms what is being paid, and how much — a variable bill rarely matches its nominal amount.
struct PaymentSheet: View {
    let expense: Expense
    let language: Language
    let onConfirm: (Double?) -> Void

    @State private var amount: String
    @Environment(\.dismiss) private var dismiss

    init(expense: Expense, language: Language, onConfirm: @escaping (Double?) -> Void) {
        self.expense = expense
        self.language = language
        self.onConfirm = onConfirm
        _amount = State(initialValue: NumberFormatting.plain(expense.amount))
    }

    private var parsedAmount: Double? {
        // A comma is what a Polish keyboard offers for a decimal separator.
        Double(amount.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(UIString.columnName(language), value: expense.name)
                    LabeledContent(
                        UIString.columnFrequency(language),
                        value: expense.frequency.label(language: language))
                }

                Section(UIString.columnAmount(language)) {
                    TextField(UIString.columnAmount(language), text: $amount)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()

                    if expense.isVariable {
                        Text(UIString.variableBill(language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(UIString.actionPay(language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(UIString.actionCancel(language)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UIString.actionPay(language)) {
                        onConfirm(parsedAmount)
                    }
                    .disabled(parsedAmount == nil || parsedAmount! <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
