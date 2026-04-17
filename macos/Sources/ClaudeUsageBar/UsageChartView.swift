import SwiftUI
import Charts

struct UsageChartView: View {
    @ObservedObject var historyService: UsageHistoryService
    var monthlyLimit: Double?
    @State private var selectedRange: TimeRange = .day1
    @State private var hoverDate: Date?
    @AppStorage("menuBarMode") private var menuBarMode = "extraUsage"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let points = historyService.downsampledPoints(for: selectedRange)

            if points.isEmpty {
                Text("No history data yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else if menuBarMode == "extraUsage" {
                extraChartView(points: points)
            } else {
                rateLimitsChartView(points: points)
            }
        }
    }

    // MARK: - Rate Limits Chart (5h / 7d %)

    @ViewBuilder
    private func rateLimitsChartView(points: [UsageDataPoint]) -> some View {
        let interpolated = hoverDate.flatMap {
            UsageChartInterpolation.interpolate(at: $0, in: points)
        }

        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Time", point.timestamp), y: .value("Usage", point.pct5h * 100))
                    .foregroundStyle(by: .value("Window", "5h"))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.timestamp), y: .value("Usage", point.pct7d * 100))
                    .foregroundStyle(by: .value("Window", "7d"))
                    .interpolationMethod(.catmullRom)
            }
            if let iv = interpolated {
                RuleMark(x: .value("Selected", iv.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", iv.date), y: .value("Usage", iv.pct5h * 100))
                    .foregroundStyle(.blue).symbolSize(24)
                PointMark(x: .value("Time", iv.date), y: .value("Usage", iv.pct7d * 100))
                    .foregroundStyle(.orange).symbolSize(24)
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text("\(v)%").font(.caption2) }
                }
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: xAxisFormat).font(.caption2)
                AxisGridLine()
            }
        }
        .chartForegroundStyleScale(["5h": Color.blue, "7d": Color.orange])
        .chartLegend(.visible)
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in hoverOverlay(proxy: proxy) }
        .overlay(alignment: .top) {
            if let iv = interpolated {
                rateLimitsTooltip(date: iv.date, pct5h: iv.pct5h, pct7d: iv.pct7d)
            }
        }
        .frame(height: 120)
        .padding(.top, 4)
    }

    // MARK: - Extra Usage Chart ($)

    @ViewBuilder
    private func extraChartView(points: [UsageDataPoint]) -> some View {
        let hasCredits = points.contains { $0.usedCredits != nil }
        let maxY: Double = {
            if let limit = monthlyLimit, limit > 0 { return limit }
            return points.compactMap(\.usedCredits).max().map { $0 * 1.1 } ?? 100
        }()
        let interpolated = hoverDate.flatMap {
            UsageChartInterpolation.interpolate(at: $0, in: points)
        }

        // Gradient fill color based on the latest data point's pace status
        let areaColor: Color = {
            guard hasCredits, let limit = monthlyLimit, limit > 0 else { return .blue }
            let latestUsed = points.compactMap(\.usedCredits).last ?? 0
            let pace = BillingPace.paceAmount(limit: limit)
            let excess = latestUsed - pace
            if excess <= 0 { return .green }
            if excess <= limit * 0.05 { return .yellow }
            return .red
        }()

        Chart {
            // Gradient area fill (drawn first, behind the line)
            ForEach(points) { point in
                let y = hasCredits ? (point.usedCredits ?? 0) : point.pctExtra * 100
                AreaMark(
                    x: .value("Time", point.timestamp),
                    yStart: .value("Base", 0.0),
                    yEnd: .value("Used", y)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(
                    colors: [areaColor.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }

            // Line with per-segment pace status coloring
            ForEach(points) { point in
                let y = hasCredits ? (point.usedCredits ?? 0) : point.pctExtra * 100
                let segmentStatus: String = {
                    guard hasCredits, let limit = monthlyLimit, limit > 0 else { return "blue" }
                    let pace = BillingPace.paceAmount(limit: limit, now: point.timestamp)
                    let excess = y - pace
                    if excess <= 0 { return "green" }
                    if excess <= limit * 0.05 { return "yellow" }
                    return "red"
                }()
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Used", y),
                    series: .value("S", "actual")
                )
                .foregroundStyle(by: .value("ps", segmentStatus))
                .interpolationMethod(.catmullRom)
            }

            // Sawtooth pace guide — separate series per billing period
            if let limit = monthlyLimit, hasCredits {
                let windowStart = Date.now.addingTimeInterval(-selectedRange.interval)
                let windowEnd = Date.now
                let segments = BillingPace.paceLineSegments(limit: limit, from: windowStart, to: windowEnd)

                ForEach(segments, id: \.idx) { seg in
                    LineMark(
                        x: .value("Time", seg.start),
                        y: .value("Used", seg.startVal),
                        series: .value("S", "pace-\(seg.idx)")
                    )
                    .foregroundStyle(.gray.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Time", seg.end),
                        y: .value("Used", seg.endVal),
                        series: .value("S", "pace-\(seg.idx)")
                    )
                    .foregroundStyle(.gray.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.linear)
                }

                RuleMark(y: .value("Limit", limit))
                    .foregroundStyle(.red.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if let iv = interpolated {
                RuleMark(x: .value("Selected", iv.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                let y = hasCredits ? (iv.usedCredits ?? 0) : iv.pctExtra * 100
                PointMark(x: .value("Time", iv.date), y: .value("Used", y))
                    .foregroundStyle(.blue).symbolSize(24)
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartYScale(domain: 0...maxY)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if hasCredits, let v = value.as(Double.self) {
                        Text("$\(Int(v))").font(.caption2)
                    } else if let v = value.as(Double.self) {
                        Text("\(Int(v))%").font(.caption2)
                    }
                }
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: xAxisFormat).font(.caption2)
                AxisGridLine()
            }
        }
        .chartForegroundStyleScale([
            "green": Color.green,
            "yellow": Color.yellow,
            "red": Color.red,
            "blue": Color.blue
        ])
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in hoverOverlay(proxy: proxy) }
        .overlay(alignment: .top) {
            if let iv = interpolated {
                extraTooltip(date: iv.date, usedCredits: iv.usedCredits, pctExtra: iv.pctExtra, hasCredits: hasCredits)
            }
        }
        .frame(height: 120)
        .padding(.top, 4)
    }

    // MARK: - Shared hover overlay

    @ViewBuilder
    private func hoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let plotOrigin = geo[proxy.plotFrame!].origin
                        let x = location.x - plotOrigin.x
                        if let date: Date = proxy.value(atX: x) { hoverDate = date }
                    case .ended:
                        hoverDate = nil
                    }
                }
        }
    }

    // MARK: - Tooltips

    @ViewBuilder
    private func rateLimitsTooltip(date: Date, pct5h: Double, pct7d: Double) -> some View {
        VStack(spacing: 2) {
            Text(date, format: tooltipDateFormat).font(.system(size: 9)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Label("\(Int(round(pct5h * 100)))%", systemImage: "circle.fill")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.blue)
                Label("\(Int(round(pct7d * 100)))%", systemImage: "circle.fill")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func extraTooltip(date: Date, usedCredits: Double?, pctExtra: Double, hasCredits: Bool) -> some View {
        VStack(spacing: 2) {
            Text(date, format: tooltipDateFormat).font(.system(size: 9)).foregroundStyle(.secondary)
            if hasCredits, let credits = usedCredits {
                Text("$\(String(format: "%.2f", credits))")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.blue)
            } else {
                Text("\(Int(round(pctExtra * 100)))%")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Formatting

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .hour1: return .dateTime.hour().minute()
        case .hour6, .day1: return .dateTime.hour()
        case .day7: return .dateTime.weekday(.abbreviated)
        case .day30: return .dateTime.day().month(.abbreviated)
        }
    }

    private var tooltipDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .hour1, .hour6, .day1: return .dateTime.hour().minute()
        case .day7: return .dateTime.weekday(.abbreviated).hour().minute()
        case .day30: return .dateTime.month(.abbreviated).day().hour()
        }
    }
}

// MARK: - Interpolation

struct UsageChartInterpolatedValues {
    let date: Date
    let pct5h: Double
    let pct7d: Double
    let pctExtra: Double
    let usedCredits: Double?
}

enum UsageChartInterpolation {
    static func interpolate(at date: Date, in points: [UsageDataPoint]) -> UsageChartInterpolatedValues? {
        guard points.count >= 2 else { return nil }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }

        if date < sorted.first!.timestamp || date > sorted.last!.timestamp {
            return UsageChartInterpolatedValues(date: date, pct5h: 0, pct7d: 0, pctExtra: 0, usedCredits: nil)
        }

        for i in 0..<(sorted.count - 1) {
            guard date >= sorted[i].timestamp && date <= sorted[i + 1].timestamp else { continue }
            let span = sorted[i + 1].timestamp.timeIntervalSince(sorted[i].timestamp)
            let t = span > 0 ? date.timeIntervalSince(sorted[i].timestamp) / span : 0
            let i0 = max(0, i - 1), i3 = min(sorted.count - 1, i + 2)

            let pct5h = clamp(catmullRom(sorted[i0].pct5h, sorted[i].pct5h, sorted[i+1].pct5h, sorted[i3].pct5h, t: t))
            let pct7d = clamp(catmullRom(sorted[i0].pct7d, sorted[i].pct7d, sorted[i+1].pct7d, sorted[i3].pct7d, t: t))
            let pctExtra = clamp(catmullRom(sorted[i0].pctExtra, sorted[i].pctExtra, sorted[i+1].pctExtra, sorted[i3].pctExtra, t: t))

            let credits: Double? = {
                let c0 = sorted[i0].usedCredits, c1 = sorted[i].usedCredits
                let c2 = sorted[i+1].usedCredits, c3 = sorted[i3].usedCredits
                guard let v1 = c1, let v2 = c2 else { return nil }
                return catmullRom(c0 ?? v1, v1, v2, c3 ?? v2, t: t)
            }()

            return UsageChartInterpolatedValues(date: date, pct5h: pct5h, pct7d: pct7d, pctExtra: pctExtra, usedCredits: credits)
        }
        return nil
    }

    private static func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
