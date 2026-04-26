import AppKit
import Foundation
#if SWIFT_PACKAGE
import GOJIPSACore
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var alarm: AlarmPanel!
    var watcher: ScreenWatcher!
    var watchTask: Task<Void, Never>?
    var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ note: Notification) {
        // First-run migration: copy ~/.sentinel/* → ~/.gojipsa/* for v1.x users.
        // Best-effort, never throws — see PathMigration.swift for details.
        PathMigration.migrateLegacyIfNeeded()

        let apiKey = loadApiKey()
        if apiKey.isEmpty {
            FileHandle.standardError.write(Data("⚠️  GEMINI_API_KEY missing. Set env var or write to ~/.gojipsa/api-key.txt\n".utf8))
        }

        // ─── --status: print cmux connection state and exit (CLI tool mode) ───
        let cliArgs = CommandLine.arguments
        if cliArgs.contains("--status") {
            Task { @MainActor in
                let report = await ScreenWatcher.quickStatus()
                let line = """
                cmux status: \(report.status.rawValue)
                summary:     \(report.status.summary)
                cmuxPath:    \(report.cmuxPath.isEmpty ? "(not found)" : report.cmuxPath)
                password:    \(report.usingPassword ? "yes" : "no")
                details:     \(report.details.isEmpty ? "(none)" : report.details)

                """
                FileHandle.standardOutput.write(Data(line.utf8))
                exit(report.status == .connected ? 0 : 2)
            }
            return
        }

        panel = OverlayPanel()
        panel.show()
        panel.speak("👀 꼬집사 깼어. 터미널 보고 있을게.", emotion: .idle)

        alarm = AlarmPanel()
        // Always-visible menu bar item — green/red dot reflects cmux state,
        // click to see status / quit GOJIPSA.
        statusBar = StatusBarController()

        // ─── Startup health check — surface cmux status visually so the user
        //     immediately knows if GOJIPSA can actually read their terminal.
        //     Suppressed when running with any --demo-* flag (those are reserved
        //     for UI tests / manual feature demos and shouldn't be polluted by
        //     status overrides). ───
        let isDemoMode = cliArgs.contains(where: { $0.hasPrefix("--demo-") })
        if !isDemoMode {
            Task { @MainActor in
                let report = await ScreenWatcher.quickStatus()
                if report.status != .connected {
                    self.panel.speak(report.status.summary,
                                     emotion: report.status == .accessDenied ? .alarmed : .nagging,
                                     autoHide: 12.0)
                }
            }
        }

        // ─── UI test / manual demo entry points ───
        // Available in both debug and release so users can verify lottie mappings
        // visually with `GOJIPSA --demo-speak ... --emotion <name>`.
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
        // --demo-speak <text> — show bubble with exact text, default idle emotion
        if let idx = args.firstIndex(of: "--demo-speak"), idx + 1 < args.count {
            let text = args[idx + 1]
            // Optional emotion: --demo-speak <text> --emotion <name>
            var emotion: Emotion = .talking
            if let eIdx = args.firstIndex(of: "--emotion"), eIdx + 1 < args.count,
               let parsed = Emotion(rawValue: args[eIdx + 1]) ??
                            Emotion.fromName(args[eIdx + 1]) {
                emotion = parsed
            }
            panel.speak(text, emotion: emotion, autoHide: 60.0)  // long autoHide for inspection
            let dwellSec = parseDwellSeconds(args, default: 5)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(dwellSec) * 1_000_000_000)
                exit(0)
            }
            return
        }

        // --demo-speak-multi — call speak() three times in a row to verify text updates
        if args.contains("--demo-speak-multi") {
            panel.speak("First message", emotion: .idle, autoHide: 60.0)
            let dwellSec = parseDwellSeconds(args, default: 6)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.panel.speak("Second message", emotion: .talking, autoHide: 60.0)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.panel.speak("Final message at the end", emotion: .celebrating, autoHide: 60.0)
                try? await Task.sleep(nanoseconds: UInt64(dwellSec - 2) * 1_000_000_000)
                exit(0)
            }
            return
        }

        // --demo-gemini-explain — fires explainDanger live, shows result in bubble
        if args.contains("--demo-gemini-explain") {
            let dwellSec = parseDwellSeconds(args, default: 12)
            panel.speak("🤖 Gemini explain 호출중...", emotion: .talking, autoHide: 60.0)
            let client = GeminiClient(apiKey: apiKey)
            Task { @MainActor in
                let explanation = await client.explainDanger(command: "rm -rf /var/log")
                if let exp = explanation, !exp.isEmpty {
                    self.panel.speak(exp, emotion: .alarmed, autoHide: 60.0)
                } else {
                    self.panel.speak("❌ Gemini 응답 실패 (network/key 이슈)", emotion: .nagging, autoHide: 60.0)
                }
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

        watcher = ScreenWatcher(
            apiKey: apiKey,
            onComment: { [weak self] comment in
                Task { @MainActor in
                    self?.panel.speak(comment)
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
        let configDir = PathMigration.configDirURL()
        let keyPath = configDir.appendingPathComponent("api-key.txt")
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
    objc_setAssociatedObject(app, "gojipsaDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    app.run()
}
