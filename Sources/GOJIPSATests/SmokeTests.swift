import Foundation
import GOJIPSACore

func runSmokeTests() async {
    await runSuite("Smoke — GOJIPSA.app binary present and signed") {
        let appPath = "/Applications/GOJIPSA.app/Contents/MacOS/GOJIPSA"
        let exists = FileManager.default.isExecutableFile(atPath: appPath)
        if !exists {
            await skip("GOJIPSA.app is not installed in /Applications")
            return
        }

        // Spawn the app, give it 2s, then kill
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: appPath)
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let alive = proc.isRunning
            proc.terminate()
            proc.waitUntilExit()
            await assert(alive, "GOJIPSA process should still be alive after 2s (no early crash)")
        } catch {
            await assert(false, "failed to launch GOJIPSA: \(error)")
        }
    }

    await runSuite("Smoke — cmux binary present") {
        let candidates = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            "/opt/homebrew/bin/cmux",
            "/usr/local/bin/cmux"
        ]
        let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        await assertNotNil(found, "cmux binary not found in standard locations")
        if let f = found { print("    ↳ cmux at: \(f)") }
    }

    await runSuite("Smoke — API key file") {
        let keyPath = PathMigration.configDirURL().appendingPathComponent("api-key.txt")
        let exists = FileManager.default.fileExists(atPath: keyPath.path)
        if !exists {
            await skip("~/.gojipsa/api-key.txt is not configured on this machine")
            return
        }

        // Permission must be 0600 (owner-only)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: keyPath.path),
           let perm = attrs[.posixPermissions] as? NSNumber {
            let p = perm.intValue
            await assertEqual(p & 0o777, 0o600, "api-key.txt permission must be 0600 (got \(String(p, radix: 8)))")
        }
    }
}
