import SwiftUI

extension Color {
    /// Green — well under pace
    static let usageEmerald  = Color(hue: 0.40, saturation: 0.58, brightness: 0.88)
    /// Lime — slightly under pace
    static let usageLime     = Color(hue: 0.26, saturation: 0.58, brightness: 0.88)
    /// Yellow — near pace
    static let usageYellow   = Color(hue: 0.16, saturation: 0.65, brightness: 0.97)
    /// Amber — slightly over pace
    static let usageAmber    = Color(hue: 0.12, saturation: 0.62, brightness: 0.96)
    /// Orange — elevated over pace
    static let usageOrange   = Color(hue: 0.07, saturation: 0.62, brightness: 0.96)
    /// Red — over budget
    static let usageCrimson  = Color(hue: 0.01, saturation: 0.58, brightness: 0.93)
    /// Blue — rate-limit percentage display
    static let usageSapphire = Color(hue: 0.60, saturation: 0.60, brightness: 0.92)

    static func forPaceStatus(_ status: PaceStatus) -> Color {
        switch status {
        case .wellUnder:    return .usageEmerald
        case .underPace:    return .usageLime
        case .nearPace:     return .usageYellow
        case .slightlyOver: return .usageAmber
        case .elevated:     return .usageOrange
        case .over:         return .usageCrimson
        }
    }

    /// Map a 0–1 utilization fraction to the shared status color ramp.
    static func usageStatus(fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return .usageEmerald
        case 0.60..<0.80: return .usageAmber
        default: return .usageCrimson
        }
    }
}
