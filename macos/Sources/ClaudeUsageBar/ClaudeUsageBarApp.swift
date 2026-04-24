import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()
    @AppStorage("menuBarMode") private var menuBarMode = "extraUsage"
    @AppStorage("menuBarExtraLabel") private var menuBarExtraLabel = "percent"

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
                    ? renderExtraUsageIcon(pct: service.pctExtra, label: extraLabel, paceStatus: extraPaceStatus)
                    : renderIcon(pct5h: service.pct5h, pct7d: service.pct7d))
                : renderUnauthenticatedIcon()
            )
                .task {
                    // Auto-mark existing users as setup-complete
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
