import Foundation

struct UsageCycleSummary {
    let currentUsedCredits: Double
    let remainingBudget: Double
    let activeDayCount: Int
    let averagePerActiveDay: Double?
    let todaySpend: Double?
    let neededDailyRate: Double?
    let projectedEndRemaining: Double?
    let projectedDaysEarly: Int?
    let trajectoryText: String?
    let trajectoryIsOverBudget: Bool
}

func currentCycleSummary(
    points: [UsageDataPoint],
    monthlyLimit: Double,
    now: Date = Date(),
    calendar: Calendar = .current
) -> UsageCycleSummary? {
    guard monthlyLimit > 0 else { return nil }

    let cycleStart = BillingPace.billingStart(now: now, calendar: calendar)
    let cycleEnd   = BillingPace.billingEnd(now: now, calendar: calendar)

    let cyclePoints = points
        .filter { $0.usedCredits != nil && $0.timestamp >= cycleStart && $0.timestamp <= now }
        .sorted { $0.timestamp < $1.timestamp }

    guard let currentUsed = cyclePoints.last?.usedCredits else {
        return UsageCycleSummary(
            currentUsedCredits: 0,
            remainingBudget: monthlyLimit,
            activeDayCount: 0,
            averagePerActiveDay: nil,
            todaySpend: nil,
            neededDailyRate: nil,
            projectedEndRemaining: nil,
            projectedDaysEarly: nil,
            trajectoryText: nil,
            trajectoryIsOverBudget: false
        )
    }

    let remaining = max(0, monthlyLimit - currentUsed)

    // Per-day spend: delta from first to last reading within each calendar day
    let groupedByDay = Dictionary(grouping: cyclePoints) {
        calendar.startOfDay(for: $0.timestamp)
    }

    let activeDayCount = groupedByDay
        .mapValues { pts -> Double in
            let sorted = pts.sorted { $0.timestamp < $1.timestamp }
            return (sorted.last?.usedCredits ?? 0) - (sorted.first?.usedCredits ?? 0)
        }
        .values
        .filter { $0 >= 0.01 }
        .count

    let avgPerActiveDay: Double? = activeDayCount > 0
        ? currentUsed / Double(activeDayCount)
        : nil

    let daysElapsed   = max(1, calendar.dateComponents([.day], from: cycleStart, to: now).day ?? 1)
    let daysRemaining = max(0, calendar.dateComponents([.day], from: now, to: cycleEnd).day ?? 0)

    // Today's spend: current total minus the last reading before today started
    let todayStart = calendar.startOfDay(for: now)
    let todaySpend: Double? = {
        let baseline = cyclePoints.last(where: { $0.timestamp < todayStart })?.usedCredits
            ?? cyclePoints.first?.usedCredits
            ?? 0
        let delta = currentUsed - baseline
        return delta >= 0.01 ? delta : nil
    }()

    // Budget needed per day from today to cycle end
    let neededDailyRate: Double? = daysRemaining >= 0
        ? remaining / Double(max(1, daysRemaining + 1))
        : nil

    var trajectoryText: String?
    var projectedEndRemaining: Double?
    var projectedDaysEarly: Int?
    var trajectoryIsOverBudget = false

    if let avg = avgPerActiveDay, activeDayCount > 0 {
        let activeDayRatio = min(1.0, max(0.0, Double(activeDayCount) / Double(daysElapsed)))
        let expectedRemainingActiveDays = Double(daysRemaining) * activeDayRatio
        let projectedSpend = currentUsed + avg * expectedRemainingActiveDays
        let projectedRemaining = monthlyLimit - projectedSpend
        projectedEndRemaining = projectedRemaining

        if projectedRemaining > 0.5 {
            trajectoryText = "$\(Int(round(projectedRemaining))) left at end of cycle"
        } else if projectedRemaining < -0.5 {
            let burnPerCalendarDay = avg * activeDayRatio
            if burnPerCalendarDay > 0.0001 {
                let daysToBurn = remaining / burnPerCalendarDay
                let daysEarly = max(0, Int(round(Double(daysRemaining) - daysToBurn)))
                projectedDaysEarly = daysEarly
                let runOutDate = calendar.date(byAdding: .day, value: Int(round(daysToBurn)), to: now) ?? now
                let dateStr = runOutDate.formatted(.dateTime.month(.abbreviated).day())
                trajectoryText = daysEarly > 0
                    ? "Budget ends \(dateStr) (\(daysEarly) days early)"
                    : "Budget runs out near cycle end"
                trajectoryIsOverBudget = true
            }
        } else {
            trajectoryText = "On track to use full budget"
        }
    }

    return UsageCycleSummary(
        currentUsedCredits: currentUsed,
        remainingBudget: remaining,
        activeDayCount: activeDayCount,
        averagePerActiveDay: avgPerActiveDay,
        todaySpend: todaySpend,
        neededDailyRate: neededDailyRate,
        projectedEndRemaining: projectedEndRemaining,
        projectedDaysEarly: projectedDaysEarly,
        trajectoryText: trajectoryText,
        trajectoryIsOverBudget: trajectoryIsOverBudget
    )
}
