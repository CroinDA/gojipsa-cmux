import AppKit
import Foundation
#if SWIFT_PACKAGE
import SentinelCore
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var alarm: AlarmPanel!
    var watcher: ScreenWatcher!
    var watchTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ note: Notification) {
        let apiKey = loadApiKey()
        if apiKey.isEmpty {
            FileHandle.standardError.write(Data("⚠️  GEMINI_API_KEY missing. Set env var or write to ~/.sentinel/api-key.txt\n".utf8))
        }

        panel = OverlayPanel()
        panel.show()
        panel.speak("👀 Sentinel awake. Watching your shell...", emotion: .idle)

        alarm = AlarmPanel()

        // ─── UI test entry points (DEBUG builds only) ───
        // Stripped from `swift build -c release` so end-users can't trigger fake alarms.
#if DEBUG
        let args = CommandLine.arguments
        if args.contains("--demo-overlay") {
            panel.speak("🧪 UI test — overlay ready", emotion: .talking)
            let dwellSec = parseDwellSeconds(args, default: 3)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(dwellSec) * 1_000_000_000)
                exit(0)
            }
            return
        }
        if args.contains("--demo-alarm") {
            alarm.showAlarm(
                pattern: "rm -rf /tmp/test-from-ui",
                warning: "🛑 [UI test] 위험 감지!",
                explanation: "이건 UI 테스트용 더미 alarm. 5초 후 자동 닫힘.",
                dismissAfter: 4.0
            )
            let dwellSec = parseDwellSeconds(args, default: 5)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(dwellSec) * 1_000_000_000)
                exit(0)
            }
            return
        }
#endif

        watcher = ScreenWatcher(
            apiKey: apiKey,
            onComment: { [weak self] comment in
                Task { @MainActor in
                    self?.panel.speak(comment.text, emotion: comment.emotion)
                }
            },
            onAlarm: { [weak self] alarmEvent in
                Task { @MainActor in
                    if alarmEvent.explanation == nil {
                        // First fire: show alarm immediately with placeholder
                        self?.alarm.showAlarm(
                            pattern: alarmEvent.pattern,
                            warning: alarmEvent.warning,
                            explanation: nil
                        )
                    } else {
                        // Refinement: explanation arrived from Gemini, update text in-place
                        self?.alarm.updateExplanation(alarmEvent.explanation ?? "")
                    }
                }
            }
        )
        let w = watcher!
        watchTask = Task.detached { await w.run() }
    }

    func applicationWillTerminate(_ note: Notification) {
        watchTask?.cancel()
    }

    private func parseDwellSeconds(_ args: [String], default fallback: Int) -> Int {
        // Looks for --dwell <N>
        if let idx = args.firstIndex(of: "--dwell"),
           idx + 1 < args.count,
           let n = Int(args[idx + 1]),
           (1...60).contains(n) {
            return n
        }
        return fallback
    }

    private func loadApiKey() -> String {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keyPath = home.appendingPathComponent(".sentinel/api-key.txt")
        if let data = try? Data(contentsOf: keyPath),
           let str = String(data: data, encoding: .utf8) {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    // Strong-retain delegate beyond scope
    objc_setAssociatedObject(app, "sentinelDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    app.run()
}
