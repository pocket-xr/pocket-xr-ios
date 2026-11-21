import UIKit

// Pocket XR for iPhone and iPad, phase 0: a probe that shows a test picture on the glasses and reports what iOS lets
// the app reach. Two scenes: the phone's own screen (PhoneSceneDelegate) and the glasses, which iOS hands the app as
// an external display with the role windowExternalDisplayNonInteractive (GlassesSceneDelegate).

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Log.line("Pocket XR \(AppInfo.version) (\(AppInfo.build)) starting on \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
        Probe.shared.start()
        SelfTest.runIfAsked()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(name: "Glasses", sessionRole: session.role)
            config.delegateClass = GlassesSceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Phone", sessionRole: session.role)
        config.delegateClass = PhoneSceneDelegate.self
        return config
    }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}

/// A plain log, kept in memory for the report and printed for the Simulator and Xcode console.
enum Log {
    private static let lock = NSLock()
    private static var lines = [String]()
    private static let start = Date()

    static func line(_ s: String) {
        let stamped = String(format: "%7.2f ", Date().timeIntervalSince(start)) + s
        lock.lock()
        lines.append(stamped)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        lock.unlock()
        print("PXR " + stamped)
    }

    static var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
