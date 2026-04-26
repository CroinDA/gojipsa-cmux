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

    private let cmuxPath: String
    private let cmuxPassword: String
    private let mySurface: String
    private let gemini: GeminiClient
    private var lastScreen: String = ""
    private var lastChangeAt = Date()
    private var lastNagAt = Date.distantPast
    private var lastCommentAt = Date.distantPast
    private var lastAlarmedPattern: String = ""
    private var lastAlarmedAt = Date.distantPast
    private var lastAnalyzedScreen: String = ""
    private let onComment: @Sendable (Comment) -> Void
    private let onAlarm: @Sendable (DangerAlarm) -> Void

    public init(
        apiKey: String,
        onComment: @escaping @Sendable (Comment) -> Void,
        onAlarm: @escaping @Sendable (DangerAlarm) -> Void
    ) {
        self.cmuxPath = ScreenWatcher.locateCmux()
        self.cmuxPassword = ScreenWatcher.loadCmuxPassword()
        self.mySurface = ProcessInfo.processInfo.environment["CMUX_SURFACE_ID"] ?? ""
        self.gemini = GeminiClient(apiKey: apiKey)
        self.onComment = onComment
        self.onAlarm = onAlarm
    }

    /// Loads cmux socket password (for cmux's password-auth mode).
    /// Order: CMUX_SOCKET_PASSWORD env var → ~/.sentinel/cmux-password.txt → empty
    /// Empty result is fine if cmux is in default mode (PID-ancestry auth).
    public static func loadCmuxPassword() -> String {
        if let env = ProcessInfo.processInfo.environment["CMUX_SOCKET_PASSWORD"], !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".sentinel/cmux-password.txt")

        // Defense-in-depth: warn if password file has loose permissions.
        // We still read it (don't break the demo), but emit a warning so the user fixes it.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let perm = attrs[.posixPermissions] as? NSNumber {
            let mode = perm.intValue & 0o777
            if mode & 0o077 != 0 {  // any group/other bits set
                let warning = "⚠️  \(path.path) has loose perms (0\(String(mode, radix: 8))). Run: chmod 600 \(path.path)\n"
                FileHandle.standardError.write(Data(warning.utf8))
            }
        }

        if let data = try? Data(contentsOf: path),
           let str = String(data: data, encoding: .utf8) {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
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

        // Skip if screen hasn't meaningfully changed since the last analyze —
        // avoids burning API calls on a static screen and prevents the bubble
        // from getting stuck repeating itself.
        let analyzeKey = String(screen.suffix(2000))
        if analyzeKey == lastAnalyzedScreen { return }
        lastAnalyzedScreen = analyzeKey

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

    /// Detailed result of a cmux subprocess invocation.
    private struct CmuxRunResult: Sendable {
        let exitCode: Int32?      // nil if launch failed before exec
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    /// Hardened: catches launch errors, reads stderr, applies a 5s timeout.
    /// Public consumers still get `String?` via the convenience wrapper below.
    private func runCmuxDetailed(args: [String], timeout: TimeInterval = 5.0) async -> CmuxRunResult {
        await withCheckedContinuation { (cont: CheckedContinuation<CmuxRunResult, Never>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: cmuxPath)
            proc.arguments = args
            if !cmuxPassword.isEmpty {
                var env = ProcessInfo.processInfo.environment
                env["CMUX_SOCKET_PASSWORD"] = cmuxPassword
                proc.environment = env
            }
            let outPipe = Pipe(), errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            do {
                try proc.run()
            } catch {
                cont.resume(returning: CmuxRunResult(
                    exitCode: nil,
                    stdout: "",
                    stderr: "Process.run failed: \(error.localizedDescription)",
                    timedOut: false
                ))
                return
            }

            // Timeout watchdog — terminate if cmux hangs
            let timedOut = ManagedFlag()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if proc.isRunning {
                    timedOut.set()
                    proc.terminate()
                }
            }

            DispatchQueue.global().async {
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                cont.resume(returning: CmuxRunResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    timedOut: timedOut.isSet
                ))
            }
        }
    }

    /// Backwards-compatible wrapper — returns nil on any non-zero exit.
    private func runCmux(args: [String]) async -> String? {
        let result = await runCmuxDetailed(args: args)
        return result.exitCode == 0 ? result.stdout : nil
    }

    /// Quick status check — typically sub-second when cmux is healthy.
    /// Distinguishes between binary missing, server down, access denied,
    /// password rejected, timeout, and unknown.
    public func checkStatus() async -> CmuxStatusReport {
        if cmuxPath.isEmpty {
            return CmuxStatusReport(status: .binaryNotFound,
                                    details: "cmux not found in /Applications, /opt/homebrew/bin, /usr/local/bin, or PATH",
                                    cmuxPath: "",
                                    usingPassword: false)
        }
        let result = await runCmuxDetailed(args: ["ping"], timeout: 3.0)
        let status: CmuxStatus = result.timedOut
            ? .timeout
            : CmuxStatusClassifier.classify(exitCode: result.exitCode,
                                            stdout: result.stdout,
                                            stderr: result.stderr)
        let details = result.timedOut
            ? "ping timed out after 3s"
            : (result.stderr.isEmpty ? result.stdout : result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        return CmuxStatusReport(
            status: status,
            details: String(details.prefix(200)),
            cmuxPath: cmuxPath,
            usingPassword: !cmuxPassword.isEmpty
        )
    }

    /// Static convenience: lets `--status` flag in main.swift run a check
    /// without constructing a full ScreenWatcher (no callbacks needed).
    public static func quickStatus() async -> CmuxStatusReport {
        let path = locateCmux()
        let password = loadCmuxPassword()
        // Use a temporary lightweight watcher instance just for the check
        let temp = ScreenWatcher(
            apiKey: "",
            onComment: { _ in },
            onAlarm: { _ in }
        )
        _ = path; _ = password   // suppress unused warnings (loaded inside init)
        return await temp.checkStatus()
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

/// Tiny thread-safe boolean — used by the cmux subprocess timeout watchdog.
private final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
