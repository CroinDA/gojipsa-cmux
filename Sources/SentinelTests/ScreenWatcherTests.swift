import Foundation
import SentinelCore

func runScreenWatcherTests() async {
    await runSuite("ScreenWatcher — Feature 2 timing constants") {
        // Poll interval must be 1s (was 5s pre-Feature-2) for fast danger detection
        await assertEqual(ScreenWatcher.pollIntervalNanos, 1_000_000_000, "poll interval should be 1s")

        // Gemini analyze() should be throttled — was 12s; reduced to 3s for
        // snappier reactions matching the original Python demo's 5s cadence.
        await assert(ScreenWatcher.geminiThrottleSec >= 1 && ScreenWatcher.geminiThrottleSec <= 10,
                     "Gemini throttle should be in 1..10s window")

        // Danger cooldown should suppress repeated alarms on the same pattern
        await assert(ScreenWatcher.dangerCooldownSec >= 20, "danger cooldown should be ≥20s")
    }

    await runSuite("ScreenWatcher — cmux password loader (Feature 2.5)") {
        // Default: no env var, file may or may not exist — must not crash
        let loaded = ScreenWatcher.loadCmuxPassword()
        await assert(loaded.count >= 0, "loader returns String, never crashes")

        // If user has the file, it should non-empty (or env override is set)
        let envSet = !(ProcessInfo.processInfo.environment["CMUX_SOCKET_PASSWORD"] ?? "").isEmpty
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pwdPath = home.appendingPathComponent(".sentinel/cmux-password.txt")
        let fileExists = FileManager.default.fileExists(atPath: pwdPath.path)
        if envSet || fileExists {
            await assert(!loaded.isEmpty, "expected a password to be loaded (env or file present)")
            print("    ↳ password length: \(loaded.count) chars (source: \(envSet ? "env" : "file"))")
        } else {
            await assert(loaded.isEmpty, "no source set → empty string expected")
        }
    }

    await runSuite("DangerAlarm — struct shape") {
        let initial = DangerAlarm(pattern: "rm -rf /var", warning: "🛑 위험!", explanation: nil)
        await assertEqual(initial.pattern, "rm -rf /var", "pattern preserved")
        await assertEqual(initial.warning, "🛑 위험!", "warning preserved")
        await assertNil(initial.explanation, "explanation defaults to nil")

        let refined = DangerAlarm(pattern: "rm -rf /var", warning: "🛑 위험!",
                                  explanation: "/var는 시스템 로그/캐시. 통째로 지우면 복구 어려워.")
        await assertNotNil(refined.explanation, "explanation populated for refined alarm")
    }
}
