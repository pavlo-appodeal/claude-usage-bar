import Foundation

struct UsageStats {
    struct PeakDay {
        let date: Date
        let amount: Double
    }

    let peakDay: PeakDay?
    let peakHourlyRate: Double?     // $/hr — fastest single active window
    let avgActiveBurnRate: Double?  // $/hr — mean over all active windows
    let favoriteHour: Int?          // 0-23 — hour with highest total spend
    let totalRecordedSpend: Double  // sum of all positive deltas all-time
    let activeDaysCount: Int

    static let none = UsageStats(
        peakDay: nil, peakHourlyRate: nil,
        avgActiveBurnRate: nil, favoriteHour: nil,
        totalRecordedSpend: 0, activeDaysCount: 0
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
        }
        var windows: [Window] = []

        for i in 0 ..< pts.count - 1 {
            let a = pts[i], b = pts[i + 1]
            guard let ca = a.usedCredits, let cb = b.usedCredits else { continue }
            let delta = cb - ca
            let gap = b.timestamp.timeIntervalSince(a.timestamp)
            guard delta > 0, gap > 0, gap <= maxGapSeconds else { continue }
            let h = Calendar.current.component(.hour, from: a.timestamp)
            windows.append(Window(delta: delta, hours: gap / 3600, startHour: h))
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

        let peakRate = windows.map { $0.delta / $0.hours }.max()

        let totalDelta = windows.reduce(0) { $0 + $1.delta }
        let totalHours = windows.reduce(0) { $0 + $1.hours }
        let avgBurn = totalHours > 0 ? totalDelta / totalHours : nil

        // Favourite hour: the hour bucket with the most total spend
        var hourSpend: [Int: Double] = [:]
        for w in windows { hourSpend[w.startHour, default: 0] += w.delta }
        let favHour = hourSpend.max(by: { $0.value < $1.value })?.key

        return UsageStats(
            peakDay: peakDay,
            peakHourlyRate: peakRate,
            avgActiveBurnRate: avgBurn,
            favoriteHour: favHour,
            totalRecordedSpend: totalDelta,
            activeDaysCount: daySpend.count
        )
    }
}
