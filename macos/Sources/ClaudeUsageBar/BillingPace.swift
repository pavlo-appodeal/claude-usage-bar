import Foundation

enum PaceStatus {
    case onTrack  // used ≤ pace
    case warning  // pace < used ≤ pace + 5% of limit
    case over     // used > pace + 5% of limit
}

struct BillingPace {
    // MARK: - Workday helpers

    /// Count of workdays (Mon–Fri) in the half-open interval [start, end).
    static func workdayCount(from start: Date, to end: Date, calendar: Calendar = .current) -> Int {
        var count = 0
        var current = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while current < endDay {
            let weekday = calendar.component(.weekday, from: current)
            if weekday >= 2 && weekday <= 6 { count += 1 }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return count
    }

    static func isWorkday(_ date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday >= 2 && weekday <= 6
    }

    /// Returns the date that is `n` workdays after `date` (skipping Sat/Sun).
    static func dateByAddingWorkdays(_ n: Int, to date: Date, calendar: Calendar = .current) -> Date {
        guard n > 0 else { return date }
        var count = 0
        var current = calendar.startOfDay(for: date)
        while count < n {
            current = calendar.date(byAdding: .day, value: 1, to: current)!
            if isWorkday(current, calendar: calendar) { count += 1 }
        }
        return current
    }

    // MARK: - Elapsed fraction

    /// Fraction of the billing period elapsed (0–1).
    /// In workdays mode the fraction is based on workdays elapsed vs total workdays in the month,
    /// with linear interpolation within the current workday.
    static func elapsedFraction(now: Date = Date(), workdaysOnly: Bool = false, calendar: Calendar = .current) -> Double {
        if workdaysOnly {
            let start = billingStart(now: now, calendar: calendar)
            let end   = billingEnd(now: now, calendar: calendar)
            let totalWorkdays = Double(workdayCount(from: start, to: end, calendar: calendar))
            guard totalWorkdays > 0 else { return 0 }
            let todayStart = calendar.startOfDay(for: now)
            let completedWorkdays = Double(workdayCount(from: start, to: todayStart, calendar: calendar))
            let todayFraction: Double = {
                guard isWorkday(now, calendar: calendar) else { return 0 }
                let nextDay = calendar.date(byAdding: .day, value: 1, to: todayStart)!
                return now.timeIntervalSince(todayStart) / nextDay.timeIntervalSince(todayStart)
            }()
            return min(1.0, (completedWorkdays + todayFraction) / totalWorkdays)
        }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let end   = calendar.date(byAdding: .month, value: 1, to: start)!
        return min(max(now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }

    static func paceAmount(limit: Double, now: Date = Date(), workdaysOnly: Bool = false) -> Double {
        limit * elapsedFraction(now: now, workdaysOnly: workdaysOnly)
    }

    // MARK: - Billing period boundaries

    /// Start of current billing period (1st of this month).
    static func billingStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    }

    /// Start of next billing period (1st of next month).
    static func billingEnd(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: 1, to: billingStart(now: now, calendar: calendar))!
    }

    // MARK: - Pace line segments

    struct PaceSegment {
        let idx: Int
        let start: Date; let startVal: Double
        let end: Date;   let endVal: Double
    }

    /// Returns pace line segments for the window, one per billing period that overlaps it.
    /// In workdays mode each calendar day is its own segment so the line steps only on workdays.
    static func paceLineSegments(
        limit: Double,
        from windowStart: Date,
        to windowEnd: Date,
        workdaysOnly: Bool = false,
        calendar: Calendar = .current
    ) -> [PaceSegment] {
        if workdaysOnly {
            return workdayPaceLineSegments(limit: limit, from: windowStart, to: windowEnd, calendar: calendar)
        }
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

    /// One segment per calendar day: flat on weekends, sloped on workdays.
    /// Produces a staircase guide that only advances on Mon–Fri.
    private static func workdayPaceLineSegments(
        limit: Double,
        from windowStart: Date,
        to windowEnd: Date,
        calendar: Calendar
    ) -> [PaceSegment] {
        var result = [PaceSegment]()
        var monthStart = billingStart(now: windowStart, calendar: calendar)
        var idx = 0

        while monthStart < windowEnd {
            let monthEnd = billingEnd(now: monthStart, calendar: calendar)
            let totalWorkdays = Double(workdayCount(from: monthStart, to: monthEnd, calendar: calendar))
            let step = totalWorkdays > 0 ? limit / totalWorkdays : 0

            var dayStart = calendar.startOfDay(for: max(monthStart, windowStart))
            if dayStart < monthStart { dayStart = monthStart }
            var workdaysBeforeDay = Double(workdayCount(from: monthStart, to: dayStart, calendar: calendar))

            while dayStart < min(monthEnd, windowEnd) {
                let dayFullEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let actualDayEnd = min(dayFullEnd, min(monthEnd, windowEnd))
                let weekday = calendar.component(.weekday, from: dayStart)
                let isDayWorkday = weekday >= 2 && weekday <= 6

                // Interpolate partial days (e.g., current day not yet complete).
                let dayProgress = dayFullEnd.timeIntervalSince(dayStart) > 0
                    ? actualDayEnd.timeIntervalSince(dayStart) / dayFullEnd.timeIntervalSince(dayStart)
                    : 1.0
                let startVal = min(workdaysBeforeDay * step, limit)
                let endVal   = min(startVal + (isDayWorkday ? dayProgress * step : 0), limit)

                result.append(PaceSegment(idx: idx, start: dayStart, startVal: startVal, end: actualDayEnd, endVal: endVal))
                idx += 1

                if isDayWorkday && actualDayEnd >= dayFullEnd { workdaysBeforeDay += 1 }
                dayStart = actualDayEnd
            }

            if monthEnd < windowEnd {
                result.append(PaceSegment(
                    idx: idx,
                    start: monthEnd.addingTimeInterval(-0.5), startVal: limit,
                    end:   monthEnd.addingTimeInterval( 0.5), endVal:   0.0
                ))
                idx += 1
            }

            monthStart = monthEnd
        }
        return result
    }

    // MARK: - Status

    static func status(used: Double, limit: Double, workdaysOnly: Bool = false, warningBand: Double = 0.05) -> PaceStatus {
        guard limit > 0 else { return .onTrack }
        let pace = paceAmount(limit: limit, workdaysOnly: workdaysOnly)
        let excess = used - pace
        if excess <= 0 { return .onTrack }
        if excess <= limit * warningBand { return .warning }
        return .over
    }
}
