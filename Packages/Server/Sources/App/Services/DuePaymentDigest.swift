import Fluent
import Foundation
import HomeBudgetCore
import Vapor

/// The daily "what is due" push.
///
/// Sends nothing when nothing is due. A notification that arrives every morning saying all is well
/// is one you stop reading, and the morning it matters you will not read it either.
enum DuePaymentDigest {
    /// Builds the digest and publishes it. Returns how many bills it reported — zero means the
    /// push was skipped, not that it failed.
    @discardableResult
    static func send(
        configuration: NtfyConfiguration,
        database: any Database,
        client: any Client,
        logger: Logger,
        language: Language,
        today: CalendarDate = .today()
    ) async throws -> Int {
        let expenses = try await ExpenseModel.query(on: database).sort(\.$name).all()
        let dashboard = DashboardBuilder.build(expenses: expenses.map(\.domain), today: today)
        let due = dashboard.duePayments(within: configuration.windowDays)

        guard !due.isEmpty else { return 0 }

        // An overdue bill is worth a noise on the phone; a bill due in four days is not.
        let hasOverdue = due.contains { ($0.daysLeft ?? 0) < 0 }

        try await NtfyClient(configuration: configuration, client: client, logger: logger)
            .send(
                title: DueDigest.title(count: due.count, language: language),
                message: DueDigest.body(due, language: language),
                priority: hasOverdue ? 5 : 3,
                tags: hasOverdue ? ["rotating_light", "moneybag"] : ["moneybag"]
            )

        return due.count
    }
}

/// Runs the digest once a day at a fixed local time.
///
/// Each run schedules only the next one, rather than repeating on a fixed 24-hour interval. Two
/// reasons: a fixed interval drifts away from the wall clock across restarts and DST, and a restart
/// part-way through the day cannot replay a push that already went out this morning — the next
/// firing is simply tomorrow.
enum DueDigestScheduler {
    static func start(_ app: Application, configuration: NtfyConfiguration) {
        let language = Language(code: Environment.get("NTFY_LANG"))

        app.logger.info(
            """
            Daily payment digest on: \(configuration.topic) at \
            \(pad(configuration.hour)):\(pad(configuration.minute)), \
            \(configuration.windowDays)-day window
            """
        )

        Task.detached {
            while !Task.isCancelled {
                let seconds = secondsUntilNextRun(
                    hour: configuration.hour, minute: configuration.minute)
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }

                do {
                    let count = try await DuePaymentDigest.send(
                        configuration: configuration,
                        database: app.db,
                        client: app.client,
                        logger: app.logger,
                        language: language
                    )
                    app.logger.info(
                        count == 0
                            ? "Payment digest: nothing due, no push sent"
                            : "Payment digest: pushed \(count) bill(s)")
                } catch {
                    // A failed push must not take the loop down with it - tomorrow should still try.
                    app.logger.error("Payment digest failed: \(error)")
                }
            }
        }
    }

    /// Seconds from now until the next `hour:minute` in the server's local time zone.
    static func secondsUntilNextRun(
        hour: Int,
        minute: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard
            let next = calendar.nextDate(
                after: now, matching: components, matchingPolicy: .nextTime)
        else {
            return 24 * 60 * 60
        }

        return max(1, Int(next.timeIntervalSince(now)))
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
