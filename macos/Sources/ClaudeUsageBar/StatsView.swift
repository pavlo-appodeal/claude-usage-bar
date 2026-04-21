import SwiftUI
import Charts

struct StatsView: View {
    let stats: UsageStats

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
                        value: stats.peakHourlyRate.map { rateString($0) }
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

                // Bar chart — per-day spend
                dailyChart

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
        }
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
