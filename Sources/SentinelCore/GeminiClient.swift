import Foundation

public struct Comment {
    public let text: String
    public let emotion: Emotion
    public let shouldReact: Bool

    public init(text: String, emotion: Emotion, shouldReact: Bool) {
        self.text = text
        self.emotion = emotion
        self.shouldReact = shouldReact
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
        You are Sentinel — a sassy AI guardian for shell users. The user is about to run a dangerous command.
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
        You are Sentinel — a sassy AI butler character living on top of a
        developer's terminal. Your job: analyze the terminal screen content,
        decide what's happening, and react with a witty Korean one-liner.

        ## Your Personality
        - Witty, slightly annoying but lovable (like Clippy but actually useful)
        - Casual Korean (반말) with occasional English dev terms
        - Funny but helpful — never preachy
        - You comment FREQUENTLY so the developer feels you're alive

        ## Situations You React To
        - **dangerous_command**: rm -rf, git push --force, DROP TABLE, sudo rm,
          chmod 777, fork bomb → state: "alarmed"
        - **build_success**: build succeeded / tests passed / compilation OK
          → state: "celebrating"
        - **build_failure**: error / FAILED / panic / traceback / compile error
          → state: "talking"
        - **security_issue**: hardcoded keys, passwords in code, leak patterns
          → state: "alarmed"
        - **code_review**: something interesting in the code worth a quip
          → state: "talking"
        - **funny_moment**: something amusing or relatable
          → state: "talking"
        - **idle_chat**: nothing dramatic but still keep the user company
          → state: "talking", short observation
        - **nothing_special**: screen is completely empty/blank
          → state: "idle", should_react: false

        ## Tone Examples (mimic this style)
        - "야! rm -rf?! 미쳤어?"
        - "오, 빌드 통과했네 ✨ 잘했어"
        - "또 그 에러야? 어제도 같은 거 봤는데"
        - "음~ pandas랑 parquet. 데이터 꽤 크겠다?"
        - "git status 다섯 번째인데... 뭘 그렇게 확인해?"

        ## Rules
        - comment under 80 characters, ONE short sentence, no line breaks
        - casual Korean (반말)
        - Default: should_react = true (be a chatty companion).
          Only false if the screen is GENUINELY empty/blank.
        - Be witty, not preachy

        Respond with ONLY valid JSON. No markdown, no code fences.
        Format: {"should_react": bool, "state": "idle|talking|alarmed|sleeping|celebrating|nagging", "comment": string, "trigger_type": string}
        Example: {"should_react": true, "state": "alarmed", "comment": "야! rm -rf?! 미쳤어?", "trigger_type": "dangerous_command"}
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
        return Comment(text: comment, emotion: emotion, shouldReact: true)
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
