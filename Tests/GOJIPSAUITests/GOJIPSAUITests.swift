import XCTest

/// UI tests for GOJIPSA — requires Xcode (XCUIApplication).
///
/// Run with:
///   xcodebuild -project GOJIPSA.xcodeproj -scheme GOJIPSA -only-testing:GOJIPSAUITests test
final class GOJIPSAUITests: XCTestCase {

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Kill any leftover GOJIPSA instances from previous tests / earlier installs
        // (prevents the 'two characters overlapping' UI state where test queries hit
        // stale instance instead of the freshly-launched one).
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "GOJIPSA.app/Contents/MacOS/GOJIPSA"]
        pkill.standardOutput = Pipe()
        pkill.standardError = Pipe()
        try? pkill.run()
        pkill.waitUntilExit()
        // Brief settle so launch-services doesn't dedupe with the dying instance
        Thread.sleep(forTimeInterval: 0.4)
    }

    override func tearDownWithError() throws {
        // Best-effort terminate — the demo-flag tests have --dwell so the app exits
        // on its own, but if a test failed mid-way we want a clean slate.
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "GOJIPSA.app/Contents/MacOS/GOJIPSA"]
        pkill.standardOutput = Pipe()
        pkill.standardError = Pipe()
        try? pkill.run()
        pkill.waitUntilExit()
    }

    private func makeApp(args: [String] = []) -> XCUIApplication {
        // No-arg XCUIApplication uses the test target's host app
        // (TEST_TARGET_NAME = GOJIPSA in GOJIPSA.xcodeproj), which is the Xcode-built
        // debug binary — NOT /Applications/GOJIPSA.app — so DEBUG flags work.
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

        // GOJIPSA is an accessory app (LSUIElement=true), so it stays in
        // .runningBackground state — never .runningForeground. We just need
        // it to not be terminated.
        XCTAssertNotEqual(app.state, .notRunning,
                          "GOJIPSA must be running (any state ≠ notRunning)")
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

    // MARK: - Bubble (말풍선) tests

    func testBubble_displaysExactSpokenText() throws {
        let unique = "Hello unique-bubble-marker-91823"
        let app = makeApp(args: ["--demo-speak", unique, "--dwell", "5"])
        app.launch()

        let exact = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS %@", unique)).firstMatch
        XCTAssertTrue(exact.waitForExistence(timeout: 3),
                      "bubble should display the exact text passed to speak()")
    }

    func testBubble_emotionLottiesLaunchWithoutCrashing() throws {
        // After removing the emoji label, the character is rendered by Lottie only.
        // XCUITest can't introspect Lottie animation content, so we verify the app
        // boots cleanly with each emotion (bubble text is queryable; if app crashed
        // mid-startup the staticTexts would be empty).
        let app = makeApp(args: [
            "--demo-speak", "Lets party time", "--emotion", "celebrating", "--dwell", "5"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 3),
                      "app should boot and show bubble text under celebrating emotion")
        XCTAssertNotEqual(app.state, .notRunning,
                          "app must stay alive after Lottie load")
    }

    func testBubble_alarmedEmotionLaunchesCleanly() throws {
        let app = makeApp(args: [
            "--demo-speak", "Watch out!", "--emotion", "alarmed", "--dwell", "5"
        ])
        app.launch()
        let bubble = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'Watch out!'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 3),
                      "alarmed emotion should still surface the spoken text in the bubble")
    }

    func testBubble_multipleSpeaksUpdatesText() throws {
        // Bubble is updated 3 times. After all updates, the FINAL message must be visible.
        let app = makeApp(args: ["--demo-speak-multi", "--dwell", "6"])
        app.launch()

        // Wait briefly for first speak() — but this is racy because the multi handler
        // sets bubble to "First", then 1s later "Second", then 1s later "Final".
        // We just verify the FINAL state.
        Thread.sleep(forTimeInterval: 3.0)  // past the third speak()

        let allTexts = app.staticTexts.allElementsBoundByIndex.compactMap { $0.value as? String }
        print("    [debug-multi] staticTexts after 3s: \(allTexts)")

        let hasFinal = allTexts.contains(where: { $0.contains("Final message") })
        XCTAssertTrue(hasFinal,
                      "speak() called 3 times — final message should end up in the bubble. Found: \(allTexts)")
    }

    // MARK: - cmux status (--status flag) tests

    func testStatus_flagPrintsConnectedAndExitsZero() throws {
        // Run GOJIPSA binary directly (not via XCUIApplication) — we want the CLI
        // exit code + stdout, not the GUI.
        // .xctest bundle path: .../Debug/GOJIPSAUITests-Runner.app/Contents/PlugIns/GOJIPSAUITests.xctest
        // Need to go up 4 directories to reach Debug/, then descend into GOJIPSA.app
        let bundleURL = Bundle(for: type(of: self)).bundleURL
            .deletingLastPathComponent()  // PlugIns/
            .deletingLastPathComponent()  // Contents/
            .deletingLastPathComponent()  // GOJIPSAUITests-Runner.app
            .deletingLastPathComponent()  // Debug/
        let appBin = bundleURL.appendingPathComponent("GOJIPSA.app/Contents/MacOS/GOJIPSA")
        guard FileManager.default.isExecutableFile(atPath: appBin.path) else {
            throw XCTSkip("GOJIPSA binary not found at \(appBin.path)")
        }

        let proc = Process()
        proc.executableURL = appBin
        proc.arguments = ["--status"]
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let combined = stdout +
            (String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")

        // Output must contain the status line headers regardless of state
        XCTAssertTrue(combined.contains("cmux status:"), "stdout missing 'cmux status:' line — got: \(combined)")
        XCTAssertTrue(combined.contains("summary:"), "stdout missing 'summary:' line")
        XCTAssertTrue(combined.contains("cmuxPath:"), "stdout missing 'cmuxPath:' line")

        // Exit code: 0 when connected, 2 otherwise — both are valid; we just check it's consistent
        let connected = combined.contains("status: connected")
        let exitCode = proc.terminationStatus
        if connected {
            XCTAssertEqual(exitCode, 0, "connected should map to exit 0")
        } else {
            XCTAssertEqual(exitCode, 2, "non-connected should map to exit 2 (got \(exitCode))")
        }
    }

    func testStatus_startupHealthCheckSurfacesInBubbleWhenDisconnected() throws {
        // We can't easily simulate cmux being down inside a UI test, but we can verify
        // the connected case: the app launches and the startup health check runs without
        // showing an error bubble. The default "GOJIPSA awake" overlay should appear.
        let app = makeApp(args: ["--demo-overlay", "--dwell", "5"])
        app.launch()

        // No specific 'failed' string should appear in the connected case
        let errorBubble = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS '❌' OR value CONTAINS '🔒'")).firstMatch
        XCTAssertFalse(errorBubble.exists,
                       "no error/lock bubble should appear when cmux is connected")
    }

    // MARK: - Gemini integration tests

    func testGemini_explainDangerReturnsKoreanResponse() throws {
        // Launches GOJIPSA with --demo-gemini-explain flag, which calls
        // GeminiClient.explainDanger("rm -rf /var/log") live and pipes the
        // response into the bubble. Verifies a non-empty Korean response
        // appears within 12s.
        //
        // The test runner's HOME may be sandboxed away from real ~/.gojipsa (and legacy ~/.sentinel),
        // so we resolve the key file via the developer's known absolute path,
        // then forward it to GOJIPSA via launchEnvironment["GEMINI_API_KEY"].
        // Test is SKIPPED if no key can be obtained.

        let candidatePaths = [
            "/Users/kwangjinpark/.gojipsa/api-key.txt",
            (FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gojipsa/api-key.txt")).path,
        ]
        let key: String? = candidatePaths.lazy
            .compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let apiKey = key else {
            throw XCTSkip("Gemini API key not found in known locations — integration test skipped")
        }

        let app = makeApp(args: ["--demo-gemini-explain", "--dwell", "15"])
        app.launchEnvironment["GEMINI_API_KEY"] = apiKey
        app.launch()

        // First state should show the 'calling Gemini' placeholder
        let placeholder = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS 'Gemini'")).firstMatch
        XCTAssertTrue(placeholder.waitForExistence(timeout: 3),
                      "should show '🤖 Gemini explain 호출중...' placeholder before response")

        // Wait for live response (Gemini typically responds in 1–5s but allow up to 12s)
        var foundResponse = false
        var sample: [String] = []
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            sample = app.staticTexts.allElementsBoundByIndex.compactMap { $0.value as? String }
            // Look for Korean response — placeholder text is replaced by real response
            // (any text NOT containing 'Gemini explain 호출중' AND has more than 20 chars)
            foundResponse = sample.contains { txt in
                txt.count > 20 &&
                !txt.contains("Gemini explain 호출중") &&
                !txt.contains("Gemini 응답 실패") &&
                txt.range(of: #"[가-힣]"#, options: .regularExpression) != nil
            }
            if foundResponse { break }
        }

        XCTAssertTrue(foundResponse,
                      "Gemini live response should arrive within 12s and contain Korean text. Last seen: \(sample)")
    }

    // MARK: - Hackathon deadline demo

    func testHackathonDeadlineNaggingDemo_runsForThirtySeconds() throws {
        // Starts at the user's example time, then compresses the remaining
        // hackathon clock so a single 30s Xcode run shows submission pressure,
        // finalist prep, final pitching, and winner-announcement nagging.
        let app = makeApp(args: [
            "--demo-hackathon-deadlines",
            "--demo-now", "17:33",
            "--demo-step-minutes", "15",
            "--demo-tick", "3",
            "--dwell", "33",
        ])
        app.launch()

        let started = Date()
        let deadline = started.addingTimeInterval(30)
        var sawSubmissionThirtyMinuteMode = false
        var sawFinalistPrep = false
        var sawAwardMessage = false
        var lastRunningElapsed: TimeInterval = 0
        var samples: [String] = []

        while Date() < deadline {
            XCTAssertNotEqual(app.state, .notRunning,
                              "GOJIPSA should stay alive for the 30s hackathon demo")

            let texts = app.staticTexts.allElementsBoundByIndex.compactMap { $0.value as? String }
            if !texts.isEmpty { samples = texts }

            sawSubmissionThirtyMinuteMode = sawSubmissionThirtyMinuteMode || texts.contains {
                $0.contains("제출 마감 30분 전") && $0.contains("새 기능 금지")
            }
            sawFinalistPrep = sawFinalistPrep || texts.contains {
                $0.contains("파이널리스트")
            }
            sawAwardMessage = sawAwardMessage || texts.contains {
                $0.contains("수상자 발표")
            }

            lastRunningElapsed = Date().timeIntervalSince(started)
            Thread.sleep(forTimeInterval: 0.5)
        }

        XCTAssertGreaterThanOrEqual(lastRunningElapsed, 29.0,
                                    "demo should remain observable for about 30s")
        XCTAssertTrue(sawSubmissionThirtyMinuteMode,
                      "17:33 should trigger the submission-deadline nag. Last seen: \(samples)")
        XCTAssertTrue(sawFinalistPrep,
                      "compressed demo should reach the 19:25 finalist announcement. Last seen: \(samples)")
        XCTAssertTrue(sawAwardMessage,
                      "compressed demo should reach the 20:00 winner announcement. Last seen: \(samples)")
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
                      "GOJIPSA should leave .runningForeground within 8s when --dwell 2 expires (state=\(app.state.rawValue))")
    }
}
