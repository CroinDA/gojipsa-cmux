import Foundation

struct Danger {
    let pattern: String
    let warning: String
    let emotion: Emotion = .alarmed
}

enum DangerDetector {
    private static let rules: [(NSRegularExpression, String)] = build()

    private static func build() -> [(NSRegularExpression, String)] {
        let raw: [(String, String)] = [
            (#"rm\s+-rf?\s+/\S*"#,                "🛑 rm -rf 절대로 안돼! 디렉토리 한번 더 봐!"),
            (#"rm\s+-rf?\s+~\S*"#,                "🛑 홈 디렉토리 통째로? 진짜?"),
            (#"git\s+push\s+(-f|--force)"#,       "🛑 force push 직전이야. 팀에 공유했어?"),
            (#"git\s+reset\s+--hard\s+(HEAD|origin)"#, "⚠️ hard reset이야. 작업 잃을 수 있어!"),
            (#"DROP\s+(TABLE|DATABASE|SCHEMA)"#,  "🛑 DROP 쿼리야! 환경 다시 봐!"),
            (#"TRUNCATE\s+TABLE"#,                "⚠️ TRUNCATE야. 백업 있어?"),
            (#":\(\)\s*\{\s*:\s*\|\s*:"#,         "🛑 fork bomb 패턴! 치지 마!"),
            (#"chmod\s+-R\s+777"#,                "⚠️ 777 재귀? 보안 사고 직전이야"),
            (#"sudo\s+rm\s+-rf"#,                 "🛑🛑 sudo rm -rf!! 정신 차려!"),
            (#"dd\s+if=.*\s+of=/dev/[sh]d"#,      "🛑 디스크 직접 덮어쓰기야! 멈춰!"),
            (#"mkfs\."#,                          "🛑 파일시스템 포맷 명령이야"),
            (#"curl[^|]+\|\s*(bash|sh)\b"#,       "⚠️ curl | bash 패턴. 그 스크립트 믿을 수 있어?"),
        ]
        return raw.compactMap { pat, msg in
            guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { return nil }
            return (re, msg)
        }
    }

    static func scan(_ text: String) -> Danger? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for (re, msg) in rules {
            if let match = re.firstMatch(in: text, options: [], range: range),
               let r = Range(match.range, in: text) {
                return Danger(pattern: String(text[r]), warning: msg)
            }
        }
        return nil
    }
}
