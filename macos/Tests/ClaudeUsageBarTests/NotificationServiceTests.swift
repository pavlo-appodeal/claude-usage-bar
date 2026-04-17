import XCTest
@testable import ClaudeUsageBar

final class NotificationServiceTests: XCTestCase {
    func testNoAlertsWhenAllOff() {
        let alerts = crossedThresholds(
            threshold5h: 0, threshold7d: 0, thresholdExtra: 0,
            previous5h: 40, previous7d: 30, previousUsedCredits: nil,
            current5h: 90, current7d: 85, usedCredits: nil, monthlyLimit: nil
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testOnly5hFires() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 0, thresholdExtra: 0,
            previous5h: 70, previous7d: 50, previousUsedCredits: nil,
            current5h: 85, current7d: 90, usedCredits: nil, monthlyLimit: nil
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "5-hour", pct: 85)])
    }

    func testOnly7dFires() {
        let alerts = crossedThresholds(
            threshold5h: 0, threshold7d: 80, thresholdExtra: 0,
            previous5h: 70, previous7d: 70, previousUsedCredits: nil,
            current5h: 85, current7d: 85, usedCredits: nil, monthlyLimit: nil
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "7-day", pct: 85)])
    }

    func testOnlyExtraFires() {
        // previousUsedCredits=0 is always below trigger (pace + limit*threshold/100 >= 50)
        // usedCredits=200 with limit=100 is always above trigger (<= pace + 50 <= 150)
        let alerts = crossedThresholds(
            threshold5h: 0, threshold7d: 0, thresholdExtra: 50,
            previous5h: 70, previous7d: 70, previousUsedCredits: 0,
            current5h: 85, current7d: 85, usedCredits: 200, monthlyLimit: 100
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "Extra usage", pct: 200)])
    }

    func testAllThreeFireSimultaneously() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 50,
            previous5h: 70, previous7d: 70, previousUsedCredits: 0,
            current5h: 85, current7d: 90, usedCredits: 200, monthlyLimit: 100
        )
        XCTAssertEqual(alerts, [
            ThresholdAlert(window: "5-hour", pct: 85),
            ThresholdAlert(window: "7-day", pct: 90),
            ThresholdAlert(window: "Extra usage", pct: 200),
        ])
    }

    func testNoAlertWhenStayingAbove() {
        // All values already above thresholds — no crossing
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 50,
            previous5h: 85, previous7d: 90, previousUsedCredits: 200,
            current5h: 88, current7d: 92, usedCredits: 210, monthlyLimit: 100
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testNoAlertWhenStayingBelow() {
        // All values below thresholds
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 50,
            previous5h: 50, previous7d: 60, previousUsedCredits: 10,
            current5h: 70, current7d: 75, usedCredits: 20, monthlyLimit: 100
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testExactThresholdTriggers() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 0, thresholdExtra: 0,
            previous5h: 79, previous7d: 50, previousUsedCredits: nil,
            current5h: 80, current7d: 50, usedCredits: nil, monthlyLimit: nil
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "5-hour", pct: 80)])
    }

    func testFirstPollFiresWhenAlreadyAboveThreshold() {
        let alerts = crossedThresholds(
            threshold5h: 25, threshold7d: 5, thresholdExtra: 0,
            previous5h: 0, previous7d: 0, previousUsedCredits: nil,
            current5h: 60, current7d: 40, usedCredits: nil, monthlyLimit: nil
        )
        XCTAssertEqual(alerts, [
            ThresholdAlert(window: "5-hour", pct: 60),
            ThresholdAlert(window: "7-day", pct: 40),
        ])
    }

    func testFirstPollDoesNotFireWhenBelowThreshold() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 0,
            previous5h: 0, previous7d: 0, previousUsedCredits: nil,
            current5h: 30, current7d: 50, usedCredits: nil, monthlyLimit: nil
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testDifferentThresholdsPerWindow() {
        let alerts = crossedThresholds(
            threshold5h: 90, threshold7d: 50, thresholdExtra: 70,
            previous5h: 85, previous7d: 45, previousUsedCredits: 0,
            current5h: 95, current7d: 55, usedCredits: 200, monthlyLimit: 100
        )
        XCTAssertEqual(alerts, [
            ThresholdAlert(window: "5-hour", pct: 95),
            ThresholdAlert(window: "7-day", pct: 55),
            ThresholdAlert(window: "Extra usage", pct: 200),
        ])
    }
}
