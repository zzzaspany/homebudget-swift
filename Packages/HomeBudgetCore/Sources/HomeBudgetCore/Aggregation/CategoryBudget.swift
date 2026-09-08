/// A monthly ceiling the household sets for a category, and how the current plan measures against it.
///
/// Deliberately local to whoever set it: these are intentions, not facts about the expenses, and the
/// server has never stored them. The web client keeps them in the browser and the iOS app in its own
/// defaults, which means the two can disagree — that is the accepted cost of not inventing a
/// server-side model for a number one person picks.
public struct CategoryBudget: Hashable, Sendable, Identifiable {
    public let category: String
    /// What the recurring expenses in this category cost per month, prorated.
    public let planned: Double
    /// The ceiling, or nil when none has been set.
    public let limit: Double?

    public var id: String { category }

    public init(category: String, planned: Double, limit: Double?) {
        self.category = category
        self.planned = planned
        self.limit = limit
    }

    /// How much of the ceiling the plan uses, clamped so a bar cannot run off its track.
    ///
    /// Nil when there is no ceiling: a progress bar against nothing is meaningless, and drawing it
    /// empty would read as "plenty of room" rather than "not measured".
    public var fraction: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(planned / limit, 1)
    }

    public var isOverBudget: Bool {
        guard let limit, limit > 0 else { return false }
        return planned > limit
    }

    /// By how much the ceiling is exceeded, or zero.
    public var overspend: Double {
        guard let limit, limit > 0, planned > limit else { return 0 }
        return planned - limit
    }
}

extension Dashboard {
    /// Every category the expenses fall into, with its prorated monthly cost and whatever ceiling
    /// the caller has stored for it.
    ///
    /// Ordered by spend rather than alphabetically — the point of the screen is which categories are
    /// large, and an alphabetical list buries that.
    public func categoryBudgets(limits: [String: Double]) -> [CategoryBudget] {
        categoryBreakdown
            .map {
                CategoryBudget(
                    category: $0.category, planned: $0.proratedAmount, limit: limits[$0.category])
            }
            .sorted { $0.planned > $1.planned }
    }
}
