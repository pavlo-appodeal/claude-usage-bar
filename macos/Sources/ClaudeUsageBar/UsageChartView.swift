import SwiftUI
import Charts

struct UsageChartView: View {
    @ObservedObject var historyService: UsageHistoryService
    var monthlyLimit: Double?
    @AppStorage("selectedChartRange") private var selectedRange: TimeRange = .billingCycle
    @State private var hoverDate: Date?
    @AppStorage("menuBarMode") private var menuBarMode = "extraUsage"
    @AppStorage("workdaysOnly") private var workdaysOnly = false

    private var chartStartDate: Date {
        if selectedRange == .today {
            let todayStart = Calendar.current.startOfDay(for: Date())
            let firstToday = historyService.history.dataPoints
                .filter { $0.timestamp >= todayStart }
                .map(\.timestamp)
                .min()
            if let first = firstToday {
                return first.addingTimeInterval(-15 * 60)
            } else {
                return Date().addingTimeInterval(-60)
            }
        }
        let earliest = historyService.history.dataPoints.map(\.timestamp).min()
        return selectedRange.startDate(earliestPoint: earliest)
    }

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
        .chartXScale(domain: chartStartDate...Date.now)
        .chartYScale(domain: {
            guard selectedRange == .today else { return 0.0...100.0 }
            let vals = points.flatMap { [$0.pct5h * 100, $0.pct7d * 100] }
            guard let lo = vals.min(), let hi = vals.max() else { return 0.0...100.0 }
            let minY = max(0.0, floor(lo / 10) * 10)
            let maxY = min(100.0, ceil(hi / 10) * 10)
            return minY...maxY
        }())
        .chartYAxis {
            if selectedRange == .today {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))%").font(.caption2) }
                    }
                    AxisGridLine()
                }
            } else {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text("\(v)%").font(.caption2) }
                    }
                    AxisGridLine()
                }
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
        let localCycleSummary: UsageCycleSummary? = {
            guard hasCredits, let limit = monthlyLimit, limit > 0 else { return nil }
            return currentCycleSummary(points: historyService.history.dataPoints, monthlyLimit: limit, workdaysOnly: workdaysOnly)
        }()
        let (minY, maxY): (Double, Double) = {
            if selectedRange == .today {
                let vals = points.compactMap { p -> Double? in
                    hasCredits ? p.usedCredits : (p.pctExtra > 0 ? p.pctExtra * 100 : nil)
                }
                if let lo = vals.min(), let hi = vals.max() {
                    let limit = monthlyLimit ?? Double.greatestFiniteMagnitude
                    let minRounded = max(0, floor(lo / 10) * 10)
                    let maxRounded = min(limit, ceil(hi / 10) * 10)
                    return (minRounded, maxRounded)
                }
            }
            if let limit = monthlyLimit, limit > 0 { return (0, limit) }
            let fallback = points.compactMap(\.usedCredits).max().map { $0 * 1.1 } ?? 100
            return (0, fallback)
        }()
        let interpolated = hoverDate.flatMap {
            UsageChartInterpolation.interpolate(at: $0, in: points)
        }

        let emerald  = Color.usageEmerald
        let amber    = Color.usageAmber
        let crimson  = Color.usageCrimson
        let sapphire = Color.usageSapphire

        let effectivePoints: [UsageDataPoint] = {
            var pts: [UsageDataPoint] = hasCredits ? points.filter { $0.usedCredits != nil } : points
            guard let first = pts.first, first.timestamp.timeIntervalSince(chartStartDate) > 300 else {
                return pts
            }
            // Inject a start-of-range anchor using the last recorded value from the
            // current billing cycle that falls before chartStartDate. This draws a flat
            // line from the range start to the first real point — but only when we
            // actually have prior data. If this is the very first recording ever (or the
            // first in this billing cycle), we leave the chart starting at the real point
            // so no fabricated line is drawn from an unobserved value.
            let billingCycleStart = BillingPace.billingStart()
            let prior = historyService.history.dataPoints
                .filter { $0.timestamp < chartStartDate && $0.timestamp >= billingCycleStart && $0.usedCredits != nil }
                .max(by: { $0.timestamp < $1.timestamp })
            guard let prior else { return pts }
            pts.insert(UsageDataPoint(
                timestamp: chartStartDate,
                pct5h: prior.pct5h, pct7d: prior.pct7d,
                pctExtra: prior.pctExtra, usedCredits: prior.usedCredits
            ), at: 0)
            return pts
        }()

        // Find the X-fraction where data first crosses from below-pace to above-pace.
        // This anchors the amber stop so the area gradient matches the line coloring.
        let paceXFrac: Double = {
            guard hasCredits, let limit = monthlyLimit, limit > 0 else { return 0.5 }
            let sorted = effectivePoints.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= 2 else { return 0.5 }
            let chartEnd: Date = selectedRange == .billingCycle ? BillingPace.billingEnd() : Date.now
            let chartTotalT = chartStartDate.distance(to: chartEnd)
            guard chartTotalT > 0 else { return 0.5 }
            for i in 0..<sorted.count - 1 {
                let y0 = sorted[i].usedCredits     ?? 0
                let y1 = sorted[i + 1].usedCredits ?? 0
                let p0 = BillingPace.paceAmount(limit: limit, now: sorted[i].timestamp, workdaysOnly: workdaysOnly)
                let p1 = BillingPace.paceAmount(limit: limit, now: sorted[i + 1].timestamp, workdaysOnly: workdaysOnly)
                let e0 = y0 - p0; let e1 = y1 - p1
                if e0 <= 0 && e1 > 0 {
                    let frac = e1 > e0 ? (-e0) / (e1 - e0) : 0.5
                    let crossAbsT = chartStartDate.distance(to: sorted[i].timestamp)
                                  + sorted[i].timestamp.distance(to: sorted[i + 1].timestamp) * frac
                    return min(0.98, max(0.02, crossAbsT / chartTotalT))
                }
            }
            // Never crossed: all above pace → push amber to very start so gradient is mostly red
            if let first = sorted.first, (first.usedCredits ?? 0) > BillingPace.paceAmount(limit: limit, now: first.timestamp, workdaysOnly: workdaysOnly) {
                return 0.02
            }
            return 0.98  // all below pace → gradient stays mostly green
        }()

        // Area fill: gradient anchored at the pace-crossover X position, matching line color semantics.
        let areaGradient = LinearGradient(
            stops: [
                .init(color: (hasCredits ? emerald : sapphire).opacity(0.22), location: 0.0),
                .init(color: (hasCredits ? amber   : sapphire).opacity(0.12), location: paceXFrac),
                .init(color: (hasCredits ? crimson : sapphire).opacity(0.26), location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )

        let yValue: (UsageDataPoint) -> Double = { p in
            hasCredits ? (p.usedCredits ?? 0) : p.pctExtra * 100
        }

        let dotColor: (UsageDataPoint) -> Color = { p in
            guard hasCredits, let limit = monthlyLimit, limit > 0 else { return sapphire }
            let y = p.usedCredits ?? 0
            let excess = y - BillingPace.paceAmount(limit: limit, now: p.timestamp, workdaysOnly: workdaysOnly)
            if excess <= 0 { return emerald }
            if excess <= limit * 0.05 { return amber }
            return crimson
        }

        // Projected trajectory: last actual point → cycle end
        // Use full history for projection so short views still get multi-day data
        let allPoints = historyService.history.dataPoints
        let projectionLine: (fromY: Double, toY: Double, color: Color)? = {
            guard hasCredits,
                  let limit = monthlyLimit, limit > 0,
                  let lastPt = effectivePoints.last,
                  let lastCredits = lastPt.usedCredits,
                  let s = currentCycleSummary(points: allPoints, monthlyLimit: limit, workdaysOnly: workdaysOnly),
                  let projRem = s.projectedEndRemaining
            else { return nil }
            // Cap projected end spend at the budget limit so the line stays in-chart
            let projEndSpend = min(max(0, limit - projRem), limit)
            let color: Color = projRem < -0.5 ? crimson : (projRem > 0.5 ? emerald : amber)
            return (fromY: lastCredits, toY: projEndSpend, color: color)
        }()

        // Extend X domain to cycle end only in billing cycle view
        let rightBoundary: Date = {
            guard projectionLine != nil, selectedRange == .billingCycle
            else { return Date.now }
            return BillingPace.billingEnd()
        }()

        Chart {
            // Area fill — gradient maps Y position to color
            ForEach(effectivePoints) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    yStart: .value("Base", 0.0),
                    yEnd: .value("Used", yValue(point)),
                    series: .value("Series", "area")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(areaGradient)
            }

            // Glow — soft wide halo
            ForEach(effectivePoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Used", yValue(point)),
                    series: .value("Series", "glow")
                )
                .foregroundStyle(.white.opacity(0.06))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            }

            // Latest point — small hollow ring only
            if let last = effectivePoints.last {
                PointMark(x: .value("Time", last.timestamp), y: .value("Used", yValue(last)))
                    .foregroundStyle(dotColor(last))
                    .symbolSize(26)
                PointMark(x: .value("Time", last.timestamp), y: .value("Used", yValue(last)))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .symbolSize(10)
            }

            // Sawtooth pace guide — quieter than the actual line
            if let limit = monthlyLimit, hasCredits {
                let windowStart = chartStartDate
                let windowEnd = rightBoundary
                let segments = BillingPace.paceLineSegments(limit: limit, from: windowStart, to: windowEnd, workdaysOnly: workdaysOnly)

                ForEach(segments, id: \.idx) { seg in
                    LineMark(
                        x: .value("Time", seg.start),
                        y: .value("Used", seg.startVal),
                        series: .value("S", "pace-\(seg.idx)")
                    )
                    .foregroundStyle(.white.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [5, 5]))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Time", seg.end),
                        y: .value("Used", seg.endVal),
                        series: .value("S", "pace-\(seg.idx)")
                    )
                    .foregroundStyle(.white.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [5, 5]))
                    .interpolationMethod(.linear)
                }

                RuleMark(y: .value("Limit", limit))
                    .foregroundStyle(Color.red.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
            }

            // Projected trajectory — dashed from last actual point to cycle end
            if let proj = projectionLine, let lastPt = effectivePoints.last {
                LineMark(
                    x: .value("Time", lastPt.timestamp),
                    y: .value("Used", proj.fromY),
                    series: .value("S", "proj")
                )
                .foregroundStyle(proj.color.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
                .interpolationMethod(.linear)

                LineMark(
                    x: .value("Time", BillingPace.billingEnd()),
                    y: .value("Used", proj.toY),
                    series: .value("S", "proj")
                )
                .foregroundStyle(proj.color.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))
                .interpolationMethod(.linear)
            }

            if let iv = interpolated {
                RuleMark(x: .value("Selected", iv.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                let y = hasCredits ? (iv.usedCredits ?? 0) : iv.pctExtra * 100
                let hoverColor: Color = {
                    guard hasCredits, let limit = monthlyLimit, limit > 0 else { return sapphire }
                    let excess = y - BillingPace.paceAmount(limit: limit, now: iv.date, workdaysOnly: workdaysOnly)
                    if excess <= 0 { return emerald }
                    if excess <= limit * 0.05 { return amber }
                    return crimson
                }()
                PointMark(x: .value("Time", iv.date), y: .value("Used", y))
                    .foregroundStyle(hoverColor).symbolSize(20)
            }
        }
        .chartXScale(domain: chartStartDate...rightBoundary)
        .chartYScale(domain: minY...maxY)
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
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]

                    // Manual domain-fraction positioning: avoids any dependency on
                    // proxy.position(forX/Y:) whose behaviour in draw-phase closures is
                    // unreliable. The explicit chartXScale/chartYScale domains map linearly
                    // onto the plot frame, so this is exact.
                    let xStart = chartStartDate
                    let xEnd   = rightBoundary
                    let totalXSec = xEnd.timeIntervalSince(xStart)
                    // screenPts: (screenPoint, dataValue, paceAtTimestamp)
                    let screenPts: [(CGPoint, Double, Double)] = totalXSec > 0 ? effectivePoints.compactMap { dp in
                        let xFrac = dp.timestamp.timeIntervalSince(xStart) / totalXSec
                        let yFrac = (maxY - minY) > 0 ? (yValue(dp) - minY) / (maxY - minY) : 0
                        guard xFrac > -0.01, xFrac < 1.01 else { return nil }
                        let sx = frame.minX + xFrac * frame.width
                        let sy = frame.maxY - yFrac * frame.height
                        let pace: Double = {
                            guard hasCredits, let lim = monthlyLimit, lim > 0 else { return 0.0 }
                            return BillingPace.paceAmount(limit: lim, now: dp.timestamp, workdaysOnly: workdaysOnly)
                        }()
                        return (CGPoint(x: sx, y: sy), yValue(dp), pace)
                    } : []

                    Canvas { ctx, _ in
                        guard screenPts.count >= 2 else { return }
                        ctx.clip(to: Path(frame))
                        for i in 0..<screenPts.count - 1 {
                            let c: Color
                            if !hasCredits {
                                c = sapphire
                            } else {
                                let actualAvg = (screenPts[i].1 + screenPts[i + 1].1) / 2
                                let paceAvg   = (screenPts[i].2 + screenPts[i + 1].2) / 2
                                let excess    = actualAvg - paceAvg
                                let scale     = (monthlyLimit ?? maxY) * 0.25  // ±25% of limit = full color range
                                // t: 0 = well below pace (emerald), 0.5 = at pace (amber), 1 = well above (crimson)
                                let t = min(1, max(0, excess / scale * 0.5 + 0.5))
                                if t <= 0.5 {
                                    let tt = t * 2
                                    c = Color(hue: 0.40 - 0.28 * tt, saturation: 0.58 + 0.04 * tt, brightness: 0.88 + 0.08 * tt)
                                } else {
                                    let tt = (t - 0.5) * 2
                                    c = Color(hue: 0.12 - 0.11 * tt, saturation: 0.62 - 0.04 * tt, brightness: 0.96 - 0.03 * tt)
                                }
                            }
                            var p = Path()
                            p.move(to: screenPts[i].0)
                            p.addLine(to: screenPts[i + 1].0)
                            ctx.stroke(p, with: .color(c),
                                       style: StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                    // Pill badge — bottom-right corner, billing cycle view only, hidden during hover
                    if hoverDate == nil,
                       selectedRange == .billingCycle,
                       let s = localCycleSummary,
                       let text = s.trajectoryText {
                        let limit = monthlyLimit ?? 0
                        let badgeColor: Color = s.trajectoryIsOverBudget ? crimson
                            : ((s.projectedEndRemaining ?? 0) > limit * 0.05 ? emerald : amber)
                        Text(text)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.60), in: Capsule())
                            .overlay(Capsule().stroke(badgeColor.opacity(0.45), lineWidth: 1))
                            .fixedSize()
                            .padding(.trailing, 6)
                            .padding(.bottom, 6)
                            .frame(width: frame.width, height: frame.height, alignment: .bottomTrailing)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }

                // Hover interaction
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
        case .today:        return .dateTime.hour()
        case .billingCycle: return .dateTime.day().month(.abbreviated)
        case .months3:      return .dateTime.month(.abbreviated).day()
        case .allTime:      return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private var tooltipDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .today:        return .dateTime.hour().minute()
        case .billingCycle: return .dateTime.month(.abbreviated).day().hour()
        case .months3:      return .dateTime.month(.abbreviated).day()
        case .allTime:      return .dateTime.month(.abbreviated).day().year(.twoDigits)
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
    static func interpolateValues(at date: Date, in points: [UsageDataPoint]) -> UsageChartInterpolatedValues? {
        interpolate(at: date, in: points)
    }

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

    static func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
