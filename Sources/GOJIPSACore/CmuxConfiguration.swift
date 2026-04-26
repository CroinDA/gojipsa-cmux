import Foundation

/// cmux CLI를 호출하는 데 필요한 실행 환경입니다.
///
/// 이 타입은 실행 파일 탐색, 비밀번호 로딩, 현재 cmux surface 식별자 확인만
/// 담당합니다. 실제 소켓 호출과 터미널 내용 선택은 각각 `CmuxProcessRunner`와
/// `CmuxTerminalContextProvider`가 맡습니다.
public struct CmuxConfiguration: Sendable, Equatable {
    /// 실행 가능한 cmux CLI 경로입니다. 찾지 못하면 빈 문자열입니다.
    public let executablePath: String

    /// cmux socket password입니다. PID-ancestry 인증을 쓰는 경우 빈 문자열일 수 있습니다.
    public let password: String

    /// GOJIPSA 자신이 cmux 안에서 실행될 때 주입되는 surface 식별자입니다.
    public let currentSurfaceID: String

    public init(executablePath: String, password: String, currentSurfaceID: String) {
        self.executablePath = executablePath
        self.password = password
        self.currentSurfaceID = currentSurfaceID
    }

    /// 현재 프로세스 환경을 기준으로 cmux 설정을 구성합니다.
    public static func current() -> CmuxConfiguration {
        CmuxConfiguration(
            executablePath: locateExecutable(),
            password: loadPassword(),
            currentSurfaceID: ProcessInfo.processInfo.environment["CMUX_SURFACE_ID"] ?? ""
        )
    }

    /// 앱 번들, Homebrew, PATH 순서로 cmux 실행 파일을 찾습니다.
    public static func locateExecutable() -> String {
        let candidates = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "/opt/homebrew/bin/cmux",
            "/usr/local/bin/cmux"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["cmux"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return FileManager.default.isExecutableFile(atPath: path) ? path : ""
        } catch {
            return ""
        }
    }

    /// cmux socket password를 로딩합니다.
    ///
    /// 우선순위는 `CMUX_SOCKET_PASSWORD` 환경 변수, `~/.gojipsa/cmux-password.txt`,
    /// 빈 문자열 순서입니다. 파일 권한이 느슨하면 stderr에 경고만 남기고 읽기는
    /// 계속합니다.
    public static func loadPassword() -> String {
        if let env = ProcessInfo.processInfo.environment["CMUX_SOCKET_PASSWORD"], !env.isEmpty {
            return env
        }

        let path = PathMigration.configDirURL().appendingPathComponent("cmux-password.txt")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let perm = attrs[.posixPermissions] as? NSNumber {
            let mode = perm.intValue & 0o777
            if mode & 0o077 != 0 {
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
}
