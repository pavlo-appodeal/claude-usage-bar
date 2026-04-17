import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @AppStorage("setupComplete") private var setupComplete = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !setupComplete && !service.isAuthenticated {
                SetupView(
                    service: service,
                    notificationService: notificationService,
                    onComplete: { setupComplete = true }
                )
            } else {
                Text("Claude Usage")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !service.isAuthenticated {
                    signInView
                } else {
                    usageView
                }
            }
        }
        .padding()
        .frame(width: 340)
    }

    @ViewBuilder
    private var signInView: some View {
        if service.isAwaitingCode {
            CodeEntryView(service: service)
        } else {
            Text("Sign in to view your usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Sign in with Claude") {
                service.startOAuthFlow()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        Divider()
        HStack {
            settingsButton
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
    }

    @AppStorage("menuBarMode") private var menuBarMode = "extraUsage"

    @ViewBuilder
    private var usageView: some View {
        let hideRateLimits = menuBarMode == "extraUsage"
            || (service.usage?.fiveHour?.utilization == nil && service.usage?.sevenDay?.utilization == nil)

        if !hideRateLimits {
            UsageBucketRow(
                label: "5-Hour Window",
                bucket: service.usage?.fiveHour
            )

            UsageBucketRow(
                label: "7-Day Window",
                bucket: service.usage?.sevenDay
            )
        }

        if !hideRateLimits,
           let opus = service.usage?.sevenDayOpus,
           opus.utilization != nil {
            Divider()
            Text("Per-Model (7 day)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            UsageBucketRow(label: "Opus", bucket: opus)
            if let sonnet = service.usage?.sevenDaySonnet {
                UsageBucketRow(label: "Sonnet", bucket: sonnet)
            }
        }

        if let extra = service.usage?.extraUsage, extra.isEnabled {
            Divider()
            ExtraUsageRow(extra: extra, paceStatus: {
                guard let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount else { return .onTrack }
                return BillingPace.status(used: used, limit: limit)
            }())
        }

        Divider()
        UsageChartView(historyService: historyService, monthlyLimit: service.usage?.extraUsage?.monthlyLimitAmount ?? service.lastKnownMonthlyLimit)

        let footerLimit = service.usage?.extraUsage?.monthlyLimitAmount ?? service.lastKnownMonthlyLimit
        if let limit = footerLimit, limit > 0,
           let usedCredits = service.usage?.extraUsage?.usedCreditsAmount,
           let summary = currentCycleSummary(points: historyService.history.dataPoints, monthlyLimit: limit) {
            BudgetStatusFooter(summary: summary, monthlyLimit: limit, usedCredits: usedCredits)
        }

        if let error = service.lastError {
            Divider()
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        if let updaterError = appUpdater.lastError {
            Divider()
            Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        Divider()

        HStack(spacing: 8) {
            settingsButton
            Spacer()
            if let updated = service.lastUpdated {
                Text("Updated \(updated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Refresh") {
                Task { await service.fetchUsage() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            if appUpdater.isConfigured {
                Button("Updates…") {
                    appUpdater.checkForUpdates()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(!appUpdater.canCheckForUpdates)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsButton: some View {
        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

// MARK: - Setup (first launch)

private struct SetupView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    var onComplete: () -> Void

    var body: some View {
        Text("Welcome")
            .font(.headline)
        Text("Configure your preferences to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Divider()

        LaunchAtLoginToggle(controlSize: .small, useSwitchStyle: true)

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SetupThresholdSlider(
                label: "5-hour window",
                value: notificationService.threshold5h,
                onChange: { notificationService.setThreshold5h($0) }
            )
            SetupThresholdSlider(
                label: "7-day window",
                value: notificationService.threshold7d,
                onChange: { notificationService.setThreshold7d($0) }
            )
            SetupThresholdSlider(
                label: "Extra usage",
                value: notificationService.thresholdExtra,
                onChange: { notificationService.setThresholdExtra($0) }
            )
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Polling Interval")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { service.pollingMinutes },
                set: { service.updatePollingInterval($0) }
            )) {
                ForEach(UsageService.pollingOptions, id: \.self) { mins in
                    Text(localizedPollingInterval(for: mins, locale: .autoupdatingCurrent))
                        .tag(mins)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isDiscouragedPollingOption(service.pollingMinutes) {
                Text("Frequent polling may cause rate limiting")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        Divider()

        Button("Get Started") {
            onComplete()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)

        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subviews

private struct CodeEntryView: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        Text("Paste the code from your browser:")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            TextField("code#state", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { submit() }
            Button {
                if let str = NSPasteboard.general.string(forType: .string) {
                    code = str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
        }

        HStack {
            Button("Cancel") {
                service.isAwaitingCode = false
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
        }
    }

    private func submit() {
        let value = code
        Task { await service.submitOAuthCode(value) }
    }
}

private struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(percentageText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            ProgressView(value: (bucket?.utilization ?? 0) / 100.0, total: 1.0)
                .tint(colorForPct((bucket?.utilization ?? 0) / 100.0))
            if let resetDate = bucket?.resetsAtDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }
}

private struct ExtraUsageRow: View {
    let extra: ExtraUsage
    let paceStatus: PaceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extra Usage")
                .font(.subheadline)
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                HStack {
                    Text("$\(Int(round(used))) / $\(Int(round(limit)))")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    if let pct = extra.utilization {
                        Text("\(Int(round(pct)))%")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                ProgressView(value: (extra.utilization ?? 0) / 100.0, total: 1.0)
                    .tint(paceColor)
            }
        }
    }

    private var paceColor: Color {
        switch paceStatus {
        case .onTrack: return .green
        case .warning: return .yellow
        case .over:    return .red
        }
    }
}

private struct SetupThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(value > 0 ? "\(value)%" : "Off")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
            .controlSize(.small)
        }
    }
}

private struct BudgetStatusFooter: View {
    let summary: UsageCycleSummary
    let monthlyLimit: Double
    let usedCredits: Double

    private var paceAmount: Double { BillingPace.paceAmount(limit: monthlyLimit) }
    private var overPaceAmount: Double { usedCredits - paceAmount }
    private var isOver: Bool { overPaceAmount > 0.5 }
    private var isUnder: Bool { overPaceAmount < -0.5 }
    private var overPacePct: Double { monthlyLimit > 0 ? abs(overPaceAmount) / monthlyLimit * 100 : 0 }

    private var accentColor: Color {
        isOver  ? Color(hue: 0.07, saturation: 0.70, brightness: 0.95) :
        isUnder ? Color(hue: 0.40, saturation: 0.58, brightness: 0.82) : .secondary
    }

    private var dailyAvgVsPace: Double? {
        guard let avg = summary.averagePerActiveDay else { return nil }
        return avg - (monthlyLimit / 30)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left: speedometer icon + pace message
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "speedometer")
                        .font(.system(size: 13))
                        .foregroundStyle(accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if abs(overPaceAmount) >= 0.5 {
                        HStack(spacing: 2) {
                            Text("You're")
                            Text("\(String(format: "%.1f", overPacePct))%")
                                .foregroundStyle(accentColor).fontWeight(.semibold)
                            Text(isOver ? "over budget pace" : "under budget pace")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.90))
                    } else {
                        Text("On budget pace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.90))
                    }
                    if let daysEarly = summary.projectedDaysEarly, daysEarly > 0 {
                        HStack(spacing: 2) {
                            Text("Budget ends")
                            Text("\(daysEarly) days early").foregroundStyle(accentColor)
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    } else if let text = summary.trajectoryText {
                        Text(text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            // Right: remaining + today spend
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(Int(round(summary.remainingBudget))) remaining")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                if let today = summary.todaySpend, let needed = summary.neededDailyRate {
                    HStack(spacing: 3) {
                        Text("Today $\(String(format: "%.2f", today))")
                            .foregroundStyle(todayColor(today: today, needed: needed))
                        Text("· need $\(String(format: "%.0f", needed))/day")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10))
                } else if let today = summary.todaySpend {
                    Text("Today $\(String(format: "%.2f", today))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private func todayColor(today: Double, needed: Double) -> Color {
        let ratio = needed > 0 ? today / needed : 0
        if ratio <= 1.0 { return Color(hue: 0.40, saturation: 0.58, brightness: 0.82) }
        if ratio <= 1.5 { return Color(hue: 0.12, saturation: 0.62, brightness: 0.96) }
        return .orange
    }
}

private func colorForPct(_ pct: Double) -> Color {
    switch pct {
    case ..<0.60: return .green
    case 0.60..<0.80: return .yellow
    default: return .red
    }
}
