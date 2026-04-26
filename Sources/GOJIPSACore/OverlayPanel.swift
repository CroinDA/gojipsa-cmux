import AppKit
import Lottie
import Foundation

/// Module-level helper exposing GOJIPSACore's resource bundle.
/// Public so tests (SPM GOJIPSATests, XCTest) can locate bundled lottie assets.
public let gojipsaCoreResourceBundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle.main
    #endif
}()

public enum Emotion: String, Sendable {
    case idle = "🙂"
    case talking = "😄"
    case alarmed = "😱"
    case sleeping = "😴"
    case celebrating = "🥳"
    case nagging = "😤"

    public static func fromName(_ name: String) -> Emotion? {
        switch name.lowercased() {
        case "idle": return .idle
        case "talking": return .talking
        case "alarmed": return .alarmed
        case "sleeping": return .sleeping
        case "celebrating": return .celebrating
        case "nagging": return .nagging
        default: return nil
        }
    }

    /// Filename (without .lottie extension) of the matching dotLottie animation.
    /// Every emotion is guaranteed to map to a real lottie file.
    public var lottieName: String {
        switch self {
        case .idle:           return "note_taking"
        case .talking:        return "Checking"
        case .celebrating:    return "happy"
        case .nagging:        return "nagging"
        case .alarmed:        return "frightening"
        case .sleeping:       return "sleepy"
        }
    }

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

/// Minimalist overlay — Lottie character + speech bubble.
/// Zero added animations: Lottie's own animation IS the motion. No fade-in,
/// no auto-hide bubble, no bob, no NSAnimationContext.
@MainActor
public final class OverlayPanel {
    private let panel: NSPanel
    private let lottieView = LottieAnimationView()
    private let bubbleLabel = NSTextField(wrappingLabelWithString: "")
    private let bubbleContainer = NSView()
    private var currentLottieName: String?

    // Layout constants — tuned so long messages stay fully visible.
    private static let panelWidth: CGFloat = 360
    private static let bubbleMaxHeight: CGFloat = 320
    private static let bubbleMinHeight: CGFloat = 60
    private static let bubbleHorizontalPadding: CGFloat = 14
    private static let bubbleVerticalPadding: CGFloat = 10
    private static let characterHeight: CGFloat = 80
    private static let panelMargin: CGFloat = 8
    private static let bubbleCharGap: CGFloat = 16

    public init() {
        // Initial size — actual height grows dynamically to fit message text.
        let initialHeight = OverlayPanel.characterHeight
            + OverlayPanel.bubbleMinHeight
            + OverlayPanel.bubbleCharGap
            + (OverlayPanel.panelMargin * 2)
        let size = NSSize(width: OverlayPanel.panelWidth, height: initialHeight)
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

        // Butler character — Lottie animation, fixed frame at bottom-right.
        lottieView.frame = NSRect(x: size.width - 96, y: OverlayPanel.panelMargin,
                                  width: 80, height: OverlayPanel.characterHeight)
        lottieView.contentMode = .scaleAspectFit
        lottieView.loopMode = .loop
        lottieView.wantsLayer = true
        root.addSubview(lottieView)

        // Speech bubble — height resized dynamically in speak() based on text.
        let bubbleY = lottieView.frame.maxY + OverlayPanel.bubbleCharGap
        bubbleContainer.frame = NSRect(x: OverlayPanel.panelMargin, y: bubbleY,
                                       width: size.width - OverlayPanel.panelMargin * 2,
                                       height: OverlayPanel.bubbleMinHeight)
        bubbleContainer.wantsLayer = true
        bubbleContainer.layer?.cornerRadius = 14
        bubbleContainer.layer?.backgroundColor = Emotion.idle.bubbleColor.cgColor
        bubbleContainer.layer?.shadowOpacity = 0.18
        bubbleContainer.layer?.shadowRadius = 6
        bubbleContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
        root.addSubview(bubbleContainer)

        bubbleLabel.frame = bubbleContainer.bounds.insetBy(
            dx: OverlayPanel.bubbleHorizontalPadding,
            dy: OverlayPanel.bubbleVerticalPadding
        )
        bubbleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        bubbleLabel.textColor = .labelColor
        bubbleLabel.maximumNumberOfLines = 0           // no truncation
        bubbleLabel.lineBreakMode = .byWordWrapping    // wrap to next line
        bubbleLabel.autoresizingMask = [.width, .height]
        bubbleContainer.addSubview(bubbleLabel)

        panel.contentView = root
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    /// Update bubble text + butler emotion. Bubble + panel grow tall enough to
    /// show the full message (no "..." truncation). Lottie drives all motion.
    public func speak(_ text: String, emotion: Emotion, autoHide: TimeInterval = 8.0) {
        applyLottie(named: emotion.lottieName)
        bubbleLabel.stringValue = text
        bubbleContainer.layer?.backgroundColor = emotion.bubbleColor.cgColor
        lottieView.setAccessibilityLabel("GOJIPSA butler — \(emotion.rawValue)")
        resizeBubbleToFit(text: text)
    }

    /// Speak with an explicit lottie override — Gemini-chosen animation takes priority.
    public func speak(_ comment: Comment) {
        let lottieName = comment.lottie ?? comment.emotion.lottieName
        applyLottie(named: lottieName)
        bubbleLabel.stringValue = comment.text
        bubbleContainer.layer?.backgroundColor = comment.emotion.bubbleColor.cgColor
        lottieView.setAccessibilityLabel("GOJIPSA butler — \(comment.emotion.rawValue)")
        resizeBubbleToFit(text: comment.text)
    }

    /// Compute the bubble height needed to show `text` in full, then resize
    /// bubbleContainer + the panel + repositions the lottie view accordingly.
    private func resizeBubbleToFit(text: String) {
        let labelWidth = OverlayPanel.panelWidth
            - OverlayPanel.panelMargin * 2
            - OverlayPanel.bubbleHorizontalPadding * 2
        let attrs: [NSAttributedString.Key: Any] = [.font: bubbleLabel.font ?? NSFont.systemFont(ofSize: 14)]
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: labelWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let textH = ceil(bounds.height)
        let bubbleH = max(OverlayPanel.bubbleMinHeight,
                          min(OverlayPanel.bubbleMaxHeight,
                              textH + OverlayPanel.bubbleVerticalPadding * 2))

        let panelH = OverlayPanel.characterHeight
            + OverlayPanel.bubbleCharGap
            + bubbleH
            + OverlayPanel.panelMargin * 2

        // Reposition panel — keep bottom-right anchored as content grows upward.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let newOrigin = NSPoint(x: screen.maxX - OverlayPanel.panelWidth - 32,
                                y: screen.minY + 32)
        let newFrame = NSRect(origin: newOrigin,
                              size: NSSize(width: OverlayPanel.panelWidth, height: panelH))
        panel.setFrame(newFrame, display: true, animate: false)

        // Re-layout subviews inside the new panel content size.
        let newBubbleY = OverlayPanel.panelMargin + OverlayPanel.characterHeight + OverlayPanel.bubbleCharGap
        bubbleContainer.frame = NSRect(
            x: OverlayPanel.panelMargin,
            y: newBubbleY,
            width: OverlayPanel.panelWidth - OverlayPanel.panelMargin * 2,
            height: bubbleH
        )
        bubbleLabel.frame = bubbleContainer.bounds.insetBy(
            dx: OverlayPanel.bubbleHorizontalPadding,
            dy: OverlayPanel.bubbleVerticalPadding
        )
        // Lottie position fixed at the bottom of the panel.
        lottieView.frame = NSRect(
            x: OverlayPanel.panelWidth - 96,
            y: OverlayPanel.panelMargin,
            width: 80,
            height: OverlayPanel.characterHeight
        )
    }

    // MARK: - Lottie loading

    private static var resourceBundle: Bundle { gojipsaCoreResourceBundle }

    private func resolveLottieURL(name: String) -> URL? {
        let bundle = OverlayPanel.resourceBundle
        if let url = bundle.url(forResource: name, withExtension: "lottie", subdirectory: "lottie") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: "lottie") {
            return url
        }
        if let bundleURL = bundle.resourceURL?.appendingPathComponent("lottie/\(name).lottie"),
           FileManager.default.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
        return nil
    }

    private func applyLottie(named name: String) {
        if currentLottieName == name && lottieView.isAnimationPlaying {
            return
        }
        guard let url = resolveLottieURL(name: name) else { return }
        DotLottieFile.loadedFrom(url: url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case .success(let file) = result {
                    self.lottieView.loadAnimation(from: file)
                    self.lottieView.loopMode = .loop
                    self.lottieView.play()
                    self.currentLottieName = name
                }
            }
        }
    }
}
