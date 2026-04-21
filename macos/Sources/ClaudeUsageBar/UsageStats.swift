import Foundation

struct UsageStats {
    struct PeakDay {
        let date: Date
        let amount: Double
    }

    struct PeakRate {
        let rate: Double
        let date: Date  // start of the window that hit peak rate
    }

    // weekday: 2=Mon … 7=Sat, 1=Sun (Calendar convention)
    struct WeekdaySpend: Identifiable {
        let id: Int
        let weekday: Int
        let label: String
        let avgAmount: Double
    }

    // hourly: 0–23 avg spend, for the hour chart
    struct HourlySpend: Identifiable {
        let id: Int   // 0-23
        let hour: Int
        let label: String  // "12am", "3pm", etc.
        let avgAmount: Double
    }

    let peakDay: PeakDay?
    let peakRate: PeakRate?         // $/hr — fastest single active window + when
    let avgActiveBurnRate: Double?  // $/hr — mean over all active windows
    let favoriteHour: Int?          // 0-23 — hour with highest total spend
    let medianDailySpend: Double?   // median $ per active calendar day
    let totalRecordedSpend: Double
    let activeDaysCount: Int
    let weekdaySpends: [WeekdaySpend]  // Mon–Sun avg, for the bar chart
    let hourlySpends: [HourlySpend]    // 0–23 avg, for the hour bar chart

    static let none = UsageStats(
        peakDay: nil, peakRate: nil,
        avgActiveBurnRate: nil, favoriteHour: nil,
        medianDailySpend: nil,
        totalRecordedSpend: 0, activeDaysCount: 0,
        weekdaySpends: [], hourlySpends: []
    )

    // "Active window" = consecutive pair where credits grew and the gap is
    // short enough that it's genuine usage, not a multi-day silence.
    static func compute(from dataPoints: [UsageDataPoint]) -> UsageStats {
        let pts = dataPoints
            .filter { $0.usedCredits != nil }
            .sorted { $0.timestamp < $1.timestamp }

        guard pts.count >= 2 else { return .none }

        // Max gap we'll treat as a single active window (4 h covers any polling
        // interval up to 60 min with a generous buffer).
        let maxGapSeconds: Double = 4 * 3600

        struct Window {
            let delta: Double
            let hours: Double
            let startHour: Int  // 0-23
            let startDate: Date
        }
        var windows: [Window] = []

        for i in 0 ..< pts.count - 1 {
            let a = pts[i], b = pts[i + 1]
            guard let ca = a.usedCredits, let cb = b.usedCredits else { continue }
            let delta = cb - ca
            let gap = b.timestamp.timeIntervalSince(a.timestamp)
            guard delta > 0, gap > 0, gap <= maxGapSeconds else { continue }
            let h = Calendar.current.component(.hour, from: a.timestamp)
            windows.append(Window(delta: delta, hours: gap / 3600, startHour: h, startDate: a.timestamp))
        }

        // Per-day spend — sum of active-window deltas bucketed by calendar day
        var daySpend: [Date: Double] = [:]
        for i in 0 ..< pts.count - 1 {
            let a = pts[i], b = pts[i + 1]
            guard let ca = a.usedCredits, let cb = b.usedCredits else { continue }
            let delta = cb - ca
            let gap = b.timestamp.timeIntervalSince(a.timestamp)
            guard delta > 0, gap <= maxGapSeconds else { continue }
            let day = Calendar.current.startOfDay(for: a.timestamp)
            daySpend[day, default: 0] += delta
        }

        let peakDay = daySpend.max(by: { $0.value < $1.value })
            .map { PeakDay(date: $0.key, amount: $0.value) }

        let peakRateWindow = windows.max(by: { ($0.delta / $0.hours) < ($1.delta / $1.hours) })
        let peakRate = peakRateWindow.map { PeakRate(rate: $0.delta / $0.hours, date: $0.startDate) }

        let totalDelta = windows.reduce(0) { $0 + $1.delta }
        let totalHours = windows.reduce(0) { $0 + $1.hours }
        let avgBurn = totalHours > 0 ? totalDelta / totalHours : nil

        // Favourite hour: the hour bucket with the most total spend
        // Also build per-day spend per hour so we can average across days
        var hourSpend: [Int: Double] = [:]
        var hourDayBuckets: [Int: Set<Date>] = [:]  // hour → set of calendar days that had spend
        for w in windows {
            let day = Calendar.current.startOfDay(for: w.startDate)
            hourSpend[w.startHour, default: 0] += w.delta
            hourDayBuckets[w.startHour, default: []].insert(day)
        }
        let favHour = hourSpend.max(by: { $0.value < $1.value })?.key

        // Median daily spend
        let sortedAmounts = daySpend.values.sorted()
        let median: Double? = sortedAmounts.isEmpty ? nil : {
            let mid = sortedAmounts.count / 2
            return sortedAmounts.count % 2 == 0
                ? (sortedAmounts[mid - 1] + sortedAmounts[mid]) / 2
                : sortedAmounts[mid]
        }()

        // Average spend per weekday (Mon–Sun order)
        var weekdayBuckets: [Int: [Double]] = [:]
        for (date, amount) in daySpend {
            let wd = Calendar.current.component(.weekday, from: date)
            weekdayBuckets[wd, default: []].append(amount)
        }
        // Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7, Sun=1 — display Mon first
        let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
        let weekdayLabels = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
        let weekdaySpends: [WeekdaySpend] = weekdayOrder.compactMap { wd in
            guard let amounts = weekdayBuckets[wd], !amounts.isEmpty else { return nil }
            return WeekdaySpend(
                id: wd,
                weekday: wd,
                label: weekdayLabels[wd] ?? "?",
                avgAmount: amounts.reduce(0, +) / Double(amounts.count)
            )
        }

        // Average spend per hour (0–23), only including hours with data
        func hourLabel(_ h: Int) -> String {
            let display = h % 12 == 0 ? 12 : h % 12
            return "\(display)\(h < 12 ? "am" : "pm")"
        }
        let hourlySpends: [HourlySpend] = (0..<24).compactMap { h in
            guard let total = hourSpend[h], let days = hourDayBuckets[h], !days.isEmpty else { return nil }
            return HourlySpend(id: h, hour: h, label: hourLabel(h), avgAmount: total / Double(days.count))
        }

        return UsageStats(
            peakDay: peakDay,
            peakRate: peakRate,
            avgActiveBurnRate: avgBurn,
            favoriteHour: favHour,
            medianDailySpend: median,
            totalRecordedSpend: totalDelta,
            activeDaysCount: daySpend.count,
            weekdaySpends: weekdaySpends,
            hourlySpends: hourlySpends
        )
    }
}
