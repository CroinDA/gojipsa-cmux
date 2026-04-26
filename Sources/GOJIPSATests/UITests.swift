import Foundation
import AppKit

// MARK: - UI test infrastructure (XCTest-free, runs without Xcode)
//
// These tests exercise the actual NSApplication binary by:
//   1. Launching `.build/debug/GOJIPSA` as a subprocess with a test flag
//      (`--demo-overlay` or `--demo-alarm`) plus `--dwell <seconds>`
//   2. Polling CGWindowListCopyWindowInfo to verify GOJIPSA windows appear
//   3. Letting the test process auto-exit() after the dwell window
//
// Why CGWindowListCopyWindowInfo: it returns window metadata (owner, bounds,
// title) without requiring Accessibility/Screen Recording permission. Good
// enough for layout + presence checks. For deep input simulation use
// XCUIApplication (Xcode required — see xctest-ui-templates/).

private let gojipsaBinary: String = {
    let candidates = [
        // SPM debug build relative to project root (when running via swift run)
        FileManager.default.currentDirectoryPath + "/.build/debug/GOJIPSA",
        // Installed app
        "/Applications/GOJIPSA.app/Contents/MacOS/GOJIPSA",
    ]
    return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? candidates[0]
}()

private struct WindowInfo {
    let owner: String
    let title: String
    let bounds: CGRect
}

/// Snapshot all on-screen windows, filter by owner name.
private func windows(ownedBy owner: String) -> [WindowInfo] {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return raw.compactMap { dict -> WindowInfo? in
        let ownerName = dict[kCGWindowOwnerName as String] as? String ?? ""
        guard ownerName == owner else { return nil }
        let title = dict[kCGWindowName as String] as? String ?? ""
        let bd = dict[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let bounds = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0,
                            width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
        return WindowInfo(owner: ownerName, title: title, bounds: bounds)
    }
}

/// Launch GOJIPSA with given arguments, return Process. Caller must terminate.
private func launchGojipsa(_ args: [String]) -> Process? {
    guard FileManager.default.isExecutableFile(atPath: gojipsaBinary) else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: gojipsaBinary)
    proc.arguments = args
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    return proc
}

// MARK: - Test cases

func runUITests() async {
    await runSuite("UI — GOJIPSA binary launchable") {
        let exists = FileManager.default.isExecutableFile(atPath: gojipsaBinary)
        await assert(exists, "GOJIPSA binary at \(gojipsaBinary) should exist & be executable")
        if !exists {
            print("    ⚠ binary not found — skipping further UI tests in this run")
        }
    }

    await runSuite("UI — overlay window appears within 3s (--demo-overlay)") {
        guard let proc = launchGojipsa(["--demo-overlay", "--dwell", "5"]) else {
            await assert(false, "could not launch GOJIPSA"); return
        }
        defer { proc.terminate() }

        var found: [WindowInfo] = []
        for _ in 0..<15 {  // up to ~3 seconds
            try? await Task.sleep(nanoseconds: 200_000_000)
            found = windows(ownedBy: "GOJIPSA")
            if !found.isEmpty { break }
        }
        await assert(!found.isEmpty, "no GOJIPSA-owned windows seen within 3s")
        if let first = found.first {
            print("    ↳ found window: bounds=\(first.bounds) title='\(first.title)'")
            // Overlay should be in the bottom-right region of some screen
            await assert(first.bounds.width > 0 && first.bounds.height > 0,
                         "window should have non-zero size")
        }
    }

    await runSuite("UI — alarm panel appears (--demo-alarm)") {
        guard let proc = launchGojipsa(["--demo-alarm", "--dwell", "5"]) else {
            await assert(false, "could not launch GOJIPSA"); return
        }
        defer { proc.terminate() }

        // Wait a bit longer — alarm panel is shown after launch
        var alarmWindows: [WindowInfo] = []
        for _ in 0..<20 {  // up to ~4 seconds
            try? await Task.sleep(nanoseconds: 200_000_000)
            let all = windows(ownedBy: "GOJIPSA")
            // The alarm covers the full screen — bigger than overlay's 320×180
            alarmWindows = all.filter { $0.bounds.width > 600 && $0.bounds.height > 300 }
            if !alarmWindows.isEmpty { break }
        }
        await assert(!alarmWindows.isEmpty, "expected a large alarm panel window (>600×300) to appear")
        if let alarm = alarmWindows.first {
            print("    ↳ alarm bounds=\(alarm.bounds)")
        }
    }

    await runSuite("UI — bubble: --demo-speak shows overlay window") {
        // Custom runner can't read NSTextField text content (no AX permission)
        // — but we can verify the overlay window appears when --demo-speak fires.
        guard let proc = launchGojipsa(["--demo-speak", "smoke-text", "--dwell", "5"]) else {
            await assert(false, "could not launch GOJIPSA"); return
        }
        defer { proc.terminate() }
        var found: [WindowInfo] = []
        for _ in 0..<15 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            found = windows(ownedBy: "GOJIPSA")
            if !found.isEmpty { break }
        }
        await assert(!found.isEmpty, "bubble overlay should appear within 3s of --demo-speak")
    }

    await runSuite("UI — bubble: --demo-speak-multi runs 3 updates without crash") {
        guard let proc = launchGojipsa(["--demo-speak-multi", "--dwell", "6"]) else {
            await assert(false, "could not launch GOJIPSA"); return
        }
        defer { proc.terminate() }
        // App should stay alive through all 3 speak() invocations
        try? await Task.sleep(nanoseconds: 4_500_000_000)  // 4.5s — past 2nd update
        await assert(proc.isRunning, "GOJIPSA should survive multiple speak() calls without crashing")
    }

    await runSuite("UI — process self-exits after dwell expires") {
        guard let proc = launchGojipsa(["--demo-overlay", "--dwell", "2"]) else {
            await assert(false, "could not launch GOJIPSA"); return
        }
        // Wait up to 5 seconds for self-exit
        var exited = false
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !proc.isRunning { exited = true; break }
        }
        if !exited { proc.terminate() }
        await assert(exited, "GOJIPSA should self-exit within 5s when --dwell 2 expires")
    }
}
