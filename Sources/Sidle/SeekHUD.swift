import AppKit

/// Small floating label shown while scrubbing the bottom edge.
final class SeekHUD {
    static let shared = SeekHUD()
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private let sublabel = NSTextField(labelWithString: "release to apply")

    private init() {}

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 76),
                            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        label.font = .monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.frame = NSRect(x: 0, y: 30, width: 220, height: 36)
        sublabel.font = .systemFont(ofSize: 11)
        sublabel.alignment = .center
        sublabel.textColor = .secondaryLabelColor
        sublabel.frame = NSRect(x: 0, y: 10, width: 220, height: 16)
        effect.addSubview(label)
        effect.addSubview(sublabel)
        return panel
    }

    func show(seconds: Int) {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        let sign = seconds >= 0 ? "+" : "−"
        label.stringValue = seconds == 0 ? "0 s" : "\(sign)\(abs(seconds)) s"
        sublabel.stringValue = seconds == 0 ? "slide to seek" : "release to apply"
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - 110, y: f.minY + 120))
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
