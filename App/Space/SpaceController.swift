import Combine
import PocketXRCore
import UIKit
import WebKit

/// A saved layout: the windows as they were, reopened exactly (Android's window presets).
struct SavedLayout: Codable, Equatable {
    var name: String
    var space: SpaceWindows
}

/// The Space: its windows, the pointer, the head's pose, and every input from the phone, a mouse or a keyboard.
@MainActor
final class SpaceController: ObservableObject {
    static let shared = SpaceController()

    enum Mode: String {
        case none, move, resize, depth, moveAll
    }

    @Published private(set) var space = SpaceWindows()
    @Published private(set) var presets = [SavedLayout]()
    @Published private(set) var mode = Mode.none
    @Published var spatialMouse = false
    /// The phone's keyboard is up (the Keyboard button). Clicking into a web field never raises it by itself.
    @Published var keyboardOn = false
    /// Where the Space is drawn: the glasses, or the phone's preview when no glasses are connected.
    @Published private(set) var onGlasses = false

    private(set) var pointer = SpacePointer()
    private(set) var pointerDistance = SpaceLayout.defaultDistance
    private(set) var hover: SpaceHit?
    private(set) var head = Quat.identity
    /// Head tracking choices (Control Center): tracking on or off, stay in place or Smooth Follow; drawing smoothing
    /// and the Still lock on, as on the other platforms.
    @Published private(set) var tracking = SpaceSettings()
    private var lookYawDeg = 0.0
    private var lookPitchDeg = 0.0
    private var hosts = [UUID: WindowHost]()
    private var dragging: UUID?
    private var lastHoverSent = 0.0
    private var pointerMoved = false
    private var saveTimer: Timer?
    private var controlPanel: ControlCenterPanel?
    let view = SpaceView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private var glassesContainer: UIView?
    private var previewContainer: UIView?

    private init() {
        load()
        for w in space.windows { makeHost(w) }
        view.sync(hosts: hosts)
        if space.windows.isEmpty { openLauncher() }
    }

    // MARK: Where it is drawn

    func attachGlasses(_ container: UIView?) {
        glassesContainer = container
        placeView()
    }

    func attachPreview(_ container: UIView?) {
        previewContainer = container
        placeView()
    }

    private func placeView() {
        let target = glassesContainer ?? previewContainer
        onGlasses = glassesContainer != nil
        guard let t = target else { view.removeFromSuperview(); return }
        if view.superview !== t {
            view.removeFromSuperview()
            view.frame = t.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            t.addSubview(view)
        }
    }

    // MARK: Each frame

    /// Head tracking is drawing the Space: the glasses' sensor stream is up and tracking is switched on.
    var tracked: Bool { tracking.headTracking && Probe.shared.snapshot.link == .streaming }

    /// The view's direction (yaw, pitch).
    var viewAim: SpaceAim { SpaceAim.of(head.rotate(SIMD3(0, 0, -1))) }

    func tick(now: Double, period: Double, view: SpaceView) {
        if tracked {
            head = Probe.shared.drawPose(now: now, framePeriod: period, options: TrackingOptions(tracking))
        } else {
            head = Quat.aboutY(lookYawDeg * .pi / 180) * Quat.aboutX(lookPitchDeg * .pi / 180)
        }
        let (hx, hy) = view.halfFovDeg
        let over = pointer.keep(inside: viewAim, halfWidthDeg: hx, halfHeightDeg: hy)
        if !tracked, over.yawDeg != 0 || over.pitchDeg != 0 {
            // No head tracking: pushing the pointer past the edge looks that way.
            lookYawDeg = SpaceAim.wrap(lookYawDeg + over.yawDeg)
            lookPitchDeg = min(max(lookPitchDeg + over.pitchDeg, -60), 60)
        }
        hover = space.hit(pointer.aim)
        pointerDistance = hover?.distance ?? SpaceLayout.defaultDistance
        if pointerMoved, let h = hover, now - lastHoverSent > 0.05, let host = hosts[h.id] {
            let p = point(on: host, h)
            if !host.onBar(p) { host.content.hover(at: p) }
            lastHoverSent = now
            pointerMoved = false
        }
    }

    private func point(on host: WindowHost, _ h: SpaceHit) -> CGPoint {
        CGPoint(x: h.u * host.bounds.width, y: h.v * host.bounds.height)
    }

    /// Where on the content (not the window as a whole) the pointer is, for web input.
    private func contentPoint() -> (WindowHost, CGPoint)? {
        guard let h = hover, let host = hosts[h.id] else { return nil }
        return (host, point(on: host, h))
    }

    // MARK: Pointer and keys

    /// A pointer move from the trackpad, the Spatial Mouse or a mouse, in trackpad points (right, down positive).
    func pointerMove(dx: Double, dy: Double, speed: Double = 1) {
        switch mode {
        case .none:
            let before = pointer.aim
            pointer.drag(dx: dx, dy: dy, speed: speed)
            if let id = dragging {
                space.move(id, dYawDeg: SpaceAim.wrap(pointer.aim.yawDeg - before.yawDeg), dPitchDeg: pointer.aim.pitchDeg - before.pitchDeg)
            }
            pointerMoved = true
        case .move:
            guard let id = space.focused else { return }
            space.move(id, dYawDeg: -dx / SpacePointer.pointsPerDeg * speed, dPitchDeg: -dy / SpacePointer.pointsPerDeg * speed)
        case .resize:
            guard let id = space.focused else { return }
            space.resize(id, dWidthDeg: (dx - dy) / SpacePointer.pointsPerDeg * speed * 0.6)
        case .depth:
            guard let id = space.focused else { return }
            space.push(id, steps: -dy / 60 * speed)
        case .moveAll:
            space.moveAll(dYawDeg: -dx / SpacePointer.pointsPerDeg * speed, dPitchDeg: -dy / SpacePointer.pointsPerDeg * speed)
        }
        changed()
    }

    /// A one-finger press starts: on a window's bar it picks the window up to drag (unless locked).
    func pressBegan() {
        guard mode == .none, !space.locked, let (host, p) = contentPoint(), host.onBar(p) else { return }
        dragging = host.id
        space.focus(host.id)
    }

    func pressEnded() {
        if let id = dragging {
            space.snap(id)
            changed()
        }
        dragging = nil
    }

    /// A tap: focuses the window under the pointer and clicks there.
    func click() {
        if mode != .none { setMode(.none); return }
        guard let (host, p) = contentPoint() else { return }
        space.focus(host.id)
        host.click(at: p)
        changed(save: false)
        // A click into a web page's text field makes WebKit take the keyboard focus and raise iOS's keyboard; the
        // key catcher takes it back (the field stays focused in the page, so typing still lands there).
        for delay in [0.0, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { KeyCatcher.current?.takeFocus() }
        }
    }

    func scroll(dx: Double, dy: Double) {
        if mode == .depth || mode == .resize {
            pointerMove(dx: dx, dy: dy)
            return
        }
        guard let (host, p) = contentPoint(), !host.onBar(p) else { return }
        host.content.scroll(at: p, dx: dx, dy: dy)
    }

    /// Two-finger pinch: resizes the focused window (or every window in Adjust all).
    func pinch(scaleChange: Double) {
        let d = (scaleChange - 1) * 40
        if mode == .moveAll { space.resizeAll(dWidthDeg: d) } else if let id = space.focused { space.resize(id, dWidthDeg: d) }
        changed()
    }

    /// Three-finger swipes: left and right go between windows, up opens the launcher, down the Control Center.
    func swipe(_ direction: UISwipeGestureRecognizer.Direction) {
        switch direction {
        case .left: space.focusNext(forward: true); bringFocusedIntoView()
        case .right: space.focusNext(forward: false); bringFocusedIntoView()
        case .up: openLauncher()
        case .down: openControlCenter()
        default: break
        }
        changed(save: false)
    }

    func type(_ text: String) {
        guard let id = space.focused, let host = hosts[id] else { return }
        host.content.type(text)
    }

    func key(_ name: String) {
        guard let id = space.focused, let host = hosts[id] else { return }
        host.content.key(name)
    }

    func back() {
        guard let id = space.focused, let host = hosts[id] else { return }
        host.content.goBack()
    }

    func setMode(_ m: Mode) {
        mode = mode == m ? .none : m
        if mode != .none && space.locked && mode != .moveAll { mode = .none }
    }

    /// The web window last focused, which the Control Center's This window row acts on.
    private(set) var lastWeb: UUID?

    /// Gives the last focused web window one of the common shapes.
    func shapeFocused(_ shape: WindowShape) {
        guard let id = lastWeb, let w = space.window(id), case .web = w.kind else { return }
        space.shape(id, shape, barHeight: Double(WindowHost.barHeight))
        if let n = space.window(id), let host = hosts[id] {
            host.bounds = CGRect(x: 0, y: 0, width: n.layoutWidth, height: n.layoutHeight)
        }
        changed()
    }

    /// The focused web window, for the Control Center's This window row.
    var focusedWeb: SpaceWindow? {
        guard let id = lastWeb, let w = space.window(id), case .web = w.kind else { return nil }
        return w
    }

    func setHeadTracking(_ on: Bool) {
        tracking.headTracking = on
        recentre()
        changed()
    }

    func setFollow(_ on: Bool) {
        tracking.trackingMode = on ? .smoothFollow : .bodyAnchor
        changed()
    }

    func setLocked(_ on: Bool) {
        space.locked = on
        if on { mode = .none }
        for (_, h) in hosts { h.locked = on }
        changed()
    }

    func recentre() {
        if tracked { Probe.shared.recentre() }
        lookYawDeg = 0
        lookPitchDeg = 0
        pointer = SpacePointer()
    }

    /// Turns the view so the focused window is in front when there is no head tracking.
    private func bringFocusedIntoView() {
        guard let id = space.focused, let w = space.window(id) else { return }
        if !tracked {
            lookYawDeg = w.yawDeg
            lookPitchDeg = w.pitchDeg
        }
        pointer.aim = SpaceAim(yawDeg: w.yawDeg, pitchDeg: w.pitchDeg)
    }

    // MARK: Windows

    @discardableResult
    func openWeb(_ url: String) -> UUID? {
        let host = URL(string: url)?.host ?? "Web"
        guard let w = space.open(.web(url: url), title: host, layoutWidth: SpaceWindows.webWidth, layoutHeight: SpaceWindows.webHeight, at: viewAim) else { return nil }
        makeHost(w)
        changed()
        return w.id
    }

    @discardableResult
    func openLauncher() -> UUID? {
        if let w = space.windows.first(where: { $0.kind == .launcher }) {
            if space.focused == w.id { close(w.id); return nil }
            space.focus(w.id)
            bringFocusedIntoView()
            changed(save: false)
            return w.id
        }
        guard let w = space.open(.launcher, title: "Apps", layoutWidth: SpaceWindows.launcherWidth, layoutHeight: SpaceWindows.launcherHeight + Double(WindowHost.barHeight),
                                 widthDeg: 34, at: viewAim) else { return nil }
        makeHost(w)
        changed()
        return w.id
    }

    @discardableResult
    func openControlCenter() -> UUID? {
        if let w = space.windows.first(where: { $0.kind == .controlCenter }) {
            if space.focused == w.id { close(w.id); return nil }
            space.focus(w.id)
            bringFocusedIntoView()
            changed(save: false)
            return w.id
        }
        let below = SpaceAim(yawDeg: viewAim.yawDeg, pitchDeg: viewAim.pitchDeg - 8)
        guard let w = space.open(.controlCenter, title: "Control Center", layoutWidth: SpaceWindows.controlWidth,
                                 layoutHeight: SpaceWindows.controlHeight + Double(WindowHost.barHeight), widthDeg: 28, at: below) else { return nil }
        makeHost(w)
        changed()
        return w.id
    }

    func close(_ id: UUID) {
        space.close(id)
        hosts[id]?.removeFromSuperview()
        hosts[id] = nil
        if controlPanel != nil, !space.windows.contains(where: { $0.kind == .controlCenter }) { controlPanel = nil }
        view.sync(hosts: hosts)
        changed()
    }

    func closeAll() {
        for w in space.windows where w.kind != .controlCenter { close(w.id) }
    }

    func arrange(_ layout: ArrangeLayout) {
        // Only web windows take part; the launcher and Control Center stay where they are.
        var webOnly = space
        webOnly.windows = space.windows.filter { if case .web = $0.kind { return true } else { return false } }
        webOnly.arrange(layout, centreYawDeg: viewAim.yawDeg)
        for w in webOnly.windows {
            if let i = space.index(w.id) { space.windows[i] = w }
        }
        // The launcher and Control Center move aside if the arrangement landed on them.
        for w in space.windows where w.kind == .launcher || w.kind == .controlCenter { space.makeRoom(for: w.id) }
        changed()
    }

    func savePreset() {
        var s = space
        s.windows = s.windows.filter { $0.kind != .controlCenter }
        let name = "Layout \(presets.count + 1)"
        presets.insert(SavedLayout(name: name, space: s), at: 0)
        if presets.count > 6 { presets.removeLast() }
        changed()
    }

    func applyPreset(_ index: Int) {
        guard presets.indices.contains(index) else { return }
        let p = presets[index]
        for w in space.windows where w.kind != .controlCenter { close(w.id) }
        for var w in p.space.windows {
            w.id = UUID()
            space.windows.append(w)
            makeHost(w)
        }
        space.focused = space.windows.last?.id
        changed()
    }

    private func makeHost(_ w: SpaceWindow) {
        let size = CGSize(width: w.layoutWidth, height: w.layoutHeight)
        let content: SpaceContent
        switch w.kind {
        case .web(let url):
            let web = WebContent(url: url, desktop: w.desktop)
            web.onChange = { [weak self, weak web] in
                guard let self = self, let web = web else { return }
                self.webChanged(w.id, web)
            }
            content = web
        case .launcher:
            content = LauncherPanel(sites: LauncherSite.defaults) { [weak self] url in _ = self?.openWeb(url) }
        case .controlCenter:
            let panel = ControlCenterPanel(controller: self)
            controlPanel = panel
            content = panel
        }
        let host = WindowHost(id: w.id, size: size, content: content, showsBack: { if case .web = w.kind { return true } else { return false } }())
        host.setTitle(w.title)
        host.locked = space.locked
        host.onAction = { [weak self] action in self?.windowKey(w.id, action) }
        hosts[w.id] = host
        view.sync(hosts: hosts)
    }

    private func webChanged(_ id: UUID, _ web: WebContent) {
        guard let i = space.index(id) else { return }
        hosts[id]?.setTitle(web.title)
        space.windows[i].title = web.title
        if let u = web.currentURL { space.windows[i].kind = .web(url: u) }
        changed()
    }

    private func windowKey(_ id: UUID, _ action: String) {
        space.focus(id)
        guard let host = hosts[id] else { return }
        switch action {
        case "back": host.content.goBack()
        case "reload": host.content.reload()
        case "wide":
            if let web = host.content as? WebContent, let i = space.index(id) {
                space.windows[i].desktop.toggle()
                web.setDesktop(space.windows[i].desktop)
            }
        case "snap": space.snap(id)
        case "close": close(id); return
        default: break
        }
        changed()
    }

    /// Focuses a window without a click (the self-test).
    func focusForTest(_ id: UUID) {
        space.focus(id)
        changed(save: false)
    }

    /// The host of a window, for the self-test.
    func host(_ id: UUID) -> WindowHost? { hosts[id] }

    /// Points the pointer at [u], [v] on a window (the self-test).
    func aim(at id: UUID, u: Double, v: Double) {
        guard let p = space.point(id, u: u, v: v) else { return }
        pointer.aim = SpaceAim.of(p)
        hover = space.hit(pointer.aim)
    }

    // MARK: Saving

    private struct Saved: Codable {
        var space: SpaceWindows
        var presets: [SavedLayout]
        var tracking: SpaceSettings?
    }

    private static let key = "space.v1"

    private func changed(save: Bool = true) {
        if let f = space.focused, let w = space.window(f), case .web = w.kind { lastWeb = f }
        controlPanel?.refresh()
        guard save else { return }
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    func saveNow() {
        var s = space
        s.windows = s.windows.filter { $0.kind != .controlCenter }
        if let data = try? JSONEncoder().encode(Saved(space: s, presets: presets, tracking: tracking)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        if UserDefaults.standard.bool(forKey: "PXRFreshSpace") { return }
        guard let data = UserDefaults.standard.data(forKey: Self.key), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        space = s.space
        presets = s.presets
        if let t = s.tracking { tracking = t }
    }
}
