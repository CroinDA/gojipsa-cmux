import AppKit

public enum Emotion: String, Sendable {
    case idle = "🙂"
    case talking = "😄"
    case alarmed = "😱"
    case sleeping = "😴"
    case celebrating = "🥳"
    case nagging = "😤"

    public var bubbleColor: NSColor {
        switch self {
        case .alarmed: return NSColor.systemRed.withAlphaComponent(0.92)
        case .celebrating: return NSColor.systemOrange.withAlphaComponent(0.92)
        case .nagging: return NSColor.systemYellow.withAlphaComponent(0.92)
        case .sleeping: return NSColor.systemGray.withAlphaComponent(0.85)
        default: return NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        }
    }
}

@MainActor
public final class OverlayPanel {
    private let panel: NSPanel
    private let characterLabel = NSTextField(labelWithString: Emotion.idle.rawValue)
    private let bubbleLabel = NSTextField(wrappingLabelWithString: "")
    private let bubbleContainer = NSView()
    private var hideTask: Task<Void, Never>?
    private var bobAnimation: Timer?

    public init() {
        let size = NSSize(width: 320, height: 180)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screen.maxX - size.width - 32, y: screen.minY + 32)

        panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true

        characterLabel.font = NSFont.systemFont(ofSize: 64)
        characterLabel.alignment = .center
        characterLabel.frame = NSRect(x: size.width - 96, y: 16, width: 80, height: 80)
        characterLabel.isBordered = false
        characterLabel.drawsBackground = false
        characterLabel.wantsLayer = true
        root.addSubview(characterLabel)

        bubbleContainer.frame = NSRect(x: 8, y: 96, width: size.width - 16, height: 76)
        bubbleContainer.wantsLayer = true
        bubbleContainer.layer?.cornerRadius = 14
        bubbleContainer.layer?.backgroundColor = Emotion.idle.bubbleColor.cgColor
        bubbleContainer.layer?.shadowOpacity = 0.18
        bubbleContainer.layer?.shadowRadius = 6
        bubbleContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
        root.addSubview(bubbleContainer)

        bubbleLabel.frame = bubbleContainer.bounds.insetBy(dx: 14, dy: 10)
        bubbleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        bubbleLabel.textColor = .labelColor
        bubbleLabel.maximumNumberOfLines = 4
        bubbleLabel.lineBreakMode = .byTruncatingTail
        bubbleLabel.autoresizingMask = [.width, .height]
        bubbleContainer.addSubview(bubbleLabel)

        panel.contentView = root
        startBobAnimation()
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    public func speak(_ text: String, emotion: Emotion, autoHide: TimeInterval = 8.0) {
        characterLabel.stringValue = emotion.rawValue
        bubbleLabel.stringValue = text

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            bubbleContainer.animator().alphaValue = 1.0
            bubbleContainer.layer?.backgroundColor = emotion.bubbleColor.cgColor
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(autoHide * 1_000_000_000))
            self?.fadeBubble()
        }
    }

    private func fadeBubble() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            bubbleContainer.animator().alphaValue = 0.0
        }
    }

    private func startBobAnimation() {
        var phase: CGFloat = 0
        bobAnimation = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            phase += 0.18
            let dy = sin(phase) * 4
            Task { @MainActor in
                self.characterLabel.frame.origin.y = 16 + dy
            }
        }
    }
}
