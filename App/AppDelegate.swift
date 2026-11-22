import UIKit

// Pocket XR for iPhone and iPad, phase 0: a probe that shows a test picture on the glasses and reports what iOS lets
// the app reach. Two scenes: the phone's own screen (PhoneSceneDelegate) and the glasses, which iOS hands the app as
// an external display with the role windowExternalDisplayNonInteractive (GlassesSceneDelegate).

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppLog.line("Pocket XR \(AppInfo.version) (\(AppInfo.build)) starting on \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
        Probe.shared.start()
        PcCrypto.installGcm()
        UIDeviceName.name = UIDevice.current.name
        _ = SpaceController.shared
        MouseInput.shared.start()
        SelfTest.runIfAsked()
        SpaceSelfTest.runIfAsked()
        // For finding out how iOS hands over the glasses: every screen it reports, as it comes and goes.
        for name in [UIScreen.didConnectNotification, UIScreen.didDisconnectNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { n in
                let s = n.object as? UIScreen
                AppLog.line("screen: \(n.name.rawValue), \(s.map { "\(Int($0.bounds.width))x\(Int($0.bounds.height))" } ?? "?")")
            }
        }
        NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { n in
            let s = n.object as? UIScene
            AppLog.line("scene: connected, role \(s?.session.role.rawValue ?? "?")")
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        AppLog.line("scene: iOS offers a scene with role \(session.role.rawValue)")
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

/// A string in the phone's language (App/Resources/Localizable.xcstrings: the 11 languages Pocket XR for Android
/// speaks); English when it has no translation.
func L(_ s: String) -> String { NSLocalizedString(s, comment: "") }

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}

/// A plain log, kept in memory for the report and printed for the Simulator and Xcode console.
enum AppLog {
    private static let lock = NSLock()
    private static var lines = [String]()
    private static let start = Date()

    static func line(_ s: String) {
        let stamped = String(format: "%7.2f ", Date().timeIntervalSince(start)) + s
        lock.lock()
        lines.append(stamped)
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
        if let h = file { h.write(Data((stamped + "\n").utf8)) }
        lock.unlock()
        print("PXR " + stamped)
    }

    /// Documents/pocketxr-log.txt, rewritten at each start: CI reads it from the Simulator, and the Files app shows it.
    private static let file: FileHandle? = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pocketxr-log.txt")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()

    static var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
