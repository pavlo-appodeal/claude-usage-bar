import SwiftUI

extension Color {
    /// Green — on track / low usage
    static let usageEmerald  = Color(hue: 0.40, saturation: 0.58, brightness: 0.88)
    /// Yellow-orange — approaching limit / mid usage
    static let usageAmber    = Color(hue: 0.12, saturation: 0.62, brightness: 0.96)
    /// Red — over budget / high usage
    static let usageCrimson  = Color(hue: 0.01, saturation: 0.58, brightness: 0.93)
    /// Blue — rate-limit percentage display
    static let usageSapphire = Color(hue: 0.60, saturation: 0.60, brightness: 0.92)

    /// Map a 0–1 utilization fraction to the shared status color ramp.
    static func usageStatus(fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return .usageEmerald
        case 0.60..<0.80: return .usageAmber
        default: return .usageCrimson
        }
    }
}
