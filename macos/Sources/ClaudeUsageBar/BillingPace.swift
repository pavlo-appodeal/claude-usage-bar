import Foundation

enum PaceStatus {
    case onTrack  // used ≤ pace
    case warning  // pace < used ≤ pace + 5% of limit
    case over     // used > pace + 5% of limit
}

struct BillingPace {
    /// Fraction of the calendar month elapsed (0–1).
    static func elapsedFraction(now: Date = Date(), calendar: Calendar = .current) -> Double {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return min(max(now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }

    static func paceAmount(limit: Double, now: Date = Date()) -> Double {
        limit * elapsedFraction(now: now)
    }

    /// Start of current billing period (1st of this month).
    static func billingStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    }

    /// Start of next billing period (1st of next month).
    static func billingEnd(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 1, to: billingStart(now: now, calendar: calendar))!
    }

    static func status(used: Double, limit: Double, warningBand: Double = 0.05) -> PaceStatus {
        guard limit > 0 else { return .onTrack }
        let pace = paceAmount(limit: limit)
        let excess = used - pace
        if excess <= 0 { return .onTrack }
        if excess <= limit * warningBand { return .warning }
        return .over
    }
}
