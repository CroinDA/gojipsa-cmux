import Foundation

public enum SecretRedactor {
    private static let rules: [(NSRegularExpression, String)] = build()

    private static func build() -> [(NSRegularExpression, String)] {
        let raw: [(String, String)] = [
            // OpenAI / Anthropic style API keys
            (#"sk-[A-Za-z0-9_-]{20,}"#,                       "sk-***REDACTED***"),
            // Google API keys (start with AIza)
            (#"AIza[0-9A-Za-z_-]{30,}"#,                      "AIza***REDACTED***"),
            // GitHub tokens
            (#"gh[opsu]_[A-Za-z0-9]{30,}"#,                   "gh*_***REDACTED***"),
            // AWS access keys
            (#"AKIA[0-9A-Z]{16}"#,                            "AKIA***REDACTED***"),
            // Bearer tokens
            (#"Bearer\s+[A-Za-z0-9._\-]{20,}"#,               "Bearer ***REDACTED***"),
            // JWT-ish (3 base64 segments)
            (#"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, "***JWT-REDACTED***"),
            // PEM private keys
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]+?-----END [A-Z ]*PRIVATE KEY-----"#, "***PRIVATE-KEY-REDACTED***"),
            // Generic password=, secret=, token= assignments
            (#"(?i)(password|passwd|secret|token|api[_-]?key)\s*[:=]\s*['"]?[A-Za-z0-9._\-+/]{8,}['"]?"#, "$1=***REDACTED***"),
        ]
        return raw.compactMap { pat, repl in
            guard let re = try? NSRegularExpression(pattern: pat, options: []) else { return nil }
            return (re, repl)
        }
    }

    public static func redact(_ text: String) -> String {
        var result = text
        for (re, replacement) in rules {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = re.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
        }
        return result
    }
}
