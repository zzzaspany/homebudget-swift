import HomeBudgetCore
import SwiftUI

/// The ceilings the household sets per category, stored on this device.
///
/// Local by design — see `CategoryBudget`. Kept out of the shared app group because the widget has
/// no use for them and a smaller shared surface is easier to reason about.
@MainActor
@Observable
final class CategoryBudgetStore {
    private let key = "categoryBudgetLimits"

    private(set) var limits: [String: Double]

    init() {
        limits = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    /// A non-positive ceiling means "unset" rather than "always exceeded", so it is removed.
    func set(_ limit: Double?, for category: String) {
        if let limit, limit > 0 {
            limits[category] = limit
        } else {
            limits.removeValue(forKey: category)
        }
        UserDefaults.standard.set(limits, forKey: key)
    }
}

struct CategoryBudgetsScreen: View {
    let dashboard: Dashboard
    @State private var store = CategoryBudgetStore()
    @State private var editing: CategoryBudget?
    @State private var draft = ""

    private var language: Language { .device }

    var body: some View {
        List {
            ForEach(dashboard.categoryBudgets(limits: store.limits)) { budget in
                row(budget)
                    .contentShape(.rect)
                    .onTapGesture {
                        draft = budget.limit.map { NumberFormatting.plain($0) } ?? ""
                        editing = budget
                    }
            }
        }
        .navigationTitle(UIString.sectionCategoryBudgets(language))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            editing.map { Localization.category($0.category, language: language) } ?? "",
            isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
        ) {
            TextField(UIString.budgetLimit(language), text: $draft)
                .keyboardType(.decimalPad)
            Button(UIString.actionSave(language)) {
                if let editing {
                    let parsed = Double(draft.replacingOccurrences(of: ",", with: "."))
                    store.set(parsed, for: editing.category)
                }
                editing = nil
            }
            Button(UIString.actionDelete(language), role: .destructive) {
                if let editing { store.set(nil, for: editing.category) }
                editing = nil
            }
            Button(UIString.actionCancel(language), role: .cancel) { editing = nil }
        }
    }

    private func row(_ budget: CategoryBudget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Localization.category(budget.category, language: language))
                    .font(.body.weight(.medium))
                Spacer()
                Text(NumberFormatting.currency(budget.planned, language: language))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }

            if let fraction = budget.fraction, let limit = budget.limit {
                ProgressView(value: fraction)
                    .tint(budget.isOverBudget ? .red : .accentColor)
                HStack {
                    Text("\(UIString.budgetOf(language)) \(NumberFormatting.currency(limit, language: language))")
                    if budget.isOverBudget {
                        Spacer()
                        Text("\(UIString.budgetOverBy(language)) \(NumberFormatting.currency(budget.overspend, language: language))")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(UIString.budgetNoLimit(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
