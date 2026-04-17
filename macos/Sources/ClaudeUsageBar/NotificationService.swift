import Foundation
@preconcurrency import UserNotifications

struct ThresholdAlert: Equatable {
    let window: String
    let pct: Int
}

/// Pure logic: returns which threshold alerts should fire given a state transition.
func crossedThresholds(
    threshold5h: Int,
    threshold7d: Int,
    thresholdExtra: Int,
    previous5h: Double,
    previous7d: Double,
    previousUsedCredits: Double?,
    current5h: Double,
    current7d: Double,
    usedCredits: Double?,
    monthlyLimit: Double?
) -> [ThresholdAlert] {
    var alerts = [ThresholdAlert]()

    if threshold5h > 0 {
        let t = Double(threshold5h)
        if current5h >= t && previous5h < t {
            alerts.append(ThresholdAlert(window: "5-hour", pct: Int(round(current5h))))
        }
    }

    if threshold7d > 0 {
        let t = Double(threshold7d)
        if current7d >= t && previous7d < t {
            alerts.append(ThresholdAlert(window: "7-day", pct: Int(round(current7d))))
        }
    }

    if thresholdExtra > 0, let usedCredits, let monthlyLimit, monthlyLimit > 0 {
        let pace = BillingPace.paceAmount(limit: monthlyLimit)
        let trigger = pace + monthlyLimit * Double(thresholdExtra) / 100.0
        if usedCredits >= trigger && (previousUsedCredits ?? 0) < trigger {
            let pct = Int(round(usedCredits / monthlyLimit * 100))
            alerts.append(ThresholdAlert(window: "Extra usage", pct: pct))
        }
    }

    return alerts
}

private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
class NotificationService: ObservableObject {
    /// 0 = off, 5–100 = alert when window reaches this %.
    @Published private(set) var threshold5h: Int
    @Published private(set) var threshold7d: Int
    @Published private(set) var thresholdExtra: Int

    private var previousPct5h: Double?
    private var previousPct7d: Double?
    private var previousUsedCredits: Double?
    private let delegate = NotificationDelegate()

    init() {
        threshold5h = Self.load("notificationThreshold5h")
        threshold7d = Self.load("notificationThreshold7d")
        thresholdExtra = Self.load("notificationThresholdExtra")
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = delegate
        }
    }

    func setThreshold5h(_ value: Int) {
        threshold5h = clamp(value)
        UserDefaults.standard.set(threshold5h, forKey: "notificationThreshold5h")
        previousPct5h = nil
        if threshold5h > 0 { requestPermission() }
    }

    func setThreshold7d(_ value: Int) {
        threshold7d = clamp(value)
        UserDefaults.standard.set(threshold7d, forKey: "notificationThreshold7d")
        previousPct7d = nil
        if threshold7d > 0 { requestPermission() }
    }

    func setThresholdExtra(_ value: Int) {
        thresholdExtra = clamp(value)
        UserDefaults.standard.set(thresholdExtra, forKey: "notificationThresholdExtra")
        previousUsedCredits = nil
        if thresholdExtra > 0 { requestPermission() }
    }

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkAndNotify(pct5h: Double, pct7d: Double, usedCredits: Double?, monthlyLimit: Double?) {
        let current5h = pct5h * 100
        let current7d = pct7d * 100

        let prev5h = previousPct5h ?? 0
        let prev7d = previousPct7d ?? 0

        defer {
            previousPct5h = current5h
            previousPct7d = current7d
            previousUsedCredits = usedCredits
        }

        let alerts = crossedThresholds(
            threshold5h: threshold5h,
            threshold7d: threshold7d,
            thresholdExtra: thresholdExtra,
            previous5h: prev5h,
            previous7d: prev7d,
            previousUsedCredits: previousUsedCredits,
            current5h: current5h,
            current7d: current7d,
            usedCredits: usedCredits,
            monthlyLimit: monthlyLimit
        )

        for alert in alerts {
            sendNotification(window: alert.window, pct: alert.pct)
        }
    }

    private func sendNotification(window: String, pct: Int) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Notification] \(window) usage has reached \(pct)% (no bundle – skipped)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Claude Usage"
        content.body = "\(window) usage has reached \(pct)%"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage-\(window)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to deliver: \(error)")
            } else {
                print("[Notification] Delivered: \(window) at \(pct)%")
            }
        }
    }

    private func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    private static func load(_ key: String) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return max(0, min(100, value))
    }
}
