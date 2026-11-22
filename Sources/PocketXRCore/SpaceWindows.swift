import Foundation

// The iOS Space's windows: each one placed on its own (as on Android, where every window has its own size and
// distance), moved, resized, pushed, pulled, snapped and arranged, and found under the pointer. Pure arithmetic, so
// Checks/WindowChecks.swift covers it without a screen. Written for Pocket XR for iOS; not used by the Mac app.

/// What a window shows.
public enum SpaceWindowKind: Codable, Equatable, Sendable {
    /// A web page.
    case web(url: String)
    /// Pocket XR's app launcher.
    case launcher
    /// Pocket XR's Control Center.
    case controlCenter
}

/// One window in the Space.
public struct SpaceWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: SpaceWindowKind
    public var title: String
    /// Where it sits. The aspect always follows [layoutSize].
    public var yawDeg: Double
    public var pitchDeg: Double
    public var widthDeg: Double
    public var distance: Double
    public var curve: Double
    /// The size its content lays out at, in points (CSS pixels for a web page).
    public var layoutWidth: Double
    public var layoutHeight: Double
    /// A web page asked for as a desktop site (Wide view's nearest match on iOS).
    public var desktop: Bool

    public init(id: UUID = UUID(), kind: SpaceWindowKind, title: String, yawDeg: Double = 0, pitchDeg: Double = 0,
                widthDeg: Double = SpaceLayout.defaultWidthDeg, distance: Double = SpaceLayout.defaultDistance,
                curve: Double = 0, layoutWidth: Double, layoutHeight: Double, desktop: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.yawDeg = yawDeg
        self.pitchDeg = pitchDeg
        self.widthDeg = widthDeg
        self.distance = distance
        self.curve = curve
        self.layoutWidth = layoutWidth
        self.layoutHeight = layoutHeight
        self.desktop = desktop
    }

    public var aspect: Double { layoutWidth / max(layoutHeight, 1) }

    public var placement: PanelPlacement {
        PanelPlacement(yawDeg: yawDeg, pitchDeg: pitchDeg, widthDeg: widthDeg, aspect: aspect, distance: distance, curve: curve)
    }

    public var heightDeg: Double { SpaceLayout.heightDeg(widthDeg: widthDeg, aspect: aspect) }
}

/// A point in the Space as seen from the head: yaw (left positive) and pitch (up positive), degrees.
public struct SpaceAim: Codable, Equatable, Sendable {
    public var yawDeg: Double
    public var pitchDeg: Double

    public init(yawDeg: Double, pitchDeg: Double) {
        self.yawDeg = yawDeg
        self.pitchDeg = pitchDeg
    }

    /// The unit direction, in the Space's frame (x right, y up, -z ahead).
    public var direction: SIMD3<Double> {
        let y = yawDeg * .pi / 180, p = pitchDeg * .pi / 180
        return SIMD3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p))
    }

    /// The aim along a direction.
    public static func of(_ d: SIMD3<Double>) -> SpaceAim {
        let len = max((d.x * d.x + d.y * d.y + d.z * d.z).squareRoot(), 1e-12)
        let u = d / len
        return SpaceAim(yawDeg: atan2(-u.x, -u.z) * 180 / .pi, pitchDeg: asin(max(-1, min(1, u.y))) * 180 / .pi)
    }

    /// Angles wrapped into -180...180.
    public static func wrap(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// Where the pointer meets a window: the window, and u, v 0...1 from its top left.
public struct SpaceHit: Equatable, Sendable {
    public var id: UUID
    public var u: Double
    public var v: Double
    public var distance: Double
}

public struct SpaceWindows: Codable, Equatable, Sendable {
    /// Windows' web layout sizes, points: a landscape tablet-like page by default.
    public static let webWidth = 1280.0
    public static let webHeight = 800.0
    public static let launcherWidth = 960.0
    public static let launcherHeight = 600.0
    public static let controlWidth = 760.0
    public static let controlHeight = 520.0
    /// Two windows' facing edges closer than this snap together, degrees.
    public static let snapDeg = 3.0
    /// Pushing and pulling change the distance by this factor a step.
    public static let pushStep = 1.15
    /// The most windows open at once (each web window is a whole browser page in memory).
    public static let maxWindows = 8

    public var windows: [SpaceWindow] = []
    public var focused: UUID?
    /// Lock screens: nothing moves or resizes; clicks, scrolls and typing still reach the windows.
    public var locked = false

    public init() {}

    public func index(_ id: UUID) -> Int? { windows.firstIndex { $0.id == id } }

    public func window(_ id: UUID) -> SpaceWindow? { index(id).map { windows[$0] } }

    /// A new window, put where it can be seen: at [aim] if nothing is there, else beside the window there, on the
    /// side with more room. Becomes the focused one. Nil when [maxWindows] are open.
    @discardableResult
    public mutating func open(_ kind: SpaceWindowKind, title: String, layoutWidth: Double, layoutHeight: Double,
                              widthDeg: Double = SpaceLayout.defaultWidthDeg, at aim: SpaceAim) -> SpaceWindow? {
        guard windows.count < Self.maxWindows else { return nil }
        var w = SpaceWindow(kind: kind, title: title, yawDeg: aim.yawDeg, pitchDeg: clampPitch(aim.pitchDeg), widthDeg: widthDeg,
                            layoutWidth: layoutWidth, layoutHeight: layoutHeight)
        var tries = 0
        while let other = overlapping(w), tries < Self.maxWindows {
            let right = other.yawDeg - (other.widthDeg + w.widthDeg) / 2 - SpaceLayout.gapDeg
            let left = other.yawDeg + (other.widthDeg + w.widthDeg) / 2 + SpaceLayout.gapDeg
            w.yawDeg = abs(SpaceAim.wrap(right - aim.yawDeg)) <= abs(SpaceAim.wrap(left - aim.yawDeg)) ? right : left
            tries += 1
        }
        windows.append(w)
        focused = w.id
        return w
    }

    /// The first other window whose angular box overlaps [w]'s.
    public func overlapping(_ w: SpaceWindow) -> SpaceWindow? {
        windows.first { o in
            o.id != w.id
                && abs(SpaceAim.wrap(o.yawDeg - w.yawDeg)) < (o.widthDeg + w.widthDeg) / 2
                && abs(o.pitchDeg - w.pitchDeg) < (o.heightDeg + w.heightDeg) / 2
        }
    }

    public mutating func close(_ id: UUID) {
        windows.removeAll { $0.id == id }
        if focused == id { focused = windows.last?.id }
    }

    public mutating func focus(_ id: UUID?) {
        guard let id = id, index(id) != nil else { return }
        focused = id
    }

    /// The next (or previous) window by position left to right, from the focused one.
    public mutating func focusNext(forward: Bool) {
        guard !windows.isEmpty else { return }
        // Left to right is falling yaw (yaw is left positive).
        let order = windows.sorted { $0.yawDeg > $1.yawDeg }.map { $0.id }
        guard let f = focused, let at = order.firstIndex(of: f) else { focused = order.first; return }
        let next = (at + (forward ? 1 : -1) + order.count) % order.count
        focused = order[next]
    }

    func clampPitch(_ p: Double) -> Double { min(max(p, -SpaceLayout.maxPitchDeg), SpaceLayout.maxPitchDeg) }

    /// Moves a window by [dYaw], [dPitch] degrees. Not while locked.
    public mutating func move(_ id: UUID, dYawDeg: Double, dPitchDeg: Double) {
        guard !locked, let i = index(id) else { return }
        windows[i].yawDeg = SpaceAim.wrap(windows[i].yawDeg + dYawDeg)
        windows[i].pitchDeg = clampPitch(windows[i].pitchDeg + dPitchDeg)
    }

    /// Makes a window [dWidthDeg] wider (narrower when negative), keeping its middle. Not while locked.
    public mutating func resize(_ id: UUID, dWidthDeg: Double) {
        guard !locked, let i = index(id) else { return }
        windows[i].widthDeg = min(max(windows[i].widthDeg + dWidthDeg, SpaceLayout.minWidthDeg), SpaceLayout.maxWidthDeg)
    }

    /// Pushes a window further ([steps] > 0) or pulls it closer, keeping its angular size, so it looks the same
    /// size but sits at another depth. Not while locked.
    public mutating func push(_ id: UUID, steps: Double) {
        guard !locked, let i = index(id) else { return }
        let d = windows[i].distance * pow(Self.pushStep, steps)
        windows[i].distance = min(max(d, SpaceLayout.minDistance), SpaceLayout.maxDistance)
    }

    /// Bends a window by [dCurve] (0 flat up to PanelCurve.maxCurve). Not while locked.
    public mutating func bend(_ id: UUID, dCurve: Double) {
        guard !locked, let i = index(id) else { return }
        windows[i].curve = min(max(windows[i].curve + dCurve, 0), PanelCurve.maxCurve)
    }

    /// Changes a window's layout size (its shape), keeping its width in degrees.
    public mutating func reshape(_ id: UUID, layoutWidth: Double, layoutHeight: Double) {
        guard !locked, let i = index(id) else { return }
        windows[i].layoutWidth = max(layoutWidth, 200)
        windows[i].layoutHeight = max(layoutHeight, 200)
    }

    /// Snaps a window next to a neighbour whose facing edge is within [snapDeg], one gap apart and at the same
    /// pitch. Returns whether it moved.
    @discardableResult
    public mutating func snap(_ id: UUID) -> Bool {
        guard !locked, let i = index(id) else { return false }
        let w = windows[i]
        var best: (yaw: Double, pitch: Double, miss: Double)?
        for o in windows where o.id != id {
            guard abs(o.pitchDeg - w.pitchDeg) < (o.heightDeg + w.heightDeg) / 2 else { continue }
            let half = (o.widthDeg + w.widthDeg) / 2 + SpaceLayout.gapDeg
            for target in [o.yawDeg + half, o.yawDeg - half] {
                let miss = abs(SpaceAim.wrap(target - w.yawDeg))
                if miss <= Self.snapDeg + SpaceLayout.gapDeg, miss < (best?.miss ?? .infinity) {
                    best = (yaw: SpaceAim.wrap(target), pitch: o.pitchDeg, miss: miss)
                }
            }
        }
        guard let b = best else { return false }
        windows[i].yawDeg = b.yaw
        windows[i].pitchDeg = b.pitch
        return true
    }

    /// Moves every window together (Adjust all). Not while locked.
    public mutating func moveAll(dYawDeg: Double, dPitchDeg: Double) {
        guard !locked else { return }
        for i in windows.indices {
            windows[i].yawDeg = SpaceAim.wrap(windows[i].yawDeg + dYawDeg)
            windows[i].pitchDeg = clampPitch(windows[i].pitchDeg + dPitchDeg)
        }
    }

    /// Pushes or pulls every window together. Not while locked.
    public mutating func pushAll(steps: Double) {
        for w in windows { push(w.id, steps: steps) }
    }

    /// Resizes every window together. Not while locked.
    public mutating func resizeAll(dWidthDeg: Double) {
        for w in windows { resize(w.id, dWidthDeg: dWidthDeg) }
    }

    /// Lays the windows out with one of the premade arrangements, centred on [centreYawDeg]. The first three
    /// windows (left to right as they are) take the layout's places; any more go in a row below. Not while locked.
    public mutating func arrange(_ layout: ArrangeLayout, centreYawDeg: Double = 0, widthDeg: Double = SpaceLayout.defaultWidthDeg,
                                 distance: Double = SpaceLayout.defaultDistance) {
        guard !locked, !windows.isEmpty else { return }
        let order = windows.sorted { $0.yawDeg > $1.yawDeg }.map { $0.id }
        let main = Array(order.prefix(3))
        let placed = SpaceLayout.arrange(layout: layout, aspects: main.map { window($0)!.aspect }, widthDeg: widthDeg,
                                         distance: distance, curve: 0)
        for (k, id) in main.enumerated() {
            guard let i = index(id), k < placed.count else { continue }
            windows[i].yawDeg = SpaceAim.wrap(placed[k].yawDeg + centreYawDeg)
            windows[i].pitchDeg = placed[k].pitchDeg
            windows[i].widthDeg = placed[k].widthDeg
            windows[i].distance = placed[k].distance
            windows[i].curve = 0
        }
        let rest = Array(order.dropFirst(3))
        if !rest.isEmpty {
            let row = SpaceLayout.row(aspects: rest.map { window($0)!.aspect }, widthDeg: widthDeg * 0.6, distance: distance)
            for (k, id) in rest.enumerated() {
                guard let i = index(id) else { continue }
                windows[i].yawDeg = SpaceAim.wrap(row[k].yawDeg + centreYawDeg)
                windows[i].pitchDeg = -SpaceLayout.maxPitchDeg * 0.8
                windows[i].widthDeg = row[k].widthDeg
                windows[i].distance = distance
                windows[i].curve = 0
            }
        }
    }

    /// The window under [aim] and where on it, nearest first where windows overlap.
    public func hit(_ aim: SpaceAim) -> SpaceHit? {
        let d = aim.direction
        var best: SpaceHit?
        for w in windows {
            guard let h = PanelCurve.intersect(w.placement, direction: d), abs(h.x) <= 0.5, abs(h.y) <= 0.5 else { continue }
            if h.t < (best?.distance ?? .infinity) {
                best = SpaceHit(id: w.id, u: h.x + 0.5, v: 0.5 - h.y, distance: h.t)
            }
        }
        return best
    }

    /// The point in the Space's frame at [u], [v] on a window (0...1 from its top left), for drawing the pointer.
    public func point(_ id: UUID, u: Double, v: Double) -> SIMD3<Double>? {
        guard let w = window(id) else { return nil }
        return PanelCurve.point(w.placement, x: u - 0.5, y: 0.5 - v)
    }
}

/// The pointer: an aim in the Space, moved by the trackpad, the Spatial Mouse or a mouse, kept within the view.
public struct SpacePointer: Codable, Equatable, Sendable {
    /// Trackpad points per degree at speed 1.
    public static let pointsPerDeg = 14.0
    /// The pointer stays this far inside the view's edge, degrees.
    public static let edgeDeg = 2.0

    public var aim = SpaceAim(yawDeg: 0, pitchDeg: 0)

    public init() {}

    /// Moves by a trackpad drag of [dx], [dy] points (right and down positive) at [speed].
    public mutating func drag(dx: Double, dy: Double, speed: Double = 1) {
        aim.yawDeg = SpaceAim.wrap(aim.yawDeg - dx * speed / Self.pointsPerDeg)
        aim.pitchDeg = min(max(aim.pitchDeg - dy * speed / Self.pointsPerDeg, -80), 80)
    }

    /// Keeps the pointer within a view centred on [view] that is [halfWidthDeg] by [halfHeightDeg] each way.
    /// Returns how far the pointer was past the edge (yaw, pitch degrees, 0 when inside), which a view with no head
    /// tracking uses to pan.
    @discardableResult
    public mutating func keep(inside view: SpaceAim, halfWidthDeg: Double, halfHeightDeg: Double) -> (yawDeg: Double, pitchDeg: Double) {
        let hw = max(halfWidthDeg - Self.edgeDeg, 1), hh = max(halfHeightDeg - Self.edgeDeg, 1)
        let dy = SpaceAim.wrap(aim.yawDeg - view.yawDeg)
        let dp = aim.pitchDeg - view.pitchDeg
        let cy = min(max(dy, -hw), hw), cp = min(max(dp, -hh), hh)
        aim.yawDeg = SpaceAim.wrap(view.yawDeg + cy)
        aim.pitchDeg = view.pitchDeg + cp
        return (yawDeg: dy - cy, pitchDeg: dp - cp)
    }
}
