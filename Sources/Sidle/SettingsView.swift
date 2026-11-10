import SwiftUI
import Carbon.HIToolbox
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var status = GestureEngine.shared.statusMessage
    @State private var hasAccessibility = EventTap.hasAccessibilityPermission(prompt: false)
    @State private var showCoffeeBanner = UsageStats.shouldShowCoffeeBanner
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        TabView {
            gesturesTab.tabItem { Label("Gestures", systemImage: "hand.draw") }
            cornersTab.tabItem { Label("Corners", systemImage: "square.topthird.inset.filled") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(12)
        .frame(width: 560, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: .sidleStatusChanged)) { _ in
            status = GestureEngine.shared.statusMessage
            hasAccessibility = EventTap.hasAccessibilityPermission(prompt: false)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = EventTap.hasAccessibilityPermission(prompt: false)
            status = GestureEngine.shared.statusMessage
        }
    }

    // MARK: Gestures

    private var gesturesTab: some View {
        Form {
            if !hasAccessibility {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("Accessibility permission needed").bold()
                            Text("Sidle presses the volume and brightness keys for you and keeps edge clicks out of other apps. Allow it under System Settings → Privacy & Security → Accessibility.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            if showCoffeeBanner {
                Section {
                    HStack {
                        Text("☕️").font(.title2)
                        VStack(alignment: .leading) {
                            Text("Enjoying Sidle?").bold()
                            Text("You have made \(UsageStats.gestureCount) edge gestures. Sidle is free; a coffee keeps it going.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Buy me a coffee") { Links.open(Links.coffee); dismissBanner() }
                        Button("No thanks") { dismissBanner() }.buttonStyle(.link)
                    }
                }
            }
            Section {
                Toggle("Enable edge gestures", isOn: $store.settings.enabled)
                LabeledContent("Status", value: status)
            }
            Section("Edges") {
                Picker("Left edge", selection: $store.settings.leftEdge) {
                    ForEach(EdgeFunction.allCases) { Text($0.label).tag($0) }
                }
                Picker("Right edge", selection: $store.settings.rightEdge) {
                    ForEach(EdgeFunction.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Swap sides", isOn: $store.settings.swapSides)
                Toggle("Bottom edge scrubs media timeline", isOn: $store.settings.bottomEdgeSeek)
                Toggle("Show seek preview while scrubbing", isOn: $store.settings.showSeekHUD)
                    .disabled(!store.settings.bottomEdgeSeek)
            }
            Section("Tuning") {
                slider("Edge width", value: $store.settings.edgeWidth, range: 0.05...0.25,
                       format: "\(Int(store.settings.edgeWidth * 100))% of trackpad")
                slider("Sensitivity (mm per step)", value: $store.settings.stepMillimetres, range: 1.5...12,
                       format: String(format: "%.1f mm", store.settings.stepMillimetres))
                slider("Seek distance (mm per step)", value: $store.settings.seekMillimetresPerStep, range: 2...15,
                       format: String(format: "%.1f mm", store.settings.seekMillimetresPerStep))
                Stepper("Seconds per seek step: \(store.settings.seekSecondsPerStep)",
                        value: $store.settings.seekSecondsPerStep, in: 1...60)
                Toggle("Limit slides to the bottom quarter", isOn: $store.settings.bottomQuarterOnly)
                Picker("Require modifier key", selection: $store.settings.requireModifier) {
                    ForEach(ModifierRequirement.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Haptic click on each step", isOn: $store.settings.haptics)
            }
            Section {
                Text("Rest one finger in an edge strip, press until the trackpad clicks, then slide. Hold ⇧⌥ while sliding for quarter steps. Leaving the strip cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func dismissBanner() {
        UsageStats.dismissCoffeeBanner()
        showCoffeeBanner = false
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(format).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range)
        }
    }

    // MARK: Corners

    private var cornersTab: some View {
        Form {
            Section {
                Text("Click a top corner 1 to 4 times to run an action. A corner with no actions stays a normal part of the trackpad. Bottom corners belong to the media strip.")
                    .font(.caption).foregroundStyle(.secondary)
                slider("Corner size", value: $store.settings.cornerSize, range: 0.06...0.25,
                       format: "\(Int(store.settings.cornerSize * 100))%")
            }
            ForEach(Corner.allCases) { corner in
                Section(corner.label) {
                    ForEach(1...4, id: \.self) { clicks in
                        CornerActionRow(action: binding(for: corner, clicks: clicks))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for corner: Corner, clicks: Int) -> Binding<CornerAction> {
        Binding(
            get: {
                store.settings.action(for: corner, clicks: clicks) ?? CornerAction(clickCount: clicks)
            },
            set: { newValue in
                var list = store.settings.cornerActions[corner] ?? []
                if let i = list.firstIndex(where: { $0.clickCount == clicks }) { list[i] = newValue } else { list.append(newValue) }
                store.settings.cornerActions[corner] = list
            })
    }

    // MARK: About

    private var aboutTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text("Sidle").font(.title2).bold()
                        Text("Volume, brightness and media controls on your trackpad edges.")
                            .foregroundStyle(.secondary)
                        Text("Version \(UpdateChecker.currentVersion)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("Sidle is free and open source. If it saves you a reach for the keyboard, buy me a coffee.")
                HStack {
                    Button("☕️ Buy me a coffee") { Links.open(Links.coffee) }
                    Button("Star on GitHub") { Links.open(Links.repo) }
                    Button("Report a problem") { Links.open(Links.issues) }
                }
            }
            Section("Updates") {
                HStack {
                    if let version = updates.availableVersion {
                        Text("Sidle \(version) is available.")
                        Spacer()
                        Button("Open Release Page") { Links.open(Links.releases) }
                    } else {
                        Text(updates.lastResult.isEmpty ? "Checks GitHub once a day." : updates.lastResult)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { updates.check() }
                    }
                }
            }
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.set($0); store.settings.launchAtLogin = $0 }))
                LabeledContent("Accessibility", value: hasAccessibility ? "Granted" : "Not granted")
                LabeledContent("Trackpad", value: status)
            }
            Section("How it works") {
                Text("Sidle reads raw finger positions from your trackpad, so it can tell an edge press from an ordinary click. Touches never leave your Mac. Volume and brightness changes are made by pressing the same keys your keyboard uses, so you see the normal macOS indicators.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Corner action row

struct CornerActionRow: View {
    @Binding var action: CornerAction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(clickLabel).frame(width: 90, alignment: .leading)
                Picker("", selection: $action.kind) {
                    ForEach(CornerAction.Kind.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            switch action.kind {
            case .openApp:
                HStack {
                    Text(action.value.isEmpty ? "No app chosen" : (action.value as NSString).lastPathComponent)
                        .foregroundStyle(action.value.isEmpty ? .secondary : .primary)
                    Spacer()
                    Button("Choose App…") { chooseApp() }
                }.padding(.leading, 96)
            case .openURL:
                TextField("https://example.com, /Users/you/Documents, or an app link", text: $action.value)
                    .textFieldStyle(.roundedBorder).padding(.leading, 96)
            case .runShortcut:
                TextField("Shortcut name (as shown in the Shortcuts app)", text: $action.value)
                    .textFieldStyle(.roundedBorder).padding(.leading, 96)
            case .keyboardShortcut:
                HStack {
                    ShortcutRecorder(shortcut: $action.shortcut)
                    Spacer()
                }.padding(.leading, 96)
            default:
                EmptyView()
            }
        }
    }

    private var clickLabel: String {
        switch action.clickCount {
        case 1: return "Single click"
        case 2: return "Double click"
        case 3: return "Triple click"
        default: return "\(action.clickCount) clicks"
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { action.value = url.path }
    }
}

// MARK: - Shortcut recorder

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyShortcut?

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onChange = { shortcut = $0 }
        return v
    }
    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.shortcut = shortcut
        nsView.onChange = { shortcut = $0 }
    }

    final class RecorderView: NSView {
        var shortcut: KeyShortcut? { didSet { needsDisplay = true } }
        var onChange: ((KeyShortcut?) -> Void)?
        private var recording = false { didSet { needsDisplay = true } }

        override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 26) }
        override var acceptsFirstResponder: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording = true
        }
        override func resignFirstResponder() -> Bool { recording = false; return true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { // Escape clears
                shortcut = nil; onChange?(nil); recording = false; window?.makeFirstResponder(nil); return
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
            let s = KeyShortcut(keyCode: event.keyCode, modifiers: mods.rawValue)
            shortcut = s
            onChange?(s)
            recording = false
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            NSColor.controlBackgroundColor.setFill()
            path.fill(); path.stroke()
            let text = recording ? "Press keys… (esc clears)" : (shortcut.map(Self.describe) ?? "Click to record shortcut")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: shortcut == nil || recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }

        static func describe(_ s: KeyShortcut) -> String {
            let f = NSEvent.ModifierFlags(rawValue: s.modifiers)
            var out = ""
            if f.contains(.control) { out += "⌃" }
            if f.contains(.option) { out += "⌥" }
            if f.contains(.shift) { out += "⇧" }
            if f.contains(.command) { out += "⌘" }
            if f.contains(.function) { out += "fn " }
            return out + keyName(s.keyCode)
        }

        static func keyName(_ code: UInt16) -> String {
            let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                             122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                                             101: "F9", 109: "F10", 103: "F11", 111: "F12", 76: "⌤", 117: "⌦", 115: "↖", 119: "↘"]
            if let s = special[code] { return s }
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "key \(code)" }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            var dead: UInt32 = 0
            let status = data.withUnsafeBytes { buf -> OSStatus in
                UCKeyTranslate(buf.bindMemory(to: UCKeyboardLayout.self).baseAddress, code, UInt16(kUCKeyActionDisplay), 0,
                               UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
            }
            guard status == noErr, length > 0 else { return "key \(code)" }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}
