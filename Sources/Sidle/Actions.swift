import AppKit
import Carbon.HIToolbox

/// System-defined media key codes (IOKit NX_KEYTYPE_*).
enum SystemKey: Int32 {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3
    case mute = 7, play = 16, next = 17, previous = 18, fast = 19, rewind = 20
}

enum Actions {
    /// Presses a system media/brightness key exactly like the hardware key would,
    /// which makes macOS show its own volume/brightness bezel.
    static func pressSystemKey(_ key: SystemKey, fineStep: Bool = false) {
        var flags: NSEvent.ModifierFlags = []
        if fineStep { flags = [.shift, .option] }   // macOS gives quarter steps with ⇧⌥
        post(key: key, down: true, flags: flags)
        post(key: key, down: false, flags: flags)
    }

    private static func post(key: SystemKey, down: Bool, flags: NSEvent.ModifierFlags) {
        let keyState: Int32 = down ? 0x0A : 0x0B
        let data1 = Int((key.rawValue << 16) | (keyState << 8))
        let modifierFlags = flags.union(down ? [] : [])
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: modifierFlags.union(NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)),
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0, context: nil,
                                             subtype: 8, data1: data1, data2: -1) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    /// Simulates a regular keyboard shortcut to the frontmost app.
    static func press(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        var cgFlags = CGEventFlags()
        if modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        if modifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
        if modifiers.contains(.control) { cgFlags.insert(.maskControl) }
        if modifiers.contains(.shift) { cgFlags.insert(.maskShift) }
        if modifiers.contains(.function) { cgFlags.insert(.maskSecondaryFn) }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = cgFlags
        up.flags = cgFlags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func pressArrow(right: Bool, times: Int) {
        let code: UInt16 = right ? UInt16(kVK_RightArrow) : UInt16(kVK_LeftArrow)
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 25)) {
                press(keyCode: code, modifiers: [])
            }
        }
    }

    /// Opens an app; if it is already frontmost, hides it instead (toggle behaviour).
    static func toggleApp(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            NSWorkspace.shared.open(url); return
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        if let app = running.first, app.isActive {
            app.hide()
        } else if let app = running.first {
            app.activate(options: [.activateAllWindows])
        } else {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    static func open(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath))
        } else if let url = URL(string: trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://" + trimmed) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs a Shortcuts.app shortcut by name in the background.
    static func runShortcut(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func missionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func lockScreen() {
        // ⌃⌘Q is the system-wide lock shortcut.
        press(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.control, .command])
    }

    static func perform(_ action: CornerAction) {
        switch action.kind {
        case .none: break
        case .mute: pressSystemKey(.mute)
        case .playPause: pressSystemKey(.play)
        case .openApp: toggleApp(path: action.value)
        case .openURL: open(link: action.value)
        case .keyboardShortcut:
            if let s = action.shortcut { press(keyCode: s.keyCode, modifiers: NSEvent.ModifierFlags(rawValue: s.modifiers)) }
        case .runShortcut: runShortcut(named: action.value)
        case .missionControl: missionControl()
        case .lockScreen: lockScreen()
        }
    }
}
