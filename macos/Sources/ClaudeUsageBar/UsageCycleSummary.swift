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
    let budgetRunoutDate: Date?
    let trajectoryText: String?
    let trajectoryIsOverBudget: Bool
}

func currentCycleSummary(
    points: [UsageDataPoint],
    monthlyLimit: Double,
    workdaysOnly: Bool = false,
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
            budgetRunoutDate: nil,
            trajectoryText: nil,
            trajectoryIsOverBudget: false
        )
    }

    let remaining = max(0, monthlyLimit - currentUsed)

    // Per-day spend: delta from first to last reading within each calendar day
    let groupedByDay = Dictionary(grouping: cyclePoints) {
        calendar.startOfDay(for: $0.timestamp)
    }

    let dailyDeltas = groupedByDay
        .mapValues { pts -> Double in
            let sorted = pts.sorted { $0.timestamp < $1.timestamp }
            return (sorted.last?.usedCredits ?? 0) - (sorted.first?.usedCredits ?? 0)
        }
        .values
        .filter { $0 >= 0.01 }

    let activeDayCount = dailyDeltas.count
    let avgPerActiveDay: Double? = activeDayCount > 0
        ? dailyDeltas.reduce(0, +) / Double(activeDayCount)
        : nil

    // Day counting: calendar days or workdays depending on mode.
    let todayStart = calendar.startOfDay(for: now)
    let daysElapsed: Int
    let daysRemaining: Int
    let totalCycleDays: Int

    if workdaysOnly {
        daysElapsed = max(1, BillingPace.workdayCount(from: cycleStart, to: now, calendar: calendar))
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        daysRemaining = max(0, BillingPace.workdayCount(from: tomorrowStart, to: cycleEnd, calendar: calendar))
        totalCycleDays = max(1, BillingPace.workdayCount(from: cycleStart, to: cycleEnd, calendar: calendar))
    } else {
        daysElapsed   = max(1, calendar.dateComponents([.day], from: cycleStart, to: now).day ?? 1)
        daysRemaining = max(0, calendar.dateComponents([.day], from: now, to: cycleEnd).day ?? 0)
        totalCycleDays = max(1, calendar.dateComponents([.day], from: cycleStart, to: cycleEnd).day ?? 30)
    }

    // Today's spend: current total minus the last reading before today started
    let todaySpend: Double? = {
        let baseline = cyclePoints.last(where: { $0.timestamp < todayStart })?.usedCredits
            ?? cyclePoints.first?.usedCredits
            ?? 0
        let delta = currentUsed - baseline
        return delta >= 0.01 ? delta : nil
    }()

    // Budget needed per workday (or calendar day) from today to cycle end.
    let neededDailyRate: Double? = {
        if workdaysOnly {
            let todayIsWorkday = BillingPace.isWorkday(now, calendar: calendar)
            return remaining / Double(max(1, daysRemaining + (todayIsWorkday ? 1 : 0)))
        }
        return remaining / Double(max(1, daysRemaining + 1))
    }()

    var trajectoryText: String?
    var projectedEndRemaining: Double?
    var projectedDaysEarly: Int?
    var budgetRunoutDate: Date?
    var trajectoryIsOverBudget = false

    // Project by extrapolating the cycle average rate.
    // In workdays mode the rate is per workday, multiplied by total workdays.
    let dailyCycleAvg = currentUsed / Double(daysElapsed)
    let projectedTotal = dailyCycleAvg * Double(totalCycleDays)
    let projectedRemaining = monthlyLimit - projectedTotal
    projectedEndRemaining = projectedRemaining

    if projectedRemaining > 0.5 {
        trajectoryText = "$\(Int(round(projectedRemaining))) left at end of cycle"
    } else if projectedRemaining < -0.5 {
        if dailyCycleAvg > 0.0001 {
            let daysToBurn = remaining / dailyCycleAvg
            let daysEarly = max(0, Int(round(Double(daysRemaining) - daysToBurn)))
            projectedDaysEarly = daysEarly
            let runOut: Date = workdaysOnly
                ? BillingPace.dateByAddingWorkdays(Int(round(daysToBurn)), to: now, calendar: calendar)
                : calendar.date(byAdding: .day, value: Int(round(daysToBurn)), to: now) ?? now
            budgetRunoutDate = runOut
            let dateStr = runOut.formatted(.dateTime.month(.abbreviated).day())
            trajectoryText = daysEarly > 0
                ? "Budget ends \(dateStr) (\(daysEarly) days early)"
                : "Budget runs out near cycle end"
            trajectoryIsOverBudget = true
        }
    } else {
        trajectoryText = "On track to use full budget"
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
        budgetRunoutDate: budgetRunoutDate,
        trajectoryText: trajectoryText,
        trajectoryIsOverBudget: trajectoryIsOverBudget
    )
}
