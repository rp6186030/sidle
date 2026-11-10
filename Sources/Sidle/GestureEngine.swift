import AppKit
import MTBridge

/// Turns raw trackpad frames plus the click event stream into edge gestures.
///
/// Rules (matching the behaviour we are reproducing):
/// - A gesture starts only when exactly one finger is resting inside an edge strip or
///   corner *and* the trackpad is physically clicked. Hovering does nothing.
/// - Leaving the strip cancels the gesture immediately.
/// - Multi-finger contacts, palms and ordinary scrolling are ignored.
/// - While sliding, the pointer is frozen and restored on release.
final class GestureEngine {
    static let shared = GestureEngine()

    enum Region: Equatable { case left, right, bottom, corner(Corner) }

    private struct ActiveSlide {
        var region: Region
        var function: EdgeFunction          // for left/right
        var device: MTDeviceRef
        var fingerID: Int32
        var startMM: CGPoint
        var lastStepMM: Double              // y (vertical edges) or x (bottom)
        var savedPointer: CGPoint
        var stripMM: Double
        var seekSteps: Int = 0
        var cancelled = false
    }

    private struct CornerClicks {
        var corner: Corner
        var count: Int
        var timer: Timer?
    }

    private let lock = NSLock()
    private var latest: [UnsafeMutableRawPointer: TouchFrame] = [:]   // per device
    private var slide: ActiveSlide?
    private var cornerClicks: CornerClicks?
    private var swallowUntilUp = false
    private var fineStep = false
    private var currentFlags: CGEventFlags = []

    private var settings: Settings { SettingsStore.shared.settings }
    private(set) var isRunning = false
    var statusMessage: String = "Stopped"

    private init() {}

    // MARK: lifecycle

    func start() {
        guard !isRunning else { return }
        TouchReader.shared.onFrame = { [weak self] frame in self?.ingest(frame) }
        let devices = TouchReader.shared.start()
        EventTap.shared.onMouseDown = { [weak self] e in self?.mouseDown(e) ?? false }
        EventTap.shared.onMouseDragged = { [weak self] _ in self?.mouseDragged() ?? false }
        EventTap.shared.onMouseUp = { [weak self] _ in self?.mouseUp() ?? false }
        EventTap.shared.onFlagsChanged = { [weak self] f in self?.currentFlags = f }
        let tapOK = EventTap.shared.start()
        isRunning = devices > 0 && tapOK
        statusMessage = devices == 0 ? "No trackpad found"
            : (tapOK ? "Watching \(devices) trackpad\(devices == 1 ? "" : "s")" : "Accessibility permission needed")
    }

    func stop() {
        endSlide(restorePointer: true)
        TouchReader.shared.stop()
        EventTap.shared.stop()
        isRunning = false
        statusMessage = "Stopped"
    }

    // MARK: touch frames (background thread)

    private func ingest(_ frame: TouchFrame) {
        lock.lock()
        latest[frame.device] = frame
        let active = slide
        lock.unlock()
        guard let active, active.device == frame.device else { return }
        DispatchQueue.main.async { [weak self] in self?.track(frame) }
    }

    /// The single resting finger across all devices, or nil if none/ambiguous.
    private func soleFinger() -> (TouchFrame, Touch)? {
        lock.lock(); defer { lock.unlock() }
        var found: (TouchFrame, Touch)?
        for frame in latest.values {
            // Drop stale frames: a frame older than half a second means the device is idle.
            let down = frame.touches.filter { $0.isDown }
            if down.count > 1 { return nil }          // multi-finger: ignore
            if let f = down.first {
                if found != nil { return nil }         // two trackpads touched at once
                found = (frame, f)
            }
        }
        return found
    }

    // MARK: classification

    private func region(of t: Touch, in frame: TouchFrame) -> Region? {
        let s = settings
        let stripMM = s.edgeWidth * frame.surfaceWidthMM
        let cornerW = s.cornerSize * frame.surfaceWidthMM
        let cornerH = s.cornerSize * frame.surfaceHeightMM
        let w = frame.surfaceWidthMM, h = frame.surfaceHeightMM

        if t.mmY > h - cornerH {
            if t.mmX < cornerW { return .corner(.topLeft) }
            if t.mmX > w - cornerW { return .corner(.topRight) }
        }
        if t.mmY < stripMM, s.bottomEdgeSeek { return .bottom }
        if t.mmX < stripMM { return .left }
        if t.mmX > w - stripMM { return .right }
        return nil
    }

    private func modifierSatisfied(_ flags: CGEventFlags) -> Bool {
        switch settings.requireModifier {
        case .none: return true
        case .command: return flags.contains(.maskCommand)
        case .option: return flags.contains(.maskAlternate)
        case .control: return flags.contains(.maskControl)
        case .shift: return flags.contains(.maskShift)
        }
    }

    // MARK: mouse events (main thread)

    private func mouseDown(_ event: CGEvent) -> Bool {
        guard settings.enabled, slide == nil else { return slide != nil }
        guard let (frame, finger) = soleFinger(), let region = region(of: finger, in: frame) else { return false }
        currentFlags = event.flags
        fineStep = event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)

        switch region {
        case .corner(let corner):
            guard settings.hasAnyAction(for: corner) else { return false }
            registerCornerClick(corner)
            swallowUntilUp = true
            return true

        case .left, .right:
            guard modifierSatisfied(event.flags) else { return false }
            if settings.bottomQuarterOnly, finger.y > 0.25 { return false }
            var function = region == .left ? settings.leftEdge : settings.rightEdge
            if settings.swapSides { function = region == .left ? settings.rightEdge : settings.leftEdge }
            guard function != .none else { return false }
            if function == .brightness, !Display.hasBuiltInDisplay { return false }
            beginSlide(region: region, function: function, frame: frame, finger: finger, pointer: event.location)
            return true

        case .bottom:
            guard modifierSatisfied(event.flags) else { return false }
            beginSlide(region: .bottom, function: .none, frame: frame, finger: finger, pointer: event.location)
            if settings.showSeekHUD { SeekHUD.shared.show(seconds: 0) }
            return true
        }
    }

    private func mouseDragged() -> Bool {
        return slide != nil || swallowUntilUp
    }

    private func mouseUp() -> Bool {
        if let active = slide {
            if active.region == .bottom, !active.cancelled, active.seekSteps != 0 {
                Actions.pressArrow(right: active.seekSteps > 0, times: abs(active.seekSteps))
            }
            endSlide(restorePointer: true)
            return true
        }
        if swallowUntilUp { swallowUntilUp = false; return true }
        return false
    }

    // MARK: slides

    private func beginSlide(region: Region, function: EdgeFunction, frame: TouchFrame, finger: Touch, pointer: CGPoint) {
        let stripMM = settings.edgeWidth * frame.surfaceWidthMM
        slide = ActiveSlide(region: region, function: function, device: frame.device, fingerID: finger.id,
                            startMM: CGPoint(x: finger.mmX, y: finger.mmY),
                            lastStepMM: region == .bottom ? finger.mmX : finger.mmY,
                            savedPointer: pointer, stripMM: stripMM)
        CGAssociateMouseAndMouseCursorPosition(0)
        UsageStats.recordGesture()
        haptic()
    }

    private func track(_ frame: TouchFrame) {
        guard var active = slide, !active.cancelled else { return }
        guard let finger = frame.touches.first(where: { $0.id == active.fingerID }) else {
            cancelSlide(); return
        }
        if !finger.isDown { return }   // waiting for the mouse-up to arrive
        if frame.touches.filter({ $0.isDown }).count > 1 { cancelSlide(); return }

        // Leaving the strip cancels.
        let inside: Bool
        switch active.region {
        case .left: inside = finger.mmX < active.stripMM
        case .right: inside = finger.mmX > frame.surfaceWidthMM - active.stripMM
        case .bottom: inside = finger.mmY < active.stripMM
        case .corner: inside = true
        }
        if !inside { cancelSlide(); return }

        switch active.region {
        case .left, .right:
            let step = max(1.0, settings.stepMillimetres)
            var delta = finger.mmY - active.lastStepMM
            while abs(delta) >= step {
                let up = delta > 0
                switch active.function {
                case .volume: Actions.pressSystemKey(up ? .soundUp : .soundDown, fineStep: fineStep)
                case .brightness: Actions.pressSystemKey(up ? .brightnessUp : .brightnessDown, fineStep: fineStep)
                case .none: break
                }
                haptic()
                active.lastStepMM += up ? step : -step
                delta = finger.mmY - active.lastStepMM
            }
        case .bottom:
            let step = max(1.0, settings.seekMillimetresPerStep)
            let steps = Int(((finger.mmX - active.startMM.x) / step).rounded(.towardZero))
            if steps != active.seekSteps {
                haptic()
                active.seekSteps = steps
                if settings.showSeekHUD { SeekHUD.shared.show(seconds: steps * settings.seekSecondsPerStep) }
            }
        case .corner: break
        }
        slide = active
    }

    private func cancelSlide() {
        guard var active = slide else { return }
        active.cancelled = true
        slide = active
        SeekHUD.shared.hide()
        restorePointer(active.savedPointer)
    }

    private func endSlide(restorePointer restore: Bool) {
        guard let active = slide else { return }
        slide = nil
        SeekHUD.shared.hide()
        if restore, !active.cancelled { restorePointer(active.savedPointer) }
    }

    private func restorePointer(_ point: CGPoint) {
        CGAssociateMouseAndMouseCursorPosition(1)
        CGWarpMouseCursorPosition(point)
    }

    // MARK: corners

    private func registerCornerClick(_ corner: Corner) {
        cornerClicks?.timer?.invalidate()
        var clicks = cornerClicks?.corner == corner ? cornerClicks! : CornerClicks(corner: corner, count: 0, timer: nil)
        clicks.count += 1
        let maxClicks = settings.maxClicks(for: corner)
        if clicks.count >= maxClicks {
            fireCorner(corner, clicks: clicks.count)
            cornerClicks = nil
            return
        }
        clicks.timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let self, let c = self.cornerClicks else { return }
            self.fireCorner(c.corner, clicks: c.count)
            self.cornerClicks = nil
        }
        cornerClicks = clicks
    }

    private func fireCorner(_ corner: Corner, clicks: Int) {
        guard let action = settings.action(for: corner, clicks: clicks), action.kind != .none else { return }
        haptic()
        UsageStats.recordGesture()
        Actions.perform(action)
    }

    // MARK: haptics

    private func haptic() {
        guard settings.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

enum Display {
    /// True when a built-in (laptop) display is attached and active.
    static var hasBuiltInDisplay: Bool {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }
}
