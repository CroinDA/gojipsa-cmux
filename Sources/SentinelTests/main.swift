import Foundation

print("🧪 Sentinel test suite")

await runSmokeTests()
await runDangerDetectorTests()
await runSecretRedactorTests()
await runScreenWatcherTests()
await runGeminiClientTests()
await runUITests()

await printSummary()

let failed = await stats.failed
exit(failed == 0 ? 0 : 1)
