import AppKit
import SwiftUI
import ServiceManagement

@main
struct SidleMain {
    static func main() {
        if CommandLine.arguments.contains("--dump-touches") { dumpTouches() }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        app.run()
    }
}

/// Debug helper: prints raw frames to stderr for a few seconds, then exits.
private func dumpTouches() {
    var frames = 0
    TouchReader.shared.onFrame = { frame in
        frames += 1
        if frames % 10 != 1 { return }
        let desc = frame.touches.map { t in
            String(format: "#%d st=%d x=%.3f y=%.3f mm=(%.1f,%.1f) size=%.2f", t.id, t.state, t.x, t.y, t.mmX, t.mmY, t.size)
        }.joined(separator: " | ")
        FileHandle.standardError.write("frame surface=\(frame.surfaceWidthMM)x\(frame.surfaceHeightMM)mm \(desc)\n".data(using: .utf8)!)
    }
    let count = TouchReader.shared.start()
    FileHandle.standardError.write("started \(count) multitouch device(s); listening 6s…\n".data(using: .utf8)!)
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
        FileHandle.standardError.write("received \(frames) frames\n".data(using: .utf8)!)
        exit(0)
    }
    RunLoop.main.run()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private let store = SettingsStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageStats.noteLaunch()
        buildStatusItem()
        UpdateChecker.shared.startDailyChecks()
        NotificationCenter.default.addObserver(forName: .sidleStatusChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshMenu()
        }
        if EventTap.hasAccessibilityPermission(prompt: false) {
            GestureEngine.shared.start()
        } else {
            openSettings()
            EventTap.hasAccessibilityPermission(prompt: true)
            waitForPermission()
        }
        refreshMenu()
    }

    private func waitForPermission() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard EventTap.hasAccessibilityPermission(prompt: false) else { return }
            t.invalidate()
            GestureEngine.shared.start()
            NotificationCenter.default.post(name: .sidleStatusChanged, object: nil)
        }
    }

    // MARK: status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.inset.filled.on.rectangle", accessibilityDescription: "Sidle")
            button.image?.isTemplate = true
        }
        statusItem.menu = NSMenu()
    }

    func refreshMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: GestureEngine.shared.statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: store.settings.enabled ? "Disable gestures" : "Enable gestures",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        if let version = UpdateChecker.shared.availableVersion {
            let update = NSMenuItem(title: "Sidle \(version) is available…", action: #selector(openReleases), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        } else {
            let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            check.target = self
            menu.addItem(check)
        }
        let coffee = NSMenuItem(title: "Buy Me a Coffee…", action: #selector(openCoffee), keyEquivalent: "")
        coffee.target = self
        menu.addItem(coffee)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Sidle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.appearsDisabled = !store.settings.enabled
    }

    @objc private func toggleEnabled() {
        store.settings.enabled.toggle()
        refreshMenu()
    }

    @objc private func openReleases() { Links.open(Links.releases) }
    @objc private func checkForUpdates() { UpdateChecker.shared.check(userInitiated: true) }
    @objc private func openCoffee() { Links.open(Links.coffee) }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView().environmentObject(store)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Sidle"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 560, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let sidleStatusChanged = Notification.Name("SidleStatusChanged")
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Login item change failed: \(error)")
        }
    }
}
