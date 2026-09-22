import Foundation
import Testing

@testable import App

/// Pure arithmetic over the clock, so it needs neither a database nor a server.
@Suite("Due digest scheduling")
struct DueDigestSchedulerTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        utc.date(
            from: DateComponents(
                timeZone: TimeZone(identifier: "UTC"), year: year, month: month, day: day,
                hour: hour, minute: minute))!
    }

    @Test("Later the same day waits only the remaining hours")
    func laterToday() {
        let seconds = DueDigestScheduler.secondsUntilNextRun(
            hour: 8, minute: 0, now: date(2026, 9, 22, 6, 30), calendar: utc)

        #expect(seconds == 90 * 60)
    }

    /// The case that matters after a restart: past this morning's slot, so the next push is
    /// tomorrow's rather than an immediate duplicate of one already sent.
    @Test("Past the hour, it waits for tomorrow")
    func alreadyPassedToday() {
        let seconds = DueDigestScheduler.secondsUntilNextRun(
            hour: 8, minute: 0, now: date(2026, 9, 22, 9, 0), calendar: utc)

        #expect(seconds == 23 * 60 * 60)
    }

    @Test("Crossing midnight is a normal wait, not a negative one")
    func acrossMidnight() {
        let seconds = DueDigestScheduler.secondsUntilNextRun(
            hour: 8, minute: 30, now: date(2026, 9, 22, 23, 30), calendar: utc)

        #expect(seconds == 9 * 60 * 60)
    }

    /// Never zero: a zero delay would spin the loop, publishing repeatedly within the same minute.
    @Test("Exactly on the hour still waits a full day")
    func exactlyOnTheHour() {
        let seconds = DueDigestScheduler.secondsUntilNextRun(
            hour: 8, minute: 0, now: date(2026, 9, 22, 8, 0), calendar: utc)

        #expect(seconds > 0)
        #expect(seconds == 24 * 60 * 60)
    }
}

@Suite("ntfy configuration")
struct NtfyConfigurationTests {
    /// Absent configuration turns the push off rather than failing the boot, so the default build
    /// of this app starts with no ntfy server in sight.
    @Test("Without a URL and topic there is no configuration")
    func missingConfigurationIsNotAnError() {
        #expect(NtfyConfiguration.make { _ in nil } == nil)
        #expect(NtfyConfiguration.make { _ in "" } == nil)
        #expect(NtfyConfiguration.make { $0 == "NTFY_URL" ? "https://x/" : nil } == nil)
    }

    @Test("Window and time fall back to sensible defaults")
    func defaults() {
        let environment = ["NTFY_URL": "https://example.invalid/", "NTFY_TOPIC": "homebudget"]
        let configuration = NtfyConfiguration.make { environment[$0] }

        #expect(configuration?.windowDays == 5)
        #expect(configuration?.hour == 8)
        #expect(configuration?.minute == 0)
        #expect(configuration?.username == nil)
    }

    @Test("Every setting can be overridden")
    func overrides() {
        let environment = [
            "NTFY_URL": "https://apns.example/", "NTFY_TOPIC": "bills",
            "NTFY_USER": "publisher", "NTFY_PASSWORD": "s3cret",
            "NTFY_DUE_WINDOW_DAYS": "10", "NTFY_DIGEST_HOUR": "19", "NTFY_DIGEST_MINUTE": "45",
        ]
        let configuration = NtfyConfiguration.make { environment[$0] }

        #expect(configuration?.windowDays == 10)
        #expect(configuration?.hour == 19)
        #expect(configuration?.minute == 45)
        #expect(configuration?.username == "publisher")
    }
}
