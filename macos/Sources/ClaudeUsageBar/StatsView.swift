import SwiftUI

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
