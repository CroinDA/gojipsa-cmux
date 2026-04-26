import XCTest

/// UI tests for Sentinel — requires Xcode (XCUIApplication).
///
/// To use:
///   1. Copy this file to `Tests/SentinelUITests/SentinelUITests.swift`
///   2. Add a `testTarget(name: "SentinelUITests", ...)` to Package.swift
///   3. `xcodebuild -scheme Sentinel -only-testing:SentinelUITests test`
final class SentinelUITests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(args: [String] = []) -> XCUIApplication {
        // No-arg XCUIApplication uses the test target's host app
        // (TEST_TARGET_NAME = Sentinel in project.yml), which is the Xcode-built
        // debug binary — NOT /Applications/Sentinel.app — so DEBUG flags work.
        let app = XCUIApplication()
        app.launchArguments = args
        return app
    }

    // MARK: - Smoke

    func testApp_launchesAndShowsOverlay() throws {
        let app = makeApp(args: ["--demo-overlay", "--dwell", "5"])
        app.launch()

        // Borderless NSPanels aren't surfaced as `.windows` in XCUITest.
        // Verify launch via accessibility children — the overlay's label.
        let anyText = app.staticTexts.firstMatch
        XCTAssertTrue(anyText.waitForExistence(timeout: 3),
                      "expected at least one accessible text element from the overlay")

        // Sentinel is an accessory app (LSUIElement=true), so it stays in
        // .runningBackground state — never .runningForeground. We just need
        // it to not be terminated.
        XCTAssertNotEqual(app.state, .notRunning,
                          "Sentinel must be running (any state ≠ notRunning)")
    }

    func testApp_showsAlarmOnDemoFlag() throws {
        let app = makeApp(args: ["--demo-alarm", "--dwell", "5"])
        app.launch()

        // Alarm has multiple accessible text fields (title, pattern, warning, explanation)
        // — verify several show up.
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 3),
                      "alarm should produce accessible text elements")

        // Title contains '위험' or '🛑'
        let title = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS '위험' OR value CONTAINS '🛑'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 3),
                      "alarm title with '위험'/'🛑' must be visible")
    }

    func testApp_overlayContainsExpectedText() throws {
        let app = makeApp(args: ["--demo-overlay", "--dwell", "5"])
        app.launch()

        // Borderless panel labels are NSTextField — exposed as staticTexts in XCUI
        let testText = app.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] 'UI test'")).firstMatch
        XCTAssertTrue(testText.waitForExistence(timeout: 3),
                      "overlay should display the UI-test marker text")
    }

    func testApp_alarmContainsPatternAndWarning() throws {
        let app = makeApp(args: ["--demo-alarm", "--dwell", "5"])
        app.launch()

        let pattern = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'rm -rf /tmp/test-from-ui'")).firstMatch
        let warning = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS '위험 감지'")).firstMatch

        XCTAssertTrue(pattern.waitForExistence(timeout: 3),
                      "alarm should show the matched pattern")
        XCTAssertTrue(warning.waitForExistence(timeout: 3),
                      "alarm should show the warning")
    }

    func testApp_terminatesAfterDwell() throws {
        let app = makeApp(args: ["--demo-overlay", "--dwell", "2"])
        app.launch()

        // Wait up to 8 seconds for self-exit. XCUI's app.state can transition through
        // multiple values (runningForeground → runningBackgroundSuspended →
        // notRunning) before reporting .notRunning, so we accept any non-foreground
        // state as "exited".
        let deadline = Date().addingTimeInterval(8)
        var exited = false
        while Date() < deadline {
            if app.state != .runningForeground { exited = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(exited,
                      "Sentinel should leave .runningForeground within 8s when --dwell 2 expires (state=\(app.state.rawValue))")
    }
}
