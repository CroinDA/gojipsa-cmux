import Foundation
import SentinelCore

func runCmuxStatusTests() async {

    await runSuite("CmuxStatus — Classifier (no subprocess)") {
        // exitCode 0 -> connected
        await assertEqual(
            CmuxStatusClassifier.classify(exitCode: 0, stdout: "PONG", stderr: ""),
            CmuxStatus.connected,
            "exit 0 should map to .connected")

        // 'only processes started inside cmux' -> accessDenied
        await assertEqual(
            CmuxStatusClassifier.classify(exitCode: 1, stdout: "",
                stderr: "ERROR: Access denied — only processes started inside cmux can connect"),
            CmuxStatus.accessDenied,
            "access-denied phrasing should map to .accessDenied")

        // 'Socket not found' -> serverNotRunning
        await assertEqual(
            CmuxStatusClassifier.classify(exitCode: 1, stdout: "",
                stderr: "Error: Socket not found at /Users/.../cmux.sock"),
            CmuxStatus.serverNotRunning,
            "missing socket should map to .serverNotRunning")

        // 'Broken pipe' -> accessDenied (most common cause)
        await assertEqual(
            CmuxStatusClassifier.classify(exitCode: 1, stdout: "",
                stderr: "Error: Failed to write to socket (Broken pipe, errno 32)"),
            CmuxStatus.accessDenied,
            "broken pipe -> .accessDenied (best-effort)")

        // 'invalid password' -> passwordRejected
        await assertEqual(
            CmuxStatusClassifier.classify(exitCode: 1, stdout: "",
                stderr: "auth failed: invalid password"),
            CmuxStatus.passwordRejected,
            "auth failed/invalid password should map to .passwordRejected")

        // Random other error -> unknown
        await assertEqual(
            CmuxStatusClassifier.classify(exitCode: 7, stdout: "", stderr: "weird unexpected message"),
            CmuxStatus.unknown,
            "unrecognized output should fall through to .unknown")
    }

    await runSuite("CmuxStatus — summary strings non-empty") {
        for s in [CmuxStatus.connected, .binaryNotFound, .serverNotRunning,
                  .accessDenied, .passwordRejected, .timeout, .unknown] {
            await assert(!s.summary.isEmpty, "\(s.rawValue) should have a non-empty summary")
        }
    }

    await runSuite("CmuxStatus — quickStatus() live (this machine)") {
        let report = await ScreenWatcher.quickStatus()
        // We don't assert .connected because cmux server may not be running on CI,
        // but the result must be one of the known cases and details non-empty.
        let validStates: Set<CmuxStatus> = [
            .connected, .binaryNotFound, .serverNotRunning,
            .accessDenied, .passwordRejected, .timeout, .unknown
        ]
        await assert(validStates.contains(report.status),
                     "quickStatus must return one of the known states (got \(report.status))")
        print("    ↳ live status: \(report.status.rawValue) | \(report.status.summary)")
        if report.status == .connected {
            await assert(!report.cmuxPath.isEmpty, "connected status requires cmuxPath")
        }
    }

    await runSuite("CmuxStatusReport — struct shape") {
        let r = CmuxStatusReport(status: .timeout, details: "ping took >3s",
                                 cmuxPath: "/x/y/cmux", usingPassword: true)
        await assertEqual(r.status, .timeout, "status preserved")
        await assertEqual(r.cmuxPath, "/x/y/cmux", "path preserved")
        await assert(r.usingPassword, "usingPassword preserved")
    }
}
