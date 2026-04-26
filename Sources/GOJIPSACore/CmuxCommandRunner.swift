import Foundation

/// cmux CLI 호출 결과입니다.
///
/// 호출 성공 여부, 표준 출력, 표준 에러, timeout 여부를 보존해 상위 계층이
/// "소켓 연결됨"과 "터미널 내용 읽기 실패"를 구분할 수 있게 합니다.
public struct CmuxCommandResult: Sendable, Equatable {
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32?, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// cmux 명령 실행을 추상화한 포트입니다.
///
/// 테스트나 다른 실행 환경에서는 이 프로토콜을 구현한 runner를 주입할 수 있고,
/// 앱 런타임에서는 `CmuxProcessRunner`가 실제 `Process`를 실행합니다.
public protocol CmuxCommandRunning: Sendable {
    func run(args: [String], timeout: TimeInterval) async -> CmuxCommandResult
}

/// `Process`를 통해 cmux CLI를 실행하는 기본 어댑터입니다.
public struct CmuxProcessRunner: CmuxCommandRunning {
    private let configuration: CmuxConfiguration

    public init(configuration: CmuxConfiguration) {
        self.configuration = configuration
    }

    /// 지정한 인자로 cmux CLI를 실행합니다.
    ///
    /// 비밀번호가 설정되어 있으면 `CMUX_SOCKET_PASSWORD` 환경 변수로만 전달해
    /// 프로세스 목록이나 로그에 비밀번호가 인자로 노출되지 않게 합니다.
    public func run(args: [String], timeout: TimeInterval = 5.0) async -> CmuxCommandResult {
        guard !configuration.executablePath.isEmpty else {
            return CmuxCommandResult(
                exitCode: nil,
                stdout: "",
                stderr: "cmux executable not found",
                timedOut: false
            )
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<CmuxCommandResult, Never>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: configuration.executablePath)
            proc.arguments = args

            if !configuration.password.isEmpty {
                var env = ProcessInfo.processInfo.environment
                env["CMUX_SOCKET_PASSWORD"] = configuration.password
                proc.environment = env
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            do {
                try proc.run()
            } catch {
                cont.resume(returning: CmuxCommandResult(
                    exitCode: nil,
                    stdout: "",
                    stderr: "Process.run failed: \(error.localizedDescription)",
                    timedOut: false
                ))
                return
            }

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
                cont.resume(returning: CmuxCommandResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? "",
                    timedOut: timedOut.isSet
                ))
            }
        }
    }
}

/// timeout watchdog가 `Process` 종료 스레드와 공유하는 작은 thread-safe flag입니다.
private final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
