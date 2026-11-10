import AppKit

/// A HID-level event tap that lets the gesture engine claim (swallow) mouse clicks
/// that start inside an edge strip or corner, so they never reach other apps.
final class EventTap {
    static let shared = EventTap()

    /// Return true to swallow the event. Called on the main thread.
    var onMouseDown: ((CGEvent) -> Bool)?
    var onMouseDragged: ((CGEvent) -> Bool)?
    var onMouseUp: ((CGEvent) -> Bool)?
    var onFlagsChanged: ((CGEventFlags) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var isRunning = false

    private init() {}

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let tapper = EventTap.shared
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let tap = tapper.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            case .flagsChanged:
                tapper.onFlagsChanged?(event.flags)
                return Unmanaged.passUnretained(event)
            case .leftMouseDown:
                return (tapper.onMouseDown?(event) ?? false) ? nil : Unmanaged.passUnretained(event)
            case .leftMouseDragged:
                return (tapper.onMouseDragged?(event) ?? false) ? nil : Unmanaged.passUnretained(event)
            case .leftMouseUp:
                return (tapper.onMouseUp?(event) ?? false) ? nil : Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback, userInfo: nil) else {
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; isRunning = false
    }
}
