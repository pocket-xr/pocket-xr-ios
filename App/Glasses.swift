import SwiftUI
import UIKit
import PocketXRCore

/// What iOS says about the external display (the glasses), for the phone screen and the report.
struct DisplayInfo: Codable, Equatable {
    var connected = false
    var widthPt = 0.0
    var heightPt = 0.0
    var scale = 0.0
    var nativeWidth = 0.0
    var nativeHeight = 0.0
    var maxFps = 0
    var modes = [String]()
    var currentMode = ""

    static func of(_ screen: UIScreen) -> DisplayInfo {
        var d = DisplayInfo()
        d.connected = true
        d.widthPt = screen.bounds.width
        d.heightPt = screen.bounds.height
        d.scale = screen.scale
        d.nativeWidth = screen.nativeBounds.width
        d.nativeHeight = screen.nativeBounds.height
        d.maxFps = screen.maximumFramesPerSecond
        d.modes = screen.availableModes.map { "\(Int($0.size.width))x\(Int($0.size.height))" }
        if let m = screen.currentMode { d.currentMode = "\(Int(m.size.width))x\(Int(m.size.height))" }
        return d
    }
}

/// Shared between the two scenes.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var display = DisplayInfo()
    @Published var probe = ProbeState()
    @Published var sideBySide = false

    private init() {
        Probe.shared.onChange = { [weak self] s in self?.probe = s }
    }
}

/// The glasses' scene: iOS gives it the external display while Pocket XR is in front on the phone.
final class GlassesSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let screen = windowScene.screen
        let info = DisplayInfo.of(screen)
        Log.line("glasses: external display connected, \(Int(info.widthPt))x\(Int(info.heightPt)) pt at \(info.scale)x, native \(Int(info.nativeWidth))x\(Int(info.nativeHeight)), \(info.maxFps) fps, modes \(info.modes.joined(separator: " ")), current \(info.currentMode)")
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: GlassesView().environmentObject(AppModel.shared))
        window.isHidden = false
        self.window = window
        AppModel.shared.display = info
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Log.line("glasses: external display gone")
        AppModel.shared.display = DisplayInfo()
        UIApplication.shared.isIdleTimerDisabled = false
        window = nil
    }
}

/// The test picture on the glasses: a grid to the edges, the size iOS reports, and a panel that the head's turn moves
/// the other way, as a held-still window would. Drawn twice, once per eye, when the display is side by side (wider
/// than 3:1) or side by side is switched on.
struct GlassesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let sbs = model.sideBySide || geo.size.width / max(geo.size.height, 1) > 3
            TimelineView(.animation) { _ in
                let q = Probe.shared.view()
                HStack(spacing: 0) {
                    if sbs {
                        GlassesPicture(size: CGSize(width: geo.size.width / 2, height: geo.size.height), head: q, probe: model.probe, eye: "left")
                        GlassesPicture(size: CGSize(width: geo.size.width / 2, height: geo.size.height), head: q, probe: model.probe, eye: "right")
                    } else {
                        GlassesPicture(size: geo.size, head: q, probe: model.probe, eye: nil)
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

struct GlassesPicture: View {
    let size: CGSize
    let head: Quat
    let probe: ProbeState
    let eye: String?

    /// The Aura's horizontal field of view is about 70 degrees in its widest mode; near enough for a test picture.
    static let fovDeg = 46.0

    var body: some View {
        let pxPerDeg = size.width / Self.fovDeg
        let forward = head.rotate(SIMD3(0, 0, -1))
        let yaw = head.yaw * 180 / .pi
        let pitch = asin(max(-1, min(1, forward.y))) * 180 / .pi
        ZStack {
            Canvas { ctx, sz in
                let grid = Path { p in
                    for i in 0...10 {
                        let x = sz.width * CGFloat(i) / 10
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: sz.height))
                        let y = sz.height * CGFloat(i) / 10
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: sz.width, y: y))
                    }
                }
                ctx.stroke(grid, with: .color(.white.opacity(0.18)), lineWidth: 1)
                ctx.stroke(Path(CGRect(origin: .zero, size: sz).insetBy(dx: 1, dy: 1)), with: .color(.white.opacity(0.7)), lineWidth: 2)
            }
            VStack(spacing: 6) {
                Text("Pocket XR").font(.system(size: size.height * 0.05, weight: .semibold))
                Text("Glasses test picture\(eye.map { ", \($0) eye" } ?? "")").font(.system(size: size.height * 0.03))
                Text("\(Int(size.width))x\(Int(size.height)) pt drawn").font(.system(size: size.height * 0.025)).opacity(0.7)
                Text(probe.link == .streaming ? String(format: "Head tracking: %.0f Hz, yaw %.1f°, pitch %.1f°", probe.imuRateHz, yaw, pitch) : "Head tracking: no sensor stream (\(probe.link.rawValue))")
                    .font(.system(size: size.height * 0.025)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .offset(y: -size.height * 0.3)
            RoundedRectangle(cornerRadius: size.height * 0.03)
                .fill(Color(red: 0.08, green: 0.1, blue: 0.16).opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: size.height * 0.03).stroke(Color(red: 0.35, green: 0.58, blue: 1), lineWidth: 3))
                .overlay(Text("A window held in place").font(.system(size: size.height * 0.035)).foregroundStyle(.white))
                .frame(width: size.width * 0.36, height: size.height * 0.32)
                .offset(x: CGFloat(yaw) * pxPerDeg, y: CGFloat(pitch) * pxPerDeg + size.height * 0.08)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
