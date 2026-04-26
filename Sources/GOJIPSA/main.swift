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
    // Prevents macOS App Nap / background throttling while monitoring the terminal.
    var activityToken: NSObjectProtocol?

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

        // Keep this process alive and un-throttled regardless of visibility.
        // Without this macOS App Nap suspends the polling loop after ~5 min of inactivity.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.background, .idleSystemSleepDisabled],
            reason: "꼬집사 터미널 모니터링"
        )

        panel = OverlayPanel()
        panel.show()
        panel.speak("👀 꼬집사 깼어. 터미널 보고 있을게.", emotion: .idle)

        alarm = AlarmPanel()
        // Always-visible menu bar item — green/red dot reflects cmux state,
        // click to see status / quit GOJIPSA.
        statusBar = StatusBarController()

        // ─── Startup health check — surface cmux status visually so the user
        //     immediately knows if GOJIPSA can actually read their terminal.
        //     Suppressed when running with any --demo-* flag so manual feature demos
        //     are not polluted by status overrides. ───
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

        // ─── Manual demo entry points ───
        // Available in both debug and release so users can verify lottie mappings
        // visually with `GOJIPSA --demo-speak ... --emotion <name>`.
        let args = CommandLine.arguments
        if args.contains("--demo-overlay") {
            panel.speak("🧪 Demo — overlay ready", emotion: .talking)
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

        if args.contains("--demo-hackathon-deadlines") {
            let dwellSec = parseDwellSeconds(args, default: 30)
            let tickSec = parseIntArg(args, name: "--demo-tick", default: 5, range: 1...15)
            let stepMinutes = parseIntArg(args, name: "--demo-step-minutes", default: 0, range: 0...180)
            let start = parseDemoClock(args) ?? Date()
            Task { @MainActor in
                await self.runHackathonDeadlineNaggingDemo(
                    start: start,
                    dwellSec: dwellSec,
                    tickSec: tickSec,
                    stepMinutes: stepMinutes
                )
                exit(0)
            }
            return
        }

        if args.contains("--demo-alarm") {
            alarm.showAlarm(
                pattern: "rm -rf /tmp/demo",
                warning: "🛑 [Demo] 위험 감지!",
                explanation: "이건 데모용 더미 alarm. 5초 후 자동 닫힘.",
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
                    self?.statusBar.noteActivity()
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
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
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

    private func parseIntArg(_ args: [String], name: String, default fallback: Int, range: ClosedRange<Int>) -> Int {
        if let idx = args.firstIndex(of: name),
           idx + 1 < args.count,
           let n = Int(args[idx + 1]),
           range.contains(n) {
            return n
        }
        return fallback
    }

    private func parseDemoClock(_ args: [String]) -> Date? {
        guard let idx = args.firstIndex(of: "--demo-now"),
              idx + 1 < args.count else {
            return nil
        }

        let parts = args[idx + 1].split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.hackathonTimeZone
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private struct HackathonEvent {
        let hour: Int
        let minute: Int
        let title: String
        let advice: String

        var minuteOfDay: Int { hour * 60 + minute }
        var clock: String { String(format: "%02d:%02d", hour, minute) }
    }

    private struct HackathonNag {
        let text: String
        let emotion: Emotion
    }

    private static let hackathonTimeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

    private static let hackathonEvents: [HackathonEvent] = [
        HackathonEvent(
            hour: 8,
            minute: 0,
            title: "입장 · 아침 식사",
            advice: "커피, 물, 충전기부터 챙겨. 굶고 해킹하면 코드가 먼저 쓰러진다."
        ),
        HackathonEvent(
            hour: 8,
            minute: 30,
            title: "오프닝",
            advice: "룰 듣자. 나중에 '몰랐어요' 금지."
        ),
        HackathonEvent(
            hour: 9,
            minute: 0,
            title: "해킹 시작",
            advice: "MVP 세로 흐름부터 꽂아. 예쁜 꿈은 테스트 통과 뒤에 꾸자."
        ),
        HackathonEvent(
            hour: 13,
            minute: 0,
            title: "점심",
            advice: "밥 먹기 전에 빌드 하나 돌려놓고 가."
        ),
        HackathonEvent(
            hour: 18,
            minute: 0,
            title: "제출 마감 · 저녁 식사 · 1차 심사 시작",
            advice: "새 기능 금지. 빌드, README, 데모 플로우만 정리해."
        ),
        HackathonEvent(
            hour: 19,
            minute: 25,
            title: "파이널리스트 6팀 발표",
            advice: "불리면 바로 움직여야 해. 발표 파일, 데모 화면, 충전기 확인."
        ),
        HackathonEvent(
            hour: 19,
            minute: 30,
            title: "파이널 피칭",
            advice: "첫 문장은 짧게. 문제, 데모, 임팩트 순서로 말해."
        ),
        HackathonEvent(
            hour: 20,
            minute: 0,
            title: "수상자 발표",
            advice: "숨 쉬어도 돼. 그래도 릴리즈 태그랑 데모 링크는 확인하고 쉬자."
        ),
    ]

    private func runHackathonDeadlineNaggingDemo(
        start: Date,
        dwellSec: Int,
        tickSec: Int,
        stepMinutes: Int
    ) async {
        let end = Date().addingTimeInterval(TimeInterval(dwellSec))
        var virtualNow = start

        while Date() < end {
            let nag = hackathonNag(at: virtualNow)
            panel.speak(nag.text, emotion: nag.emotion, autoHide: TimeInterval(dwellSec + 5))

            let remaining = end.timeIntervalSinceNow
            if remaining <= 0 { break }
            let sleepSeconds = min(TimeInterval(tickSec), remaining)
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))

            if stepMinutes > 0 {
                virtualNow = virtualNow.addingTimeInterval(TimeInterval(stepMinutes * 60))
            }
        }
    }

    private func hackathonNag(at date: Date) -> HackathonNag {
        let minute = minuteOfDay(from: date)
        let clock = clockText(from: date)
        let events = Self.hackathonEvents

        if let current = events.first(where: { $0.minuteOfDay == minute }) {
            return nagForCurrentEvent(current, clock: clock)
        }

        if let recent = events.last(where: { $0.minuteOfDay < minute }),
           minute - recent.minuteOfDay <= 10 {
            return nagForJustPassedEvent(recent, clock: clock)
        }

        guard let next = events.first(where: { $0.minuteOfDay > minute }) else {
            return HackathonNag(
                text: "\(clock) KST · 오늘 공식 일정 끝. 이제 데모 링크, 릴리즈 태그, README 상태만 마지막으로 확인해.",
                emotion: .celebrating
            )
        }

        let remaining = next.minuteOfDay - minute
        return nagForUpcomingEvent(next, remaining: remaining, clock: clock)
    }

    private func nagForCurrentEvent(_ event: HackathonEvent, clock: String) -> HackathonNag {
        if event.title.contains("제출 마감") {
            return HackathonNag(
                text: "\(clock) KST · 지금 \(event.clock) \(event.title). 손 떼고 제출 상태부터 확인해. \(event.advice)",
                emotion: .alarmed
            )
        }
        return HackathonNag(
            text: "\(clock) KST · 지금 \(event.clock) \(event.title). \(event.advice)",
            emotion: event.title.contains("수상자") ? .celebrating : .nagging
        )
    }

    private func nagForJustPassedEvent(_ event: HackathonEvent, clock: String) -> HackathonNag {
        if event.title.contains("제출 마감") {
            return HackathonNag(
                text: "\(clock) KST · \(event.clock) 제출 마감 방금 지났어. 제출 확인, 빌드 링크, 데모 파일 깨졌는지부터 봐.",
                emotion: .alarmed
            )
        }
        if event.title.contains("파이널리스트") {
            return HackathonNag(
                text: "\(clock) KST · \(event.clock) 파이널리스트 발표 직후야. 이름 불리면 19:30 피칭까지 5분도 없어.",
                emotion: .nagging
            )
        }
        if event.title.contains("파이널 피칭") {
            return HackathonNag(
                text: "\(clock) KST · \(event.clock) 파이널 피칭 들어갔어. 데모는 짧게, 임팩트는 크게.",
                emotion: .talking
            )
        }
        return HackathonNag(
            text: "\(clock) KST · \(event.clock) \(event.title) 지나갔어. 다음 일정 보고 바로 움직여.",
            emotion: .talking
        )
    }

    private func nagForUpcomingEvent(_ event: HackathonEvent, remaining: Int, clock: String) -> HackathonNag {
        if event.title.contains("제출 마감") {
            if remaining <= 5 {
                return HackathonNag(
                    text: "\(clock) KST · 제출 마감 \(remaining)분 남았어. 지금은 커밋, 태그, 업로드만. 새 코드 만지면 내가 진짜 꼬집는다.",
                    emotion: .alarmed
                )
            }
            if remaining <= 30 {
                let remainingText = remaining == 30 ? "정확히 30분" : "\(durationText(minutes: remaining))"
                return HackathonNag(
                    text: "\(clock) KST · 제출 마감 30분 전 모드야. 실제로 \(remainingText) 남았어. 새 기능 금지. 빌드, README, 데모 플로우만 정리해.",
                    emotion: .nagging
                )
            }
            return HackathonNag(
                text: "\(clock) KST · \(event.clock) \(event.title)까지 \(durationText(minutes: remaining)). \(event.advice)",
                emotion: .talking
            )
        }

        if remaining <= 10 {
            return HackathonNag(
                text: "\(clock) KST · \(event.clock) \(event.title)까지 \(durationText(minutes: remaining)). \(event.advice)",
                emotion: .nagging
            )
        }

        return HackathonNag(
            text: "\(clock) KST · 다음은 \(event.clock) \(event.title)까지 \(durationText(minutes: remaining)). \(event.advice)",
            emotion: event.title.contains("수상자") ? .celebrating : .talking
        )
    }

    private func minuteOfDay(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.hackathonTimeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func clockText(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.hackathonTimeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func durationText(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)분" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(mins)분"
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
