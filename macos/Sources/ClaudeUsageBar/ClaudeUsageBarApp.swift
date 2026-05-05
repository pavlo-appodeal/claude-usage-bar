import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()
    @AppStorage("menuBarMode") private var menuBarMode = "extraUsage"
    @AppStorage("menuBarExtraLabel") private var menuBarExtraLabel = "percent"

    private var paceSwiftUIColor: Color {
        switch extraPaceStatus {
        case .wellUnder:    return Color(NSColor.systemGreen)
        case .underPace:    return Color(hue: 0.26, saturation: 0.58, brightness: 0.88)
        case .nearPace:     return Color(NSColor.systemYellow)
        case .slightlyOver: return Color(hue: 0.12, saturation: 0.62, brightness: 0.96)
        case .elevated:     return Color(NSColor.systemOrange)
        case .over:         return Color(NSColor.systemRed)
        }
    }

    private var extraPaceStatus: PaceStatus {
        let used = service.usage?.extraUsage?.usedCreditsAmount ?? service.lastKnownUsedCredits
        let limit = service.usage?.extraUsage?.monthlyLimitAmount ?? service.lastKnownMonthlyLimit
        guard let used, let limit else { return .wellUnder }
        return BillingPace.status(used: used, limit: limit)
    }

    private var extraLabel: String {
        let used = service.usage?.extraUsage?.usedCreditsAmount ?? service.lastKnownUsedCredits
        let limit = service.usage?.extraUsage?.monthlyLimitAmount ?? service.lastKnownMonthlyLimit
        switch menuBarExtraLabel {
        case "percent":
            return "\(Int(round(service.pctExtra * 100)))%"
        case "used":
            if let used { return "$\(Int(used))" }
            return "$"
        case "remaining":
            if let used, let limit { return "$\(Int(limit - used))" }
            return "$"
        default:
            return "$"
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                service: service,
                historyService: historyService,
                notificationService: notificationService,
                appUpdater: appUpdater
            )
        } label: {
            Image(nsImage: service.isAuthenticated
                ? (menuBarMode == "extraUsage"
                    ? renderExtraLabelIcon(label: extraLabel)
                    : renderIcon(pct5h: service.pct5h, pct7d: service.pct7d))
                : renderUnauthenticatedIcon()
            )
            .overlay(alignment: .bottom) {
                if service.isAuthenticated && menuBarMode == "extraUsage" {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                            Capsule()
                                .fill(paceSwiftUIColor)
                                .frame(
                                    width: max(g.size.width * CGFloat(min(max(service.pctExtra, 0), 1)), 2),
                                    height: 2
                                )
                        }
                    }
                    .frame(height: 2)
                }
            }
            .task {
                if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                    UserDefaults.standard.set(true, forKey: "setupComplete")
                }
                historyService.loadHistory()
                service.historyService = historyService
                service.notificationService = notificationService
                service.startPolling()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowContent(
                service: service,
                notificationService: notificationService
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
