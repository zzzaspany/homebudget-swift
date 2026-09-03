#if canImport(WASILibc)
    import WASILibc
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The one place in the core that reads the wall clock.
///
/// Uses the C library rather than Foundation so it works identically on a Linux server and inside
/// a WebAssembly build, where pulling in Foundation costs tens of megabytes.
enum PlatformClock {
    /// Julian day number of 1970-01-01, the Unix epoch.
    static let epochJulianDay = 2_440_588

    static func julianDayNumberToday() -> Int {
        let seconds = Int(time(nil))
        // Floor division, so dates before the epoch still land on the right day.
        let days = seconds >= 0 ? seconds / 86400 : (seconds - 86399) / 86400
        return epochJulianDay + days
    }
}
