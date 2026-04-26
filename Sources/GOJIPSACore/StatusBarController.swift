import AppKit

/// Menu-bar status item with quit option.
/// Periodically refreshes its icon based on cmux connection state.
@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "🟡 Checking...", action: nil, keyEquivalent: "")
    private var refreshTimer: Timer?
    private var lastActivityAt: Date = Date.distantPast

    public override init() {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // Default icon — will be replaced on first status refresh
        if let button = item.button {
            button.title = "🤏"
            button.toolTip = "꼬집사 (GOJIPSA) for cmux"
        }

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show status (--status)",
                                action: #selector(showStatus),
                                keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit 꼬집사",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        for case let m? in menu.items.map({ $0.action != nil ? $0 : nil }) where m.target == nil {
            m.target = self
        }

        item.menu = menu
        menu.delegate = self

        // Refresh status every 5s
        startRefreshTimer()
        Task { await refreshNow() }
    }

    // MARK: - Refresh

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshNow() }
        }
    }

    private func refreshNow() async {
        let report = await ScreenWatcher.quickStatus()
        let (icon, label): (String, String) = {
            switch report.status {
            case .connected:        return ("🟢🤏", "꼬집사 — cmux connected")
            case .accessDenied,
                 .passwordRejected: return ("🔒🤏", "꼬집사 — cmux access denied")
            case .serverNotRunning,
                 .binaryNotFound:   return ("🔴🤏", "꼬집사 — cmux not running")
            case .timeout:          return ("⏱🤏", "꼬집사 — cmux timeout")
            case .unknown:          return ("⚠️🤏", "꼬집사 — cmux unknown")
            }
        }()
        item.button?.title = icon
        let activitySuffix: String = {
            guard lastActivityAt != Date.distantPast else { return "" }
            let sec = Int(Date().timeIntervalSince(lastActivityAt))
            if sec < 5 { return " · 방금 반응" }
            if sec < 60 { return " · \(sec)초 전 반응" }
            return " · \(sec / 60)분 전 반응"
        }()
        item.button?.toolTip = label + activitySuffix
        statusMenuItem.title = "\(icon) \(report.status.summary)\(activitySuffix)"
    }

    // MARK: - Menu actions

    @objc private func showStatus() {
        Task { @MainActor in
            await refreshNow()
            // Open menu programmatically so user sees the latest line
            item.button?.performClick(nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Call this whenever a comment is generated — updates the "last active" tooltip.
    public func noteActivity() {
        lastActivityAt = Date()
    }

    // MARK: - NSMenuDelegate

    public func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in await refreshNow() }
    }
}
