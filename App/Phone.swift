import SwiftUI
import UIKit
import PocketXRCore

final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ProbeView().environmentObject(AppModel.shared))
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// The phone's screen in phase 0: what iOS reports about the glasses and their USB network, with a report to share.
struct ProbeView: View {
    @EnvironmentObject var model: AppModel
    @State private var axesOne = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Plug XR glasses into this iPhone or iPad's USB-C port. This test version shows a test picture on them and checks what iOS lets Pocket XR reach. Share the report with Mike.")
                        .font(.callout)
                }
                Section("Glasses display") {
                    row("Connected", model.display.connected ? "Yes" : "No")
                    if model.display.connected {
                        row("Size", "\(Int(model.display.widthPt))x\(Int(model.display.heightPt)) pt at \(String(format: "%.1f", model.display.scale))x")
                        row("Native", "\(Int(model.display.nativeWidth))x\(Int(model.display.nativeHeight))")
                        row("Refresh", "\(model.display.maxFps) Hz")
                        row("Modes", model.display.modes.joined(separator: ", "))
                        row("Current mode", model.display.currentMode)
                        Toggle("Draw side by side", isOn: $model.sideBySide)
                    }
                }
                Section("Glasses USB network") {
                    row("Interfaces", model.probe.interfaces)
                    row("Glasses links", model.probe.routes.isEmpty ? "None found" : model.probe.routes.joined(separator: ", "))
                }
                Section("Head tracking (TCP 52998)") {
                    row("Sensor stream", model.probe.link.rawValue.capitalized)
                    if !model.probe.via.isEmpty { row("Via", model.probe.via) }
                    if !model.probe.lastError.isEmpty && model.probe.link != .streaming { row("Last error", model.probe.lastError) }
                    row("Reports", "\(model.probe.reports) (\(model.probe.imuReports) motion)")
                    row("Rate", String(format: "%.0f Hz", model.probe.imuRateHz))
                    row("Yaw, pitch", String(format: "%.1f°, %.1f°", model.probe.yawDeg, model.probe.pitchDeg))
                    Toggle("XREAL One family axes", isOn: $axesOne)
                        .onChange(of: axesOne) { _, on in Probe.shared.setAxes(on ? .one : .aura) }
                    Button("Recentre") { Probe.shared.recentre() }
                }
                Section {
                    ShareLink(item: Report.make(display: model.display, probe: model.probe).text) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = Report.make(display: model.display, probe: model.probe).text
                    } label: {
                        Label("Copy report", systemImage: "doc.on.doc")
                    }
                }
                Section {
                    Text("Pocket XR \(AppInfo.version) (\(AppInfo.build)), phase 0 test version").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pocket XR")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

/// The report Mike gets: what iOS said, and the log.
struct Report: Codable {
    var app: String
    var device: String
    var system: String
    var display: DisplayInfo
    var probe: ProbeState
    var log: String

    @MainActor
    static func make(display: DisplayInfo, probe: ProbeState) -> Report {
        Report(app: "\(AppInfo.version) (\(AppInfo.build))", device: deviceModel(), system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
               display: display, probe: probe, log: Log.text)
    }

    var text: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        var copy = self
        copy.log = ""
        let json = (try? enc.encode(copy)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "Pocket XR for iOS probe report\n\n\(json)\n\nLog:\n\(log)\n"
    }

    static func deviceModel() -> String {
        var sys = utsname()
        uname(&sys)
        let id = withUnsafeBytes(of: &sys.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
        return id.isEmpty ? UIDevice.current.model : id
    }
}
