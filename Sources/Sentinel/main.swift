import AppKit
import Foundation
import SentinelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: OverlayPanel!
    var watcher: ScreenWatcher!
    var watchTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ note: Notification) {
        let apiKey = loadApiKey()
        if apiKey.isEmpty {
            FileHandle.standardError.write(Data("⚠️  GEMINI_API_KEY missing. Set env var or write to ~/.sentinel/api-key.txt\n".utf8))
        }

        panel = OverlayPanel()
        panel.show()
        panel.speak("👀 Sentinel awake. Watching your shell...", emotion: .idle)

        watcher = ScreenWatcher(apiKey: apiKey, onComment: { [weak self] comment in
            Task { @MainActor in
                self?.panel.speak(comment.text, emotion: comment.emotion)
            }
        })
        let w = watcher!
        watchTask = Task.detached { await w.run() }
    }

    func applicationWillTerminate(_ note: Notification) {
        watchTask?.cancel()
    }

    private func loadApiKey() -> String {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keyPath = home.appendingPathComponent(".sentinel/api-key.txt")
        if let data = try? Data(contentsOf: keyPath),
           let str = String(data: data, encoding: .utf8) {
            return str.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    // Strong-retain delegate beyond scope
    objc_setAssociatedObject(app, "sentinelDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    app.run()
}
