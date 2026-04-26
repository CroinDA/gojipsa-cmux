import Foundation
import AppKit

// MARK: - UI test infrastructure (XCTest-free, runs without Xcode)
//
// These tests exercise the actual NSApplication binary by:
//   1. Launching `.build/debug/Sentinel` as a subprocess with a test flag
//      (`--demo-overlay` or `--demo-alarm`) plus `--dwell <seconds>`
//   2. Polling CGWindowListCopyWindowInfo to verify Sentinel windows appear
//   3. Letting the test process auto-exit() after the dwell window
//
// Why CGWindowListCopyWindowInfo: it returns window metadata (owner, bounds,
// title) without requiring Accessibility/Screen Recording permission. Good
// enough for layout + presence checks. For deep input simulation use
// XCUIApplication (Xcode required — see xctest-ui-templates/).

private let sentinelBinary: String = {
    let candidates = [
        // SPM debug build relative to project root (when running via swift run)
        FileManager.default.currentDirectoryPath + "/.build/debug/Sentinel",
        // Installed app
        "/Applications/Sentinel.app/Contents/MacOS/Sentinel",
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

/// Launch Sentinel with given arguments, return Process. Caller must terminate.
private func launchSentinel(_ args: [String]) -> Process? {
    guard FileManager.default.isExecutableFile(atPath: sentinelBinary) else { return nil }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: sentinelBinary)
    proc.arguments = args
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    do { try proc.run() } catch { return nil }
    return proc
}

// MARK: - Test cases

func runUITests() async {
    await runSuite("UI — Sentinel binary launchable") {
        let exists = FileManager.default.isExecutableFile(atPath: sentinelBinary)
        await assert(exists, "Sentinel binary at \(sentinelBinary) should exist & be executable")
        if !exists {
            print("    ⚠ binary not found — skipping further UI tests in this run")
        }
    }

    await runSuite("UI — overlay window appears within 3s (--demo-overlay)") {
        guard let proc = launchSentinel(["--demo-overlay", "--dwell", "5"]) else {
            await assert(false, "could not launch Sentinel"); return
        }
        defer { proc.terminate() }

        var found: [WindowInfo] = []
        for _ in 0..<15 {  // up to ~3 seconds
            try? await Task.sleep(nanoseconds: 200_000_000)
            found = windows(ownedBy: "Sentinel")
            if !found.isEmpty { break }
        }
        await assert(!found.isEmpty, "no Sentinel-owned windows seen within 3s")
        if let first = found.first {
            print("    ↳ found window: bounds=\(first.bounds) title='\(first.title)'")
            // Overlay should be in the bottom-right region of some screen
            await assert(first.bounds.width > 0 && first.bounds.height > 0,
                         "window should have non-zero size")
        }
    }

    await runSuite("UI — alarm panel appears (--demo-alarm)") {
        guard let proc = launchSentinel(["--demo-alarm", "--dwell", "5"]) else {
            await assert(false, "could not launch Sentinel"); return
        }
        defer { proc.terminate() }

        // Wait a bit longer — alarm panel is shown after launch
        var alarmWindows: [WindowInfo] = []
        for _ in 0..<20 {  // up to ~4 seconds
            try? await Task.sleep(nanoseconds: 200_000_000)
            let all = windows(ownedBy: "Sentinel")
            // The alarm covers the full screen — bigger than overlay's 320×180
            alarmWindows = all.filter { $0.bounds.width > 600 && $0.bounds.height > 300 }
            if !alarmWindows.isEmpty { break }
        }
        await assert(!alarmWindows.isEmpty, "expected a large alarm panel window (>600×300) to appear")
        if let alarm = alarmWindows.first {
            print("    ↳ alarm bounds=\(alarm.bounds)")
        }
    }

    await runSuite("UI — process self-exits after dwell expires") {
        guard let proc = launchSentinel(["--demo-overlay", "--dwell", "2"]) else {
            await assert(false, "could not launch Sentinel"); return
        }
        // Wait up to 5 seconds for self-exit
        var exited = false
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !proc.isRunning { exited = true; break }
        }
        if !exited { proc.terminate() }
        await assert(exited, "Sentinel should self-exit within 5s when --dwell 2 expires")
    }
}
