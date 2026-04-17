import Foundation

struct UsageDataPoint: Identifiable {
    var id: UUID
    let timestamp: Date
    let pct5h: Double
    let pct7d: Double
    let pctExtra: Double
    let usedCredits: Double?  // dollars

    init(timestamp: Date = Date(), pct5h: Double, pct7d: Double, pctExtra: Double = 0, usedCredits: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.pct5h = pct5h
        self.pct7d = pct7d
        self.pctExtra = pctExtra
        self.usedCredits = usedCredits
    }
}

extension UsageDataPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, pct5h, pct7d, pctExtra, usedCredits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        pct5h = try c.decode(Double.self, forKey: .pct5h)
        pct7d = try c.decode(Double.self, forKey: .pct7d)
        pctExtra = try c.decodeIfPresent(Double.self, forKey: .pctExtra) ?? 0
        usedCredits = try c.decodeIfPresent(Double.self, forKey: .usedCredits)
    }
}

struct UsageHistory: Codable {
    var dataPoints: [UsageDataPoint] = []
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today        = "Today"
    case billingCycle = "Cycle"
    case months3      = "3M"
    case allTime      = "All"

    var id: String { rawValue }

    func startDate(earliestPoint: Date? = nil) -> Date {
        switch self {
        case .today:        return Calendar.current.startOfDay(for: Date())
        case .billingCycle: return BillingPace.billingStart()
        case .months3:      return Date().addingTimeInterval(-90 * 86400)
        case .allTime:      return earliestPoint ?? Date().addingTimeInterval(-365 * 86400)
        }
    }

    var targetPointCount: Int {
        switch self {
        case .today:        return 200
        case .billingCycle: return 200
        case .months3:      return 200
        case .allTime:      return 300
        }
    }
}
