import AppKit
import Combine

/// Every outward link in one place.
enum Links {
    static let githubUser = "rp6186030"
    static let repoName = "sidle"
    /// Buy Me a Coffee handle. Change this one constant if the handle differs.
    static let coffeeHandle = "rp6186060x"

    static var repo: URL { URL(string: "https://github.com/\(githubUser)/\(repoName)")! }
    static var issues: URL { URL(string: "https://github.com/\(githubUser)/\(repoName)/issues/new/choose")! }
    static var releases: URL { URL(string: "https://github.com/\(githubUser)/\(repoName)/releases/latest")! }
    static var latestReleaseAPI: URL { URL(string: "https://api.github.com/repos/\(githubUser)/\(repoName)/releases/latest")! }
    static var coffee: URL { URL(string: "https://buymeacoffee.com/\(coffeeHandle)")! }

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Local-only usage counters that decide when to show the one-time coffee banner.
/// Nothing here leaves the Mac.
enum UsageStats {
    private static let d = UserDefaults.standard
    private static let countKey = "Sidle.gestureCount"
    private static let firstKey = "Sidle.firstLaunch"
    private static let dismissedKey = "Sidle.coffeeBannerDismissed"

    static func noteLaunch() {
        if d.object(forKey: firstKey) == nil { d.set(Date(), forKey: firstKey) }
    }
    static func recordGesture() { d.set(gestureCount + 1, forKey: countKey) }
    static var gestureCount: Int { d.integer(forKey: countKey) }
    static var daysInUse: Int {
        guard let first = d.object(forKey: firstKey) as? Date else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
    }
    /// Shown once, in the settings window only, after real use.
    static var shouldShowCoffeeBanner: Bool {
        !d.bool(forKey: dismissedKey) && daysInUse >= 30 && gestureCount >= 500
    }
    static func dismissCoffeeBanner() { d.set(true, forKey: dismissedKey) }
}

/// Checks GitHub Releases for a newer version. Never downloads anything by itself.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published private(set) var availableVersion: String?
    @Published private(set) var lastResult: String = ""
    private var timer: Timer?
    private let lastCheckKey = "Sidle.lastUpdateCheck"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func startDailyChecks() {
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 86_400 { check() }
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.check() }
    }

    func check(userInitiated: Bool = false) {
        var request = URLRequest(url: Links.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var newer: String?
            var message = "Could not reach GitHub."
            if let data,
               (response as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isVersion(latest, newerThan: Self.currentVersion) {
                    newer = latest
                    message = "Sidle \(latest) is available."
                } else {
                    message = "Sidle \(Self.currentVersion) is the latest version."
                }
            } else if (response as? HTTPURLResponse)?.statusCode == 404 {
                message = "No releases published yet."
            }
            DispatchQueue.main.async {
                guard let self else { return }
                UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)
                self.availableVersion = newer
                self.lastResult = message
                NotificationCenter.default.post(name: .sidleStatusChanged, object: nil)
                if userInitiated { self.present(message, hasUpdate: newer != nil) }
            }
        }.resume()
    }

    private func present(_ message: String, hasUpdate: Bool) {
        let alert = NSAlert()
        alert.messageText = message
        if hasUpdate {
            alert.informativeText = "Download it from the GitHub release page."
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Later")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, hasUpdate { Links.open(Links.releases) }
    }

    /// Numeric dotted comparison: 1.10.0 > 1.9.3.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
