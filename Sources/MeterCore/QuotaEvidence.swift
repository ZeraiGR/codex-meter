import Foundation

public struct WeeklyResetChange: Codable {
    public var previousReset: Double
    public var reportedReset: Double
    public var observedAt: Date
    public var previousObservation: Date
    public var usageDropped: Bool
}

extension AccountSnapshot {
    /// Preserve server values; add evidence labels without inventing a reset schedule.
    public func withQuotaEvidence(previous: AccountSnapshot?) -> AccountSnapshot {
        var result = self
        for index in result.buckets.indices {
            func annotate(_ window: QuotaWindow?) -> QuotaWindow? {
                guard var window else { return nil }
                if let reset = window.resetsAt {
                    window.resetIsProvisional = window.usedPercent == 0 && window.duration > 0
                        && reset - fetchedAt.timeIntervalSince1970 >= window.duration - 120
                }
                return window
            }
            result.buckets[index].primary = annotate(result.buckets[index].primary)
            result.buckets[index].secondary = annotate(result.buckets[index].secondary)
        }
        guard let previous, previous.accountKey == accountKey,
              previous.fetchedAt <= fetchedAt else { return result }
        result.weeklyResetChange = previous.weeklyResetChange
        guard let old = previous.main?.windows.first(where: { $0.windowDurationMins == 10080 }),
              let new = result.main?.windows.first(where: { $0.windowDurationMins == 10080 }),
              let before = old.resetsAt, let after = new.resetsAt,
              before.isFinite, after.isFinite, abs(before - after) > 90 else { return result }
        // Old versions have no label. Recognize their placeholder responses too.
        let oldPlaceholder = old.resetIsProvisional == true || (old.usedPercent == 0
            && before - previous.fetchedAt.timeIntervalSince1970 >= old.duration - 120)
        guard !oldPlaceholder else { return result }
        result.weeklyResetChange = WeeklyResetChange(previousReset: before, reportedReset: after,
            observedAt: fetchedAt, previousObservation: previous.fetchedAt,
            usageDropped: new.usedPercent < old.usedPercent)
        return result
    }
}
