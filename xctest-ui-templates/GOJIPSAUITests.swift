import XCTest

/// UI tests for GOJIPSA — requires Xcode (XCUIApplication).
///
/// To use:
///   1. Copy this file to `Tests/GOJIPSAUITests/GOJIPSAUITests.swift`
///   2. Add a `testTarget(name: "GOJIPSAUITests", ...)` to Package.swift
///   3. `xcodebuild -scheme GOJIPSA -only-testing:GOJIPSAUITests test`
final class GOJIPSAUITests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "app.gojipsa.GOJIPSA")
        app.launchArguments = args
        return app
    }

    // MARK: - Smoke

    func testApp_launchesAndShowsOverlay() throws {
        let app = makeApp(args: ["--demo-overlay", "--dwell", "5"])
        app.launch()

        // GOJIPSA uses a borderless NSPanel — XCUI may surface it as a window
        let firstWindow = app.windows.firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 3),
                      "overlay window should appear within 3s")

        // Sanity: window bounds are non-empty (XCUI reports frame)
        let frame = firstWindow.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    func testApp_showsAlarmOnDemoFlag() throws {
        let app = makeApp(args: ["--demo-alarm", "--dwell", "5"])
        app.launch()

        // Alarm panel is full screen — should be the largest window
        let allWindows = app.windows.allElementsBoundByIndex
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))

        let largest = allWindows.max(by: { $0.frame.width < $1.frame.width })
        XCTAssertNotNil(largest)
        if let w = largest {
            XCTAssertGreaterThan(w.frame.width, 600,
                                 "alarm panel should be at least 600pt wide")
        }
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

        // Wait up to 5 seconds for self-exit
        let deadline = Date().addingTimeInterval(5)
        var exited = false
        while Date() < deadline {
            if app.state == .notRunning { exited = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(exited, "GOJIPSA should self-exit within 5s when --dwell 2 expires")
    }
}
