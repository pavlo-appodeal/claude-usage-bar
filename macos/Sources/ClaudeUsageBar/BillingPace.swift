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

    struct PaceSegment {
        let idx: Int
        let start: Date; let startVal: Double
        let end: Date;   let endVal: Double
    }

    /// Returns pace line segments for the window, one per billing period that overlaps it.
    /// Includes explicit vertical-drop segments at month resets to produce the /|/ sawtooth.
    static func paceLineSegments(
        limit: Double,
        from windowStart: Date,
        to windowEnd: Date,
        calendar: Calendar = .current
    ) -> [PaceSegment] {
        var result = [PaceSegment]()
        var monthStart = billingStart(now: windowStart, calendar: calendar)
        var idx = 0
        while monthStart < windowEnd {
            let monthEnd = billingEnd(now: monthStart, calendar: calendar)
            let segStart = max(monthStart, windowStart)
            let segEnd   = min(monthEnd, windowEnd)
            if segStart < segEnd {
                let atMonthBoundary = segEnd >= monthEnd
                // paceAmount(now: monthEnd) evaluates as start of NEXT month = $0, so
                // use `limit` directly when we reach the true end of the billing period.
                let endVal = atMonthBoundary ? limit : paceAmount(limit: limit, now: segEnd)
                result.append(PaceSegment(
                    idx: idx,
                    start: segStart, startVal: paceAmount(limit: limit, now: segStart),
                    end:   segEnd,   endVal:   endVal
                ))
                idx += 1
                // Vertical drop at the reset point — two points at ±0.5s so they form
                // a near-vertical line without ambiguity about same-timestamp rendering.
                if atMonthBoundary && monthEnd < windowEnd {
                    result.append(PaceSegment(
                        idx: idx,
                        start: monthEnd.addingTimeInterval(-0.5), startVal: limit,
                        end:   monthEnd.addingTimeInterval( 0.5), endVal:   0.0
                    ))
                    idx += 1
                }
            }
            monthStart = monthEnd
        }
        return result
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
