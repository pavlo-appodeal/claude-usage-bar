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
        .frame(width: 360)
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

        if let extra = service.effectiveExtraUsage, extra.isEnabled {
            Divider()
            ExtraUsageRow(extra: extra, paceStatus: {
                guard let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount else { return .onTrack }
                return BillingPace.status(used: used, limit: limit)
            }())
        }

        Divider()
        UsageChartView(historyService: historyService, monthlyLimit: service.effectiveExtraUsage?.monthlyLimitAmount ?? service.lastKnownMonthlyLimit)

        let footerLimit = service.effectiveExtraUsage?.monthlyLimitAmount ?? service.lastKnownMonthlyLimit
        let footerUsed = service.effectiveExtraUsage?.usedCreditsAmount
            ?? historyService.history.dataPoints.last(where: { $0.usedCredits != nil })?.usedCredits
        if let limit = footerLimit, limit > 0,
           let usedCredits = footerUsed,
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
            RefreshStatusButton(lastUpdated: service.lastUpdated) {
                Task { await service.fetchUsage() }
            }
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

    private var overPaceAmount: Double { usedCredits - BillingPace.paceAmount(limit: monthlyLimit) }
    private var isOver: Bool  { overPaceAmount >  0.5 }
    private var isUnder: Bool { overPaceAmount < -0.5 }
    private var overPacePct: Double { monthlyLimit > 0 ? abs(overPaceAmount) / monthlyLimit * 100 : 0 }
    private var accentColor: Color {
        isOver  ? Color(hue: 0.07, saturation: 0.70, brightness: 0.95) :
        isUnder ? Color(hue: 0.40, saturation: 0.58, brightness: 0.82) : .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            // Tile 1 — Pace
            StatTile {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 11))
                            .foregroundStyle(accentColor)
                        Text("pace")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if abs(overPaceAmount) >= 0.5 {
                        (Text("\(String(format: "%.1f", overPacePct))%").bold()
                            + Text(isOver ? " over" : " under"))
                            .font(.system(size: 13))
                            .foregroundStyle(accentColor)
                    } else {
                        Text("on track")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hue: 0.40, saturation: 0.58, brightness: 0.82))
                    }
                    if let daysEarly = summary.projectedDaysEarly, daysEarly > 0 {
                        Text("ends \(daysEarly)d early")
                            .font(.system(size: 10))
                            .foregroundStyle(accentColor.opacity(0.8))
                    } else if let text = summary.trajectoryText {
                        Text(text)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            // Tile 2 — Remaining
            StatTile {
                VStack(alignment: .leading, spacing: 4) {
                    Text("remaining")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("$\(Int(round(summary.remainingBudget)))")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("of $\(Int(round(monthlyLimit)))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Tile 3 — Today
            if let today = summary.todaySpend {
                let needed = summary.neededDailyRate
                StatTile {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("today")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("$\(String(format: "%.2f", today))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(todayColor(today: today, needed: needed))
                        if let needed {
                            Text("need $\(String(format: "%.0f", needed))/day")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func todayColor(today: Double, needed: Double?) -> Color {
        guard let needed, needed > 0 else { return .secondary }
        let ratio = today / needed
        if ratio <= 1.0 { return Color(hue: 0.40, saturation: 0.58, brightness: 0.82) }
        if ratio <= 1.5 { return Color(hue: 0.12, saturation: 0.62, brightness: 0.96) }
        return .orange
    }
}

private struct StatTile<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Refresh status button

private struct RefreshStatusButton: View {
    let lastUpdated: Date?
    let onRefresh: () -> Void
    @State private var isHovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: onRefresh) {
                ZStack {
                    Text("Refresh")
                        .opacity(isHovering ? 1 : 0)
                    Text(idleLabel(now: context.date))
                        .opacity(isHovering ? 0 : 1)
                }
                .font(.caption)
                .foregroundStyle(isHovering ? .primary : .secondary)
                .animation(.easeInOut(duration: 0.12), value: isHovering)
            }
            .buttonStyle(.borderless)
            .onHover { isHovering = $0 }
        }
    }

    private func idleLabel(now: Date) -> String {
        guard let updated = lastUpdated else { return "Never refreshed" }
        let elapsed = max(0, now.timeIntervalSince(updated))
        if elapsed < 5   { return "Just updated" }
        if elapsed < 90  {
            let s = Int(elapsed)
            return "Updated \(s) second\(s == 1 ? "" : "s") ago"
        }
        let mins = Int(elapsed / 60)
        if mins < 60 {
            return "Updated \(mins) minute\(mins == 1 ? "" : "s") ago"
        }
        let hours = Int(elapsed / 3600)
        return "Updated \(hours) hour\(hours == 1 ? "" : "s") ago"
    }
}

private func colorForPct(_ pct: Double) -> Color {
    switch pct {
    case ..<0.60: return .green
    case 0.60..<0.80: return .yellow
    default: return .red
    }
}
