import Foundation

public struct Comment {
    public let text: String
    public let emotion: Emotion
    public let shouldReact: Bool
    /// Lottie file name (without .lottie) chosen by Gemini. Overrides emotion.lottieName when set.
    public let lottie: String?

    public init(text: String, emotion: Emotion, shouldReact: Bool, lottie: String? = nil) {
        self.text = text
        self.emotion = emotion
        self.shouldReact = shouldReact
        self.lottie = lottie
    }
}

public actor GeminiClient {
    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    public init(apiKey: String, model: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    /// Explain a dangerous command in natural Korean.
    /// Returns: 1-2 sentence explanation including WHY it's dangerous + a safer alternative.
    /// Returns nil on API failure or missing key (caller should fall back to canned warning).
    public func explainDanger(command: String) async -> String? {
        guard !apiKey.isEmpty else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let systemPrompt = """
        You are 꼬집사 (GOJIPSA) — a sassy Korean AI butler that pinches developers when they're about to do something dangerous.
        The user is about to run a dangerous command.
        Reply in Korean (반말, friendly but urgent).
        ONE OR TWO short sentences. No JSON, no markdown — plain text only.
        Cover: (1) WHY it's risky, (2) a safer alternative if one exists.
        Be specific to the actual command — not generic.
        """
        let userPrompt = "Dangerous command:\n\n\(trimmed.suffix(500))"

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userPrompt]]]],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 200,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return parsePlainText(data)
        } catch {
            return nil
        }
    }

    private func parsePlainText(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    public func analyze(screen: String) async -> Comment? {
        guard !apiKey.isEmpty else { return nil }
        guard !screen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let systemPrompt = """
        You are 꼬집사 (GOJIPSA, "Pinch Butler") — a sassy Korean AI butler
        living on top of a developer's terminal. Analyze the screen and react
        with a witty Korean one-liner AND pick the most fitting animation.

        ## Available Animations (pick exactly one for "lottie")
        - "note_taking"       — thinking, writing, reviewing code quietly
        - "Checking"          — explaining, talking, narrating what's on screen
        - "frightening"       — scared, alarmed, danger detected
        - "happy"             — celebrating, build success, tests passed
        - "nagging"           — scolding, complaining, repeating the same mistake
        - "sleepy"            — bored, slow progress, waiting for something
        - "angry"             — frustrated, something is clearly broken or wrong
        - "crying"            — devastated, catastrophic failure, data loss risk
        - "walking"           — neutral activity, just moving along, routine task
        - "dancing"           — ecstatic, major milestone, exceptional success
        - "nodding_sighingly" — resigned sigh, "again?", tired but not angry

        ## Tone & Rules
        - Casual Korean (반말), witty, slightly annoying but lovable
        - comment: ONE sentence, under 80 characters, no line breaks
        - Pick the animation that BEST matches the mood — use the full range
        - should_react = false ONLY if screen is genuinely empty/blank
        - state: semantic bucket for bubble color only (idle/talking/alarmed/sleeping/celebrating/nagging)

        ## Examples
        - rm -rf detected       → lottie: "crying",            state: "alarmed",     comment: "야!! 그거 진짜 지워지는 거야!"
        - build succeeded       → lottie: "dancing",           state: "celebrating", comment: "오 빌드 터졌다~ 진짜 됐어?"
        - same error 3rd time   → lottie: "nodding_sighingly", state: "nagging",     comment: "또 그 에러야... 진짜"
        - git push --force      → lottie: "frightening",       state: "alarmed",     comment: "포스 푸시?! 팀원들 다 죽는다고"
        - slow compile          → lottie: "sleepy",            state: "sleeping",    comment: "빌드 또 길어지네... 커피나 마셔"
        - npm install running   → lottie: "walking",           state: "idle",        comment: "node_modules 다운 중... 오래 걸리겠다"
        - crash / panic         → lottie: "angry",             state: "alarmed",     comment: "크래시났네. 스택 트레이스 봐봐"
        - reviewing code        → lottie: "note_taking",       state: "idle",        comment: "코드 보는 중? 뭔가 냄새 나는데"

        Respond with ONLY valid JSON. No markdown, no code fences.
        Format: {"should_react": bool, "state": "idle|talking|alarmed|sleeping|celebrating|nagging", "lottie": string, "comment": string, "trigger_type": string}
        """
        let userPrompt = "Recent terminal screen content:\n\n\(screen.suffix(2000))"

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": userPrompt]]]],
            "generationConfig": [
                "temperature": 0.9,
                "maxOutputTokens": 256,
                "responseMimeType": "application/json",
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return parse(data)
        } catch {
            return nil
        }
    }

    private func parse(_ data: Data) -> Comment? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }
        // Defensive: strip ```json ... ``` markdown wrapping if present
        let cleaned = stripMarkdownFence(text)
        guard let json = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return nil
        }
        let shouldReact = parsed["should_react"] as? Bool ?? false
        let comment = (parsed["comment"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stateRaw = parsed["state"] as? String ?? "talking"
        guard shouldReact, !comment.isEmpty else { return nil }
        let emotion = Emotion(rawValue: stateRaw) ?? Emotion(stateName: stateRaw)
        let lottieRaw = (parsed["lottie"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lottie = (lottieRaw?.isEmpty == false) ? lottieRaw : nil
        return Comment(text: comment, emotion: emotion, shouldReact: true, lottie: lottie)
    }
}

private func stripMarkdownFence(_ text: String) -> String {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("```") {
        if let firstNewline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: firstNewline)...])
        }
        if t.hasSuffix("```") {
            t = String(t.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return t
}

private extension Emotion {
    init(stateName: String) {
        switch stateName.lowercased() {
        case "idle": self = .idle
        case "talking": self = .talking
        case "alarmed": self = .alarmed
        case "sleeping": self = .sleeping
        case "celebrating": self = .celebrating
        case "nagging": self = .nagging
        default: self = .talking
        }
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        comps.queryItems = (comps.queryItems ?? []) + queryItems
        return comps.url ?? self
    }
}
