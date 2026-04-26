import Foundation
import SentinelCore

func runScreenWatcherTests() async {
    await runSuite("ScreenWatcher — Feature 2 timing constants") {
        // Poll interval must be 1s (was 5s pre-Feature-2) for fast danger detection
        await assertEqual(ScreenWatcher.pollIntervalNanos, 1_000_000_000, "poll interval should be 1s")

        // Gemini analyze() should be throttled to keep API cost predictable
        await assert(ScreenWatcher.geminiThrottleSec >= 10, "Gemini analyze throttle should be ≥10s")

        // Danger cooldown should suppress repeated alarms on the same pattern
        await assert(ScreenWatcher.dangerCooldownSec >= 20, "danger cooldown should be ≥20s")
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
