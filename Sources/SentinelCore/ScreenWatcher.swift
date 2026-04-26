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
    public static let geminiThrottleSec: TimeInterval = 12         // ≤ 1 analyze() per 12s
    public static let dangerCooldownSec: TimeInterval = 30         // suppress repeat alarm on same pattern
    public static let nagAfterIdleSec: TimeInterval = 90
    public static let nagThrottleSec: TimeInterval = 180

    private let cmuxPath: String
    private let mySurface: String
    private let gemini: GeminiClient
    private var lastScreen: String = ""
    private var lastChangeAt = Date()
    private var lastNagAt = Date.distantPast
    private var lastCommentAt = Date.distantPast
    private var lastAlarmedPattern: String = ""
    private var lastAlarmedAt = Date.distantPast
    private let onComment: @Sendable (Comment) -> Void
    private let onAlarm: @Sendable (DangerAlarm) -> Void

    public init(
        apiKey: String,
        onComment: @escaping @Sendable (Comment) -> Void,
        onAlarm: @escaping @Sendable (DangerAlarm) -> Void
    ) {
        self.cmuxPath = ScreenWatcher.locateCmux()
        self.mySurface = ProcessInfo.processInfo.environment["CMUX_SURFACE_ID"] ?? ""
        self.gemini = GeminiClient(apiKey: apiKey)
        self.onComment = onComment
        self.onAlarm = onAlarm
    }

    public func run() async {
        guard !cmuxPath.isEmpty else {
            onComment(Comment(text: "cmux를 찾을 수 없어. cmux 안에서 실행해줘.", emotion: .alarmed, shouldReact: true))
            return
        }
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: ScreenWatcher.pollIntervalNanos)
        }
    }

    private func tick() async {
        let screen = await readOtherSurfaces()
        guard !screen.isEmpty else { return }

        // Fast-path: dangerous pattern (regex, ~ms)
        if let danger = DangerDetector.scan(screen) {
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
                // 1) Show small bubble immediately (canned warning)
                onComment(Comment(text: danger.warning, emotion: danger.emotion, shouldReact: true))
                // 2) Trigger full-screen alarm right away with placeholder explanation; refine async
                onAlarm(DangerAlarm(pattern: danger.pattern, warning: danger.warning, explanation: nil))
                // 3) Fetch natural-language explanation from Gemini in background, dispatch updated alarm
                let pat = danger.pattern, warn = danger.warning
                let local = self.gemini
                let cb = self.onAlarm
                Task.detached {
                    if let exp = await local.explainDanger(command: pat) {
                        cb(DangerAlarm(pattern: pat, warning: warn, explanation: exp))
                    }
                }
            }
            // Update screen state and bail — no Gemini analyze() on dangerous content
            lastScreen = screen
            lastChangeAt = Date()
            return
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

        let redacted = SecretRedactor.redact(screen)
        if let comment = await gemini.analyze(screen: redacted) {
            onComment(comment)
            lastCommentAt = Date()
        }
    }

    private func readOtherSurfaces() async -> String {
        let surfaces = await listSurfaces()
        let others = surfaces.filter { !$0.isEmpty && !$0.contains(mySurface) }

        if others.isEmpty {
            return await runCmux(args: ["read-screen"]) ?? ""
        }

        var combined: [String] = []
        for s in others.prefix(3) {
            if let txt = await runCmux(args: ["read-screen", "--surface", s]), !txt.isEmpty {
                let trimmed = String(txt.suffix(2000))
                combined.append("=== surface \(s) ===\n\(trimmed)")
            }
        }
        return combined.joined(separator: "\n\n")
    }

    private func listSurfaces() async -> [String] {
        guard let tree = await runCmux(args: ["tree"]) else { return [] }
        let pattern = #"surface:[\w-]+|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsrange = NSRange(tree.startIndex..<tree.endIndex, in: tree)
        let matches = re.matches(in: tree, options: [], range: nsrange)
        let ids = matches.compactMap { Range($0.range, in: tree).map { String(tree[$0]) } }
        // Dedup preserving order
        var seen = Set<String>(), uniq: [String] = []
        for id in ids where seen.insert(id).inserted { uniq.append(id) }
        return uniq
    }

    private func runCmux(args: [String]) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: cmuxPath)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()

            do { try proc.run() } catch {
                cont.resume(returning: nil); return
            }
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    cont.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private static func locateCmux() -> String {
        let candidates = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "/opt/homebrew/bin/cmux",
            "/usr/local/bin/cmux"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fallback: PATH lookup via /usr/bin/which
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["cmux"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return FileManager.default.isExecutableFile(atPath: str) ? str : ""
        } catch {
            return ""
        }
    }
}
