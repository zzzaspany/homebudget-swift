import HomeBudgetCore
import SwiftUI

/// Confirms what is being paid, and how much — a variable bill rarely matches its nominal amount.
struct PaymentSheet: View {
    let expense: Expense
    let language: Language
    /// What this bill is likely to come to, worked out from its own history. Nil for a fixed bill,
    /// or for a variable one with nothing paid yet.
    let suggestion: AmountSuggestion?
    let onConfirm: (Double?) -> Void

    @State private var amount: String
    @Environment(\.dismiss) private var dismiss

    init(
        expense: Expense, language: Language, suggestion: AmountSuggestion? = nil,
        onConfirm: @escaping (Double?) -> Void
    ) {
        self.expense = expense
        self.language = language
        self.suggestion = suggestion
        self.onConfirm = onConfirm
        // The nominal amount, not the suggestion. A suggestion is offered, not applied — the
        // number in the field should be the one the expense says until somebody chooses otherwise.
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

                    if let suggestion {
                        Button {
                            amount = NumberFormatting.plain(suggestion.amount)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(UIString.suggestionUse(language)) \(NumberFormatting.currency(suggestion.amount, language: language))")
                                    // Why, not just how much: a figure the user cannot account for
                                    // is one they have to check anyway.
                                    Text(basis(suggestion.basis))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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

    private func basis(_ basis: AmountSuggestion.Basis) -> String {
        switch basis {
        case .sameMonth(let date):
            return "\(UIString.suggestionSameMonth(language)) (\(Localization.dateLabel(date, language: language)))"
        case .sameMonthAverage(let count):
            return "\(UIString.suggestionSameMonthAverage(language)) (\(count))"
        case .overallAverage(let count):
            return "\(UIString.suggestionOverallAverage(language)) (\(count))"
        }
    }
}
