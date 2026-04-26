import Foundation
import SentinelCore

func runGeminiClientTests() async {
    let envKey = ProcessInfo.processInfo.environment["GEMINI_TEST_KEY"] ?? ""

    await runSuite("GeminiClient — input validation") {
        let emptyClient = GeminiClient(apiKey: "")
        let nilForEmpty = await emptyClient.analyze(screen: "$ ls -la\nfile.txt")
        await assertNil(nilForEmpty, "empty API key should yield nil")

        if !envKey.isEmpty {
            let realClient = GeminiClient(apiKey: envKey)
            let nilForBlank = await realClient.analyze(screen: "   \n\n  ")
            await assertNil(nilForBlank, "blank screen should short-circuit")
        }
    }

    await runSuite("GeminiClient — invalid key fails gracefully") {
        let client = GeminiClient(apiKey: "INVALID_KEY_FOR_TESTING_ERROR_PATH")
        let result = await client.analyze(screen: "$ ls -la")
        await assertNil(result, "invalid key should yield nil, not crash")
    }

    if envKey.isEmpty {
        await runSuite("GeminiClient — live integration") {
            await skip("GEMINI_TEST_KEY env var not set")
        }
    } else {
        await runSuite("GeminiClient — live integration (real Gemini call)") {
            let client = GeminiClient(apiKey: envKey)
            let danger = """
            $ rm -rf /tmp/test-dir
            $ git push --force origin main
            """
            let comment = await client.analyze(screen: danger)
            await assertNotNil(comment, "live call with danger screen should return a comment")
            if let c = comment {
                await assert(!c.text.isEmpty, "comment text non-empty (got: '\(c.text)')")
                await assert(c.shouldReact, "shouldReact must be true for danger")
                print("    💬 sample reply: \(c.text) [\(c.emotion.rawValue)]")
            }
        }
    }
}
