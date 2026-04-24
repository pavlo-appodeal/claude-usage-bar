import SwiftUI
import Charts

struct StatsView: View {
    let stats: UsageStats

    private enum RtkState {
        case checking
        case notFound
        case installing
        case installFailed
        case found(saved: Int, pct: Double)
    }
    @State private var rtkState: RtkState = .checking

    var body: some View {
        if stats.activeDaysCount == 0 {
            Text("No spending data yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            VStack(spacing: 8) {
                // Row 1 — best day + peak rate
                HStack(spacing: 8) {
                    statTile(
                        icon: "trophy.fill", iconColor: .usageAmber,
                        label: "best day",
                        value: stats.peakDay.map { "$\(String(format: "%.2f", $0.amount))" },
                        sub: stats.peakDay.map { $0.date.formatted(.dateTime.month(.abbreviated).day()) }
                    )
                    statTile(
                        icon: "bolt.fill", iconColor: .usageCrimson,
                        label: "peak rate",
                        value: stats.peakRate.map { rateString($0.rate) },
                        sub: stats.peakRate.map { $0.date.formatted(.dateTime.month(.abbreviated).day().hour()) }
                    )
                }

                // Row 2 — avg burn + fav hour
                HStack(spacing: 8) {
                    statTile(
                        icon: "flame.fill", iconColor: .usageAmber,
                        label: "avg burn",
                        value: stats.avgActiveBurnRate.map { rateString($0) },
                        sub: "active windows only"
                    )
                    statTile(
                        icon: "clock.fill", iconColor: .usageSapphire,
                        label: "fav hour",
                        value: stats.favoriteHour.map { hourLabel($0) }
                    )
                }

                // Row 3 — coffees burned
                let coffees = Int(stats.totalRecordedSpend / 5.0)
                if coffees > 0 {
                    statTile(
                        icon: "cup.and.saucer.fill", iconColor: .usageAmber,
                        label: "coffees burned",
                        value: "≈ \(coffees) ☕",
                        sub: "at $5 each"
                    )
                }

                // Row 4 — rtk token savings (optional, only if rtk is installed or to prompt install)
                rtkTile

                // Bar chart — per-day spend
                dailyChart

                // Bar chart — per-hour spend
                if !stats.hourlySpends.isEmpty {
                    hourlyChart
                }

                // Summary bar
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                    let days = stats.activeDaysCount
                    Text("$\(String(format: "%.2f", stats.totalRecordedSpend)) across \(days) active day\(days == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
            }
            .task { await loadRtk() }
        }
    }

    // MARK: - RTK gain tile

    @ViewBuilder
    private var rtkTile: some View {
        switch rtkState {
        case .checking:
            EmptyView()

        case .notFound, .installFailed:
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("token savings")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text("install rtk")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if case .installFailed = rtkState {
                        Text("install failed — try in Terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    } else {
                        Text("save 60–90% tokens on dev commands")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Install") {
                    Task { await installRtk() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.usageSapphire)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))

        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Installing rtk…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))

        case .found(let saved, let pct):
            if saved > 0 {
                statTile(
                    icon: "bolt.circle.fill", iconColor: .usageEmerald,
                    label: "rtk tokens saved",
                    value: formatTokens(saved),
                    sub: pct > 0 ? "avg \(Int(pct))% compression" : nil
                )
            }
        }
    }

    // MARK: - RTK helpers

    private func loadRtk() async {
        let candidates = [
            "/opt/homebrew/bin/rtk",
            "/usr/local/bin/rtk",
            "/usr/bin/rtk",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.cargo/bin/rtk",
        ]
        guard let rtkPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            rtkState = .notFound
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: rtkPath)
        process.arguments = ["gain", "--format", "json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        struct RtkResponse: Decodable {
            struct Summary: Decodable {
                let total_saved: Int
                let avg_savings_pct: Double
            }
            let summary: Summary
        }

        await withCheckedContinuation { cont in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let parsed = try? JSONDecoder().decode(RtkResponse.self, from: data) {
                    Task { @MainActor in
                        self.rtkState = .found(saved: parsed.summary.total_saved, pct: parsed.summary.avg_savings_pct)
                    }
                } else {
                    Task { @MainActor in self.rtkState = .found(saved: 0, pct: 0) }
                }
                cont.resume()
            }
            try? process.run()
        }
    }

    private func installRtk() async {
        rtkState = .installing

        let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brewPath = brewCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            rtkState = .installFailed
            return
        }

        let brewProc = Process()
        brewProc.executableURL = URL(fileURLWithPath: brewPath)
        brewProc.arguments = ["install", "rtk"]
        brewProc.standardOutput = Pipe()
        brewProc.standardError = Pipe()

        let brewOk = await withCheckedContinuation { cont in
            brewProc.terminationHandler = { p in cont.resume(returning: p.terminationStatus == 0) }
            try? brewProc.run()
        }

        guard brewOk else {
            rtkState = .installFailed
            return
        }

        let rtkCandidates = ["/opt/homebrew/bin/rtk", "/usr/local/bin/rtk"]
        if let rtkPath = rtkCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let initProc = Process()
            initProc.executableURL = URL(fileURLWithPath: rtkPath)
            initProc.arguments = ["init", "-g"]
            initProc.standardOutput = Pipe()
            initProc.standardError = Pipe()
            await withCheckedContinuation { cont in
                initProc.terminationHandler = { _ in cont.resume() }
                try? initProc.run()
            }
        }

        await loadRtk()
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }

    // MARK: - Weekday bar chart

    @ViewBuilder
    private var dailyChart: some View {
        let shown = stats.weekdaySpends
        let median = stats.medianDailySpend
        let maxVal = shown.map(\.avgAmount).max() ?? 1

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("avg spend by weekday")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let m = median {
                    Text("median $\(String(format: "%.2f", m))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Chart {
                ForEach(shown) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Spend", day.avgAmount)
                    )
                    .foregroundStyle(barColor(day.avgAmount, max: maxVal))
                    .cornerRadius(3)
                }
                if let m = median {
                    RuleMark(y: .value("Median", m))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("med")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))").font(.system(size: 9))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartPlotStyle { $0.clipped() }
            .frame(height: 100)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Hourly bar chart

    @ViewBuilder
    private var hourlyChart: some View {
        let shown = stats.hourlySpends
        let maxVal = shown.map(\.avgAmount).max() ?? 1

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("avg spend by hour")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(shown) { item in
                    BarMark(
                        x: .value("Hour", item.hour),
                        y: .value("Spend", item.avgAmount)
                    )
                    .foregroundStyle(barColor(item.avgAmount, max: maxVal))
                    .cornerRadius(2)
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            let display = h % 12 == 0 ? 12 : h % 12
                            Text("\(display)\(h < 12 ? "am" : "pm")").font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("$\(Int(v))").font(.system(size: 9))
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartPlotStyle { $0.clipped() }
            .frame(height: 80)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
    }

    private func barColor(_ amount: Double, max: Double) -> Color {
        let frac = max > 0 ? amount / max : 0
        if frac >= 0.8 { return .usageCrimson.opacity(0.8) }
        if frac >= 0.5 { return .usageAmber.opacity(0.8) }
        return .usageSapphire.opacity(0.8)
    }

    // MARK: - Stat tile

    @ViewBuilder
    private func statTile(
        icon: String, iconColor: Color,
        label: String,
        value: String?,
        sub: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value ?? "—")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(value != nil ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
    }

    private func rateString(_ rate: Double) -> String {
        "$\(String(format: "%.2f", rate))/hr"
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 12 ? "am" : "pm")"
    }
}
