import Foundation

/// Automatic account polling backs off after failures. Manual refresh stays available.
public struct QuotaRefreshSchedule {
    public private(set) var nextAttempt = Date.distantPast
    private var consecutiveFailures = 0
    public init() {}
    public func isDue(at date: Date) -> Bool { date >= nextAttempt }
    public mutating func succeeded(at date: Date) {
        consecutiveFailures = 0
        nextAttempt = date
    }
    public mutating func failed(_ error: Error, at date: Date) {
        consecutiveFailures = min(consecutiveFailures + 1, 5)
        let base: TimeInterval = (error as? CodexServiceError)?.httpStatus == 403 ? 300 : 60
        let delay = min(900, base * pow(2, Double(consecutiveFailures - 1)))
        nextAttempt = date.addingTimeInterval(delay)
    }
}
