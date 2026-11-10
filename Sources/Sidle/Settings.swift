import Foundation
import Combine

enum EdgeFunction: String, Codable, CaseIterable, Identifiable {
    case volume, brightness, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .none: return "Off"
        }
    }
}

enum ModifierRequirement: String, Codable, CaseIterable, Identifiable {
    case none, command, option, control, shift
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        }
    }
}

enum Corner: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight
    var id: String { rawValue }
    var label: String { self == .topLeft ? "Top-left corner" : "Top-right corner" }
}

struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt   // NSEvent.ModifierFlags raw value
}

struct CornerAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case none, mute, openApp, openURL, keyboardShortcut, runShortcut, playPause, missionControl, lockScreen
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "Nothing"
            case .mute: return "Mute / unmute"
            case .openApp: return "Open app (click again to hide)"
            case .openURL: return "Open link, file or folder"
            case .keyboardShortcut: return "Press keyboard shortcut"
            case .runShortcut: return "Run a Shortcut"
            case .playPause: return "Play / pause"
            case .missionControl: return "Mission Control"
            case .lockScreen: return "Lock screen"
            }
        }
    }
    var id: Int { clickCount }
    var clickCount: Int
    var kind: Kind = .none
    var value: String = ""          // app path, URL, or Shortcut name
    var shortcut: KeyShortcut? = nil
}

struct Settings: Codable, Equatable {
    var enabled = true
    var edgeWidth: Double = 0.10            // fraction of trackpad width
    var cornerSize: Double = 0.12           // fraction of trackpad width/height
    var stepMillimetres: Double = 4.0       // slide distance per volume/brightness step
    var seekMillimetresPerStep: Double = 6.0
    var seekSecondsPerStep: Int = 5         // informational; apps map an arrow key to ~5 s
    var swapSides = false
    var bottomQuarterOnly = false
    var requireModifier: ModifierRequirement = .none
    var haptics = true
    var leftEdge: EdgeFunction = .brightness
    var rightEdge: EdgeFunction = .volume
    var bottomEdgeSeek = true
    var showSeekHUD = true
    var cornerActions: [Corner: [CornerAction]] = [
        .topLeft: (1...4).map { CornerAction(clickCount: $0, kind: $0 == 1 ? .mute : .none) },
        .topRight: (1...4).map { CornerAction(clickCount: $0) },
    ]
    var launchAtLogin = false

    func action(for corner: Corner, clicks: Int) -> CornerAction? {
        cornerActions[corner]?.first { $0.clickCount == clicks }
    }
    func hasAnyAction(for corner: Corner) -> Bool {
        cornerActions[corner]?.contains { $0.kind != .none } ?? false
    }
    /// Highest click count that has an action on this corner (so we know how long to wait for more clicks).
    func maxClicks(for corner: Corner) -> Int {
        cornerActions[corner]?.filter { $0.kind != .none }.map(\.clickCount).max() ?? 0
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "SidleSettings.v1"

    @Published var settings: Settings {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
