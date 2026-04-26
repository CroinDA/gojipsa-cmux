import Foundation

actor ScreenWatcher {
    private let cmuxPath: String
    private let mySurface: String
    private let danger = DangerDetector.self
    private let gemini: GeminiClient
    private var lastScreen: String = ""
    private var lastChangeAt = Date()
    private var lastNagAt = Date.distantPast
    private var lastCommentAt = Date.distantPast
    private let onComment: @Sendable (Comment) -> Void

    init(apiKey: String, onComment: @escaping @Sendable (Comment) -> Void) {
        self.cmuxPath = ScreenWatcher.locateCmux()
        self.mySurface = ProcessInfo.processInfo.environment["CMUX_SURFACE_ID"] ?? ""
        self.gemini = GeminiClient(apiKey: apiKey)
        self.onComment = onComment
    }

    func run() async {
        guard !cmuxPath.isEmpty else {
            onComment(Comment(text: "cmux를 찾을 수 없어. cmux 안에서 실행해줘.", emotion: .alarmed, shouldReact: true))
            return
        }
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func tick() async {
        let screen = await readOtherSurfaces()
        guard !screen.isEmpty else { return }

        if let danger = DangerDetector.scan(screen) {
            // De-dup: only fire on new content
            if screen != lastScreen {
                onComment(Comment(text: danger.warning, emotion: danger.emotion, shouldReact: true))
                lastCommentAt = Date()
            }
        }

        // Detect change vs idle
        if screen != lastScreen {
            lastScreen = screen
            lastChangeAt = Date()
        } else {
            let idleSec = Date().timeIntervalSince(lastChangeAt)
            if idleSec > 90, Date().timeIntervalSince(lastNagAt) > 180 {
                onComment(Comment(text: "조용하네... 막힌거야 아니면 농땡이?", emotion: .nagging, shouldReact: true))
                lastNagAt = Date()
                return
            }
        }

        // Throttle Gemini: at most once every 12 seconds
        if Date().timeIntervalSince(lastCommentAt) < 12 { return }

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
