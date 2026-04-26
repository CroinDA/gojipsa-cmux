import Foundation

/// Full-screen alarm payload — distinct from Comment (which is the small bubble).
public struct DangerAlarm: Sendable {
    public let pattern: String
    public let warning: String
    public let explanation: String?

    public init(pattern: String, warning: String, explanation: String? = nil) {
        self.pattern = pattern
        self.warning = warning
        self.explanation = explanation
    }
}

public actor ScreenWatcher {
    // Tunable cadence
    public static let pollIntervalNanos: UInt64 = 1_000_000_000   // 1s — fast danger detection
    // Gemini analyze() rate — user requested 1s reactions. With pollInterval=1s
    // and the change-detection guard, this caps API calls at ~60/min when screen
    // is constantly changing (within Gemini 2.5 Flash free tier's 60 RPM limit).
    public static let geminiThrottleSec: TimeInterval = 1
    public static let dangerCooldownSec: TimeInterval = 30         // suppress repeat alarm on same pattern
    public static let nagAfterIdleSec: TimeInterval = 90
    public static let nagThrottleSec: TimeInterval = 180

    private let cmuxClient: CmuxClient
    private let contextProvider: CmuxTerminalContextProvider
    private let gemini: GeminiClient
    private var lastScreen: String = ""
    private var lastChangeAt = Date()
    private var lastNagAt = Date.distantPast
    private var lastCommentAt = Date.distantPast
    private var lastAlarmedPattern: String = ""
    private var lastAlarmedAt = Date.distantPast
    private var lastAnalyzedScreen: String = ""
    private var lastGeminiAttemptAt = Date.distantPast  // retry gate after Gemini failure
    private let onComment: @Sendable (Comment) -> Void
    private let onAlarm: @Sendable (DangerAlarm) -> Void

    public init(
        apiKey: String,
        onComment: @escaping @Sendable (Comment) -> Void,
        onAlarm: @escaping @Sendable (DangerAlarm) -> Void
    ) {
        let cmuxConfiguration = CmuxConfiguration.current()
        let cmuxClient = CmuxClient(configuration: cmuxConfiguration)
        self.cmuxClient = cmuxClient
        self.contextProvider = CmuxTerminalContextProvider(
            client: cmuxClient,
            ownSurfaceID: cmuxConfiguration.currentSurfaceID
        )
        self.gemini = GeminiClient(apiKey: apiKey)
        self.onComment = onComment
        self.onAlarm = onAlarm
    }

    /// cmux socket password를 로딩합니다.
    ///
    /// 실제 구현은 `CmuxConfiguration`에 위임합니다. 기존 외부 호출자가
    /// `ScreenWatcher.loadCmuxPassword()`를 계속 사용할 수 있도록 남겨둔 호환 API입니다.
    public static func loadCmuxPassword() -> String {
        CmuxConfiguration.loadPassword()
    }

    public func run() async {
        guard cmuxClient.isConfigured else {
            onComment(Comment(text: "cmux를 찾을 수 없어. cmux 안에서 실행해줘.", emotion: .alarmed, shouldReact: true))
            return
        }
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: ScreenWatcher.pollIntervalNanos)
        }
    }

    private func tick() async {
        let screen = await contextProvider.readContext()
        guard !screen.isEmpty else { return }

        // Fast-path: dangerous pattern (regex, ~ms).
        // Scan the recent tail (last 2000 chars) so old scrollback doesn't keep
        // matching the same pattern forever and starve Gemini analyze().
        let recentTail = String(screen.suffix(2000))
        if let danger = DangerDetector.scan(recentTail) {
            // Suppress "keystroke storm": as user types `rm -rf /tmp` then `rm -rf /tmp/foo`,
            // both match — but second is just an extension of the first. Treat as same alarm.
            let isVariationOfLast = !lastAlarmedPattern.isEmpty &&
                (danger.pattern.hasPrefix(lastAlarmedPattern) ||
                 lastAlarmedPattern.hasPrefix(danger.pattern))
            let cooledDown = Date().timeIntervalSince(lastAlarmedAt) > ScreenWatcher.dangerCooldownSec
            let shouldFire = cooledDown || !isVariationOfLast
            if shouldFire {
                lastAlarmedPattern = danger.pattern
                lastAlarmedAt = Date()
                lastCommentAt = Date()
                onComment(Comment(text: danger.warning, emotion: danger.emotion, shouldReact: true))
                onAlarm(DangerAlarm(pattern: danger.pattern, warning: danger.warning, explanation: nil))
                let pat = danger.pattern, warn = danger.warning
                let local = self.gemini
                let cb = self.onAlarm
                Task.detached {
                    if let exp = await local.explainDanger(command: pat) {
                        cb(DangerAlarm(pattern: pat, warning: warn, explanation: exp))
                    }
                }
                // We just fired — bail this tick so the alarm gets full focus
                lastScreen = screen
                lastChangeAt = Date()
                return
            }
            // Pattern still present but cooldown active or just a typing variation.
            // Fall through to Gemini analyze() below so the bubble keeps reflecting
            // whatever the user is ACTUALLY working on now (not stuck on the old danger).
        }

        // Idle detection
        if screen != lastScreen {
            lastScreen = screen
            lastChangeAt = Date()
        } else {
            let idleSec = Date().timeIntervalSince(lastChangeAt)
            if idleSec > ScreenWatcher.nagAfterIdleSec,
               Date().timeIntervalSince(lastNagAt) > ScreenWatcher.nagThrottleSec {
                onComment(Comment(text: "조용하네... 막힌거야 아니면 농땡이?", emotion: .nagging, shouldReact: true))
                lastNagAt = Date()
                return
            }
        }

        // Throttle Gemini analyze() — keep API cost predictable
        if Date().timeIntervalSince(lastCommentAt) < ScreenWatcher.geminiThrottleSec { return }

        // Skip if screen hasn't changed since last analyze —
        // but retry after 30s in case the previous Gemini call failed silently.
        let analyzeKey = String(screen.suffix(2000))
        if analyzeKey == lastAnalyzedScreen {
            if Date().timeIntervalSince(lastGeminiAttemptAt) < 30 { return }
        }
        lastAnalyzedScreen = analyzeKey
        lastGeminiAttemptAt = Date()

        let redacted = SecretRedactor.redact(screen)
        if let comment = await gemini.analyze(screen: redacted) {
            onComment(comment)
            lastCommentAt = Date()
        }
    }

    /// Quick status check — typically sub-second when cmux is healthy.
    /// Distinguishes between binary missing, server down, access denied,
    /// password rejected, timeout, and unknown.
    public func checkStatus() async -> CmuxStatusReport {
        if !cmuxClient.isConfigured {
            return CmuxStatusReport(status: .binaryNotFound,
                                    details: "cmux not found in /Applications, /opt/homebrew/bin, /usr/local/bin, or PATH",
                                    cmuxPath: "",
                                    usingPassword: false)
        }
        let result = await cmuxClient.ping(timeout: 3.0)
        var status: CmuxStatus = result.timedOut
            ? .timeout
            : CmuxStatusClassifier.classify(exitCode: result.exitCode,
                                            stdout: result.stdout,
                                            stderr: result.stderr)
        var details = result.timedOut
            ? "ping timed out after 3s"
            : (result.stderr.isEmpty ? result.stdout : result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)

        if status == .connected {
            let canReadContext = await contextProvider.canReadAnyTerminalSurface(limit: 1)
            if !canReadContext {
                status = .contextUnavailable
                details = "cmux socket is reachable, but no terminal surface could be read"
            }
        }

        return CmuxStatusReport(
            status: status,
            details: String(details.prefix(200)),
            cmuxPath: cmuxClient.configuration.executablePath,
            usingPassword: !cmuxClient.configuration.password.isEmpty
        )
    }

    /// Static convenience: lets `--status` flag in main.swift run a check
    /// without constructing a full ScreenWatcher (no callbacks needed).
    public static func quickStatus() async -> CmuxStatusReport {
        let temp = ScreenWatcher(
            apiKey: "",
            onComment: { _ in },
            onAlarm: { _ in }
        )
        return await temp.checkStatus()
    }
}
