import AppKit

/// Full-screen red translucent alarm panel for dangerous command warnings.
/// Distinct from the small OverlayPanel (which is for ambient comments).
///
/// Behavior:
/// - Covers the entire main screen with a translucent red wash (no focus steal).
/// - Big bold title + matched pattern + warning + Gemini explanation.
/// - Auto-dismisses after `dismissAfter` seconds.
/// - Mouse events pass through (does NOT block other apps).
@MainActor
public final class AlarmPanel {
    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let patternLabel = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private let explanationLabel = NSTextField(wrappingLabelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private var dismissTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    public init() {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        panel = NSPanel(
            contentRect: screen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver  // above floating, below absolute system overlays
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true

        let root = NSView(frame: NSRect(origin: .zero, size: screen.size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor

        // Center card
        let cardW: CGFloat = 720, cardH: CGFloat = 320
        let card = NSView(frame: NSRect(
            x: (screen.width - cardW) / 2,
            y: (screen.height - cardH) / 2,
            width: cardW, height: cardH
        ))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.95).cgColor
        card.layer?.cornerRadius = 24
        card.layer?.borderWidth = 3
        card.layer?.borderColor = NSColor.systemRed.cgColor
        card.layer?.shadowColor = NSColor.systemRed.cgColor
        card.layer?.shadowOpacity = 0.5
        card.layer?.shadowRadius = 24

        // Title (🛑 icon + headline)
        titleLabel.frame = NSRect(x: 28, y: cardH - 80, width: cardW - 56, height: 48)
        titleLabel.font = NSFont.systemFont(ofSize: 36, weight: .bold)
        titleLabel.textColor = NSColor.systemRed
        titleLabel.alignment = .left
        titleLabel.stringValue = "🛑 위험 명령 감지"
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        card.addSubview(titleLabel)

        // Pattern (the matched dangerous string)
        patternLabel.frame = NSRect(x: 28, y: cardH - 130, width: cardW - 56, height: 36)
        patternLabel.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold)
        patternLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
        patternLabel.alignment = .left
        patternLabel.maximumNumberOfLines = 1
        patternLabel.lineBreakMode = .byTruncatingMiddle
        patternLabel.isBordered = false
        patternLabel.drawsBackground = false
        card.addSubview(patternLabel)

        // Warning (canned message from DangerDetector)
        warningLabel.frame = NSRect(x: 28, y: cardH - 180, width: cardW - 56, height: 40)
        warningLabel.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        warningLabel.textColor = NSColor.systemYellow
        warningLabel.maximumNumberOfLines = 2
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.isBordered = false
        warningLabel.drawsBackground = false
        card.addSubview(warningLabel)

        // Explanation (Gemini natural-language detail)
        explanationLabel.frame = NSRect(x: 28, y: 60, width: cardW - 56, height: 110)
        explanationLabel.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        explanationLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        explanationLabel.maximumNumberOfLines = 5
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isBordered = false
        explanationLabel.drawsBackground = false
        card.addSubview(explanationLabel)

        // Countdown bar at the bottom
        countdownLabel.frame = NSRect(x: 28, y: 18, width: cardW - 56, height: 28)
        countdownLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        countdownLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
        countdownLabel.alignment = .right
        countdownLabel.isBordered = false
        countdownLabel.drawsBackground = false
        card.addSubview(countdownLabel)

        root.addSubview(card)
        panel.contentView = root
    }

    public func showAlarm(pattern: String, warning: String, explanation: String?, dismissAfter: TimeInterval = 5.0) {
        patternLabel.stringValue = pattern
        warningLabel.stringValue = warning
        explanationLabel.stringValue = explanation ?? "5초만 멈추고 한번 더 생각해봐. 정말 실행할 거야?"

        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1.0
        }

        dismissTask?.cancel()
        countdownTask?.cancel()
        let totalSeconds = Int(dismissAfter)
        countdownTask = Task { @MainActor [weak self] in
            for remaining in stride(from: totalSeconds, through: 1, by: -1) {
                self?.countdownLabel.stringValue = "\(remaining)초 후 자동 닫힘"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
        }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(dismissAfter * 1_000_000_000))
            self?.dismiss()
        }
    }

    public func updateExplanation(_ explanation: String) {
        explanationLabel.stringValue = explanation
    }

    public func dismiss() {
        countdownTask?.cancel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }
}
