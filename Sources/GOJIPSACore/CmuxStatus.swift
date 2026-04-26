import Foundation

/// Discrete states of the cmux socket connection.
///
/// Used by `ScreenWatcher.checkStatus()` to give the user (and tests) clear,
/// actionable diagnostics instead of opaque "broken pipe" failures.
public enum CmuxStatus: String, Sendable, Equatable {
    /// cmux server reachable, password (if configured) accepted, screens readable.
    case connected

    /// cmux binary not found in any known path.
    case binaryNotFound

    /// cmux server isn't running (no socket file or server doesn't accept connection).
    case serverNotRunning

    /// Server reachable but rejected our connection — we're not a cmux child AND no
    /// valid password was provided. Fix: set `~/.gojipsa/cmux-password.txt` or run inside cmux.
    case accessDenied

    /// Password was provided but server rejected it.
    case passwordRejected

    /// Server didn't respond within the deadline.
    case timeout

    /// Socket/auth is healthy, but no terminal surface can be read.
    case contextUnavailable

    /// Some other error — message captured in `details`.
    case unknown

    /// Human-readable summary, suitable for the bubble or `--status` output.
    public var summary: String {
        switch self {
        case .connected:        return "✅ cmux 연결됨"
        case .binaryNotFound:   return "❌ cmux 바이너리를 찾을 수 없음"
        case .serverNotRunning: return "❌ cmux 서버가 실행 중이 아님"
        case .accessDenied:     return "🔒 cmux 접근 거부됨 (cmux 안에서 실행 또는 password 설정 필요)"
        case .passwordRejected: return "🔒 cmux password 거부됨 — cmux Settings의 비밀번호와 일치하는지 확인"
        case .timeout:          return "⏱  cmux 응답 지연 (5초 초과)"
        case .contextUnavailable:
            return "⚠️  cmux 연결됨, 하지만 읽을 터미널 surface를 찾지 못함"
        case .unknown:          return "⚠️  cmux 상태 불명"
        }
    }
}

/// Snapshot of a status check, including raw diagnostic output for debugging.
public struct CmuxStatusReport: Sendable, Equatable {
    public let status: CmuxStatus
    public let details: String
    public let cmuxPath: String
    public let usingPassword: Bool

    public init(status: CmuxStatus, details: String, cmuxPath: String, usingPassword: Bool) {
        self.status = status
        self.details = details
        self.cmuxPath = cmuxPath
        self.usingPassword = usingPassword
    }
}

/// Maps raw `cmux ping` output (stdout/stderr) to a CmuxStatus.
/// Pulled into a free function so SPM unit tests can exercise it without spawning a process.
public enum CmuxStatusClassifier {
    public static func classify(exitCode: Int32?, stdout: String, stderr: String) -> CmuxStatus {
        let combined = (stdout + "\n" + stderr).lowercased()

        if exitCode == 0 {
            // cmux ping returns 0 when reachable
            return .connected
        }

        if combined.contains("only processes started inside cmux") {
            return .accessDenied
        }
        if combined.contains("invalid password") || combined.contains("password rejected") ||
           combined.contains("auth failed") || combined.contains("unauthorized") {
            return .passwordRejected
        }
        if combined.contains("socket not found") || combined.contains("connection refused") ||
           combined.contains("no such file") {
            return .serverNotRunning
        }
        if combined.contains("broken pipe") {
            // Could be access-denied OR transient server issue — lean toward accessDenied
            // since that's the most common cause for our use case.
            return .accessDenied
        }
        if combined.contains("timed out") || combined.contains("timeout") {
            return .timeout
        }

        return .unknown
    }
}
