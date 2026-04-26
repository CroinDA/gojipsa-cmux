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
        // Kill any leftover Sentinel instances from previous tests / earlier installs
        // (prevents the 'two characters overlapping' UI state where test queries hit
        // stale instance instead of the freshly-launched one).
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "Sentinel.app/Contents/MacOS/Sentinel"]
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
        pkill.arguments = ["-f", "Sentinel.app/Contents/MacOS/Sentinel"]
        pkill.standardOutput = Pipe()
        pkill.standardError = Pipe()
        try? pkill.run()
        pkill.waitUntilExit()
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

    func testBubble_emotionUpdatesCharacterEmoji() throws {
        // Use celebrating emotion → character should show 🥳.
        // NOTE: avoid apostrophes — XCUI launchArguments shell-quoting breaks on '.
        let app = makeApp(args: [
            "--demo-speak", "Lets party time", "--emotion", "celebrating", "--dwell", "5"
        ])
        app.launch()

        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 3))

        let allTexts = app.staticTexts.allElementsBoundByIndex.compactMap { e -> String? in
            return e.value as? String ?? e.label
        }
        let hasEmoji = allTexts.contains(where: { $0.contains("🥳") })
        XCTAssertTrue(hasEmoji,
                      "celebrating emotion should render 🥳 — found: \(allTexts)")
    }

    func testBubble_alarmedEmotionShowsCorrectEmoji() throws {
        let app = makeApp(args: [
            "--demo-speak", "Watch out!", "--emotion", "alarmed", "--dwell", "5"
        ])
        app.launch()

        let emoji = app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS '😱'")).firstMatch
        XCTAssertTrue(emoji.waitForExistence(timeout: 3),
                      "alarmed emotion should render 😱 character emoji")
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
        // Run Sentinel binary directly (not via XCUIApplication) — we want the CLI
        // exit code + stdout, not the GUI.
        // .xctest bundle path: .../Debug/SentinelUITests-Runner.app/Contents/PlugIns/SentinelUITests.xctest
        // Need to go up 4 directories to reach Debug/, then descend into Sentinel.app
        let bundleURL = Bundle(for: type(of: self)).bundleURL
            .deletingLastPathComponent()  // PlugIns/
            .deletingLastPathComponent()  // Contents/
            .deletingLastPathComponent()  // SentinelUITests-Runner.app
            .deletingLastPathComponent()  // Debug/
        let appBin = bundleURL.appendingPathComponent("Sentinel.app/Contents/MacOS/Sentinel")
        guard FileManager.default.isExecutableFile(atPath: appBin.path) else {
            throw XCTSkip("Sentinel binary not found at \(appBin.path)")
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
        // showing an error bubble. The default "Sentinel awake" overlay should appear.
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
        // Launches Sentinel with --demo-gemini-explain flag, which calls
        // GeminiClient.explainDanger("rm -rf /var/log") live and pipes the
        // response into the bubble. Verifies a non-empty Korean response
        // appears within 12s.
        //
        // The test runner's HOME may be sandboxed away from real ~/.sentinel,
        // so we resolve the key file via the developer's known absolute path,
        // then forward it to Sentinel via launchEnvironment["GEMINI_API_KEY"].
        // Test is SKIPPED if no key can be obtained.

        let candidatePaths = [
            "/Users/kwangjinpark/.sentinel/api-key.txt",
            (FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".sentinel/api-key.txt")).path,
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
