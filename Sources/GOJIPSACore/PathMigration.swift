import Foundation

/// Migrates the legacy `~/.sentinel/` config directory (used by Sentinel for cmux v1.x)
/// to the new `~/.gojipsa/` location used by 꼬집사 (GOJIPSA) v2.0.0+.
///
/// Behavior:
/// - Idempotent: safe to call on every launch.
/// - Only acts when `~/.sentinel` exists AND `~/.gojipsa` does NOT yet exist.
/// - Copies `api-key.txt` and `cmux-password.txt`, preserving 0600 perms.
/// - Never overwrites existing files in `~/.gojipsa` — user's current config wins.
/// - Always enforces 0700 on the config directory (even if it already existed
///   with looser perms) so the migrated secrets aren't readable by other users.
/// - Failures are logged to stderr with generic messages (no path/filename) so
///   the migration can be diagnosed without leaking which secret files exist.
public enum PathMigration {
    /// Public well-known config directory for the running app.
    public static let configDirName = ".gojipsa"
    public static let legacyConfigDirName = ".sentinel"

    public static func configDirURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(configDirName, isDirectory: true)
    }

    public static func legacyConfigDirURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(legacyConfigDirName, isDirectory: true)
    }

    /// Run once at app start. No-op when nothing to migrate.
    @discardableResult
    public static func migrateLegacyIfNeeded() -> Bool {
        let fm = FileManager.default
        let newDir = configDirURL()
        let oldDir = legacyConfigDirURL()

        // Nothing to migrate — legacy dir doesn't exist
        guard fm.fileExists(atPath: oldDir.path) else { return false }

        // Ensure new dir exists with safe perms (0700 — owner only).
        // Always enforce — even if the dir pre-existed it may have loose perms
        // from an earlier shell command (e.g. `mkdir ~/.gojipsa` without umask).
        if !fm.fileExists(atPath: newDir.path) {
            do {
                try fm.createDirectory(
                    at: newDir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: NSNumber(value: 0o700)]
                )
            } catch {
                FileHandle.standardError.write(Data(
                    "⚠️  Config migration: failed to create config directory\n".utf8
                ))
                return false
            }
        }
        // Tighten perms even if the dir existed before — defense-in-depth.
        try? fm.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: newDir.path
        )

        // Copy known config files (best-effort, never overwrite).
        // The list is hardcoded — never accept user-supplied names — so this can
        // only ever touch the two well-known secret files we own.
        let knownFiles = ["api-key.txt", "cmux-password.txt"]
        var migratedAny = false
        for name in knownFiles {
            let src = oldDir.appendingPathComponent(name)
            let dst = newDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            guard !fm.fileExists(atPath: dst.path) else {
                // User already populated the new location — leave it alone
                continue
            }
            do {
                try fm.copyItem(at: src, to: dst)
                // Preserve 0600 (owner read/write only) regardless of source perms
                try fm.setAttributes(
                    [.posixPermissions: NSNumber(value: 0o600)],
                    ofItemAtPath: dst.path
                )
                migratedAny = true
            } catch {
                FileHandle.standardError.write(Data(
                    "⚠️  Config migration: failed to migrate one config entry\n".utf8
                ))
            }
        }

        if migratedAny {
            FileHandle.standardError.write(Data(
                "✓ Config migration: legacy configuration imported\n".utf8
            ))
        }

        return migratedAny
    }
}
