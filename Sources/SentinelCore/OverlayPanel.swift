import AppKit
import Lottie
import Foundation

/// Module-level helper exposing SentinelCore's resource bundle.
/// Public so tests (SPM SentinelTests, XCTest) can locate bundled lottie assets.
public let sentinelCoreResourceBundle: Bundle = {
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
        case .celebrating:    return "dancing"
        case .nagging:        return "nodding_sighingly"
        case .alarmed:        return "frightening"
        case .sleeping:       return "note_taking"  // TEMP until sleep lottie ships
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

        // Butler character — Lottie animation, fixed frame, no extra motion.
        lottieView.frame = NSRect(x: size.width - 96, y: 16, width: 80, height: 80)
        lottieView.contentMode = .scaleAspectFit
        lottieView.loopMode = .loop
        lottieView.wantsLayer = true
        root.addSubview(lottieView)

        // Speech bubble (always visible — no fade)
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
    }

    public func show() {
        panel.orderFrontRegardless()
    }

    /// Update bubble text + butler emotion. Lottie animation drives all motion;
    /// no fade, no auto-hide. autoHide param kept for API compat but ignored.
    public func speak(_ text: String, emotion: Emotion, autoHide: TimeInterval = 8.0) {
        applyLottie(named: emotion.lottieName)
        bubbleLabel.stringValue = text
        bubbleContainer.layer?.backgroundColor = emotion.bubbleColor.cgColor
        lottieView.setAccessibilityLabel("Sentinel butler — \(emotion.rawValue)")
    }

    // MARK: - Lottie loading

    private static var resourceBundle: Bundle { sentinelCoreResourceBundle }

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
