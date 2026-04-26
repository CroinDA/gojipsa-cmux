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

    /// Resolve a state name (e.g. "talking", "alarmed") to an Emotion.
    /// Returns nil for unknown names.
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

    /// Filename (without .lottie extension) of the matching dotLottie animation
    /// in SentinelCore's bundle. Returns nil if no animation has been mapped yet
    /// — caller falls back to the emoji rawValue.
    public var lottieName: String? {
        switch self {
        case .idle:           return "note_taking"      // butler at desk
        case .talking:        return "Checking"         // actively inspecting
        case .celebrating:    return "dancing"
        case .nagging:        return "nodding_sighingly"
        case .alarmed:        return "frightening"
        case .sleeping:       return nil                // emoji 😴 fallback (until file added)
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

@MainActor
public final class OverlayPanel {
    private let panel: NSPanel
    private let characterLabel = NSTextField(labelWithString: Emotion.idle.rawValue)
    private let lottieView = LottieAnimationView()
    private let bubbleLabel = NSTextField(wrappingLabelWithString: "")
    private let bubbleContainer = NSView()
    private var hideTask: Task<Void, Never>?
    private var bobAnimation: Timer?
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

        let charFrame = NSRect(x: size.width - 96, y: 16, width: 80, height: 80)
        characterLabel.font = NSFont.systemFont(ofSize: 64)
        characterLabel.alignment = .center
        characterLabel.frame = charFrame
        characterLabel.isBordered = false
        characterLabel.drawsBackground = false
        characterLabel.wantsLayer = true
        root.addSubview(characterLabel)

        // Lottie animation view — overlays the emoji label and is shown when
        // a lottie file is mapped for the current emotion. Falls back to the
        // emoji label otherwise.
        lottieView.frame = charFrame
        lottieView.contentMode = .scaleAspectFit
        lottieView.loopMode = .loop
        lottieView.backgroundBehavior = .pauseAndRestore
        lottieView.isHidden = true
        lottieView.wantsLayer = true
        root.addSubview(lottieView)

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
        // Try to play a lottie animation if mapped; otherwise show the emoji label.
        if let lottie = emotion.lottieName {
            applyLottie(named: lottie, fallbackEmoji: emotion.rawValue)
        } else {
            characterLabel.stringValue = emotion.rawValue
            characterLabel.isHidden = false
            lottieView.isHidden = true
            lottieView.stop()
            currentLottieName = nil
        }
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

    /// Resource bundle for .lottie files — uses the free helper so non-MainActor
    /// callers (e.g., SPM tests) can reach the same bundle.
    private static var resourceBundle: Bundle { sentinelCoreResourceBundle }

    /// Resolve a .lottie file URL across both bundle layouts.
    /// SPM puts assets in a subdirectory (Resources/lottie/), Xcode at root.
    private func resolveLottieURL(name: String) -> URL? {
        let bundle = OverlayPanel.resourceBundle
        if let url = bundle.url(forResource: name, withExtension: "lottie", subdirectory: "lottie") {
            return url
        }
        if let url = bundle.url(forResource: name, withExtension: "lottie") {
            return url
        }
        // Last resort: walk Resources/lottie subdir explicitly
        if let bundleURL = bundle.resourceURL?.appendingPathComponent("lottie/\(name).lottie"),
           FileManager.default.fileExists(atPath: bundleURL.path) {
            return bundleURL
        }
        return nil
    }

    /// Loads the dotLottie file and starts playback. Hides the emoji label on
    /// success; on failure (file missing, parse error) reverts to emoji.
    private func applyLottie(named name: String, fallbackEmoji: String) {
        if currentLottieName == name && !lottieView.isHidden {
            return  // already playing
        }
        guard let url = resolveLottieURL(name: name) else {
            characterLabel.stringValue = fallbackEmoji
            characterLabel.isHidden = false
            lottieView.isHidden = true
            currentLottieName = nil
            return
        }
        DotLottieFile.loadedFrom(url: url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let file):
                    self.lottieView.loadAnimation(from: file)
                    self.lottieView.loopMode = .loop
                    self.lottieView.play()
                    self.lottieView.isHidden = false
                    self.characterLabel.isHidden = true
                    self.currentLottieName = name
                case .failure:
                    self.characterLabel.stringValue = fallbackEmoji
                    self.characterLabel.isHidden = false
                    self.lottieView.isHidden = true
                    self.currentLottieName = nil
                }
            }
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
