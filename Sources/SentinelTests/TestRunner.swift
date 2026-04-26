import Foundation

// Lightweight test framework — XCTest-free so this builds without Xcode.

actor TestStats {
    var passed = 0
    var failed = 0
    var skipped = 0
    var failures: [String] = []

    func recordPass() { passed += 1 }
    func recordFail(_ message: String) { failed += 1; failures.append(message) }
    func recordSkip() { skipped += 1 }
}

let stats = TestStats()

func assert(_ cond: Bool, _ message: @autoclosure () -> String, file: String = #file, line: Int = #line) async {
    if cond {
        await stats.recordPass()
    } else {
        let msg = "❌ \(URL(fileURLWithPath: file).lastPathComponent):\(line) — \(message())"
        await stats.recordFail(msg)
    }
}

func assertNotNil<T>(_ value: T?, _ message: @autoclosure () -> String, file: String = #file, line: Int = #line) async {
    await assert(value != nil, message(), file: file, line: line)
}

func assertNil<T>(_ value: T?, _ message: @autoclosure () -> String, file: String = #file, line: Int = #line) async {
    await assert(value == nil, message(), file: file, line: line)
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String, file: String = #file, line: Int = #line) async {
    await assert(a == b, "\(message()) — got \(a), expected \(b)", file: file, line: line)
}

func skip(_ reason: String) async {
    await stats.recordSkip()
    print("  ⏭  SKIP — \(reason)")
}

func runSuite(_ name: String, _ body: () async -> Void) async {
    print("\n━━━ \(name) ━━━")
    await body()
}

func printSummary() async {
    let p = await stats.passed
    let f = await stats.failed
    let s = await stats.skipped
    let failures = await stats.failures
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("✅ \(p) passed   ❌ \(f) failed   ⏭  \(s) skipped")
    if !failures.isEmpty {
        print("\nFailures:")
        for msg in failures { print("  \(msg)") }
    }
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
}
