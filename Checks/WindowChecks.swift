import Foundation

// The iOS Space's windows and pointer (Sources/PocketXRCore/SpaceWindows.swift).

func windowChecks() {
    // Aims and directions agree with the panels' own frame: yaw left positive, -z ahead.
    let ahead = SpaceAim(yawDeg: 0, pitchDeg: 0).direction
    check(near(ahead.z, -1) && near(ahead.x, 0), "straight ahead is -z")
    let left = SpaceAim(yawDeg: 90, pitchDeg: 0).direction
    check(near(left.x, -1, 1e-9), "yaw 90 is to the left (-x)")
    let back = SpaceAim.of(SpaceAim(yawDeg: 33, pitchDeg: -12).direction)
    check(near(back.yawDeg, 33, 1e-9) && near(back.pitchDeg, -12, 1e-9), "aim round trip")
    let panelCentre = PanelCurve.point(PanelPlacement(yawDeg: 25, pitchDeg: 10, widthDeg: 40, aspect: 1.6, distance: 1.4), x: 0, y: 0)
    let centreAim = SpaceAim.of(panelCentre)
    check(near(centreAim.yawDeg, 25, 1e-9) && near(centreAim.pitchDeg, 10, 1e-9), "a panel's centre is at its yaw and pitch")
    check(near(SpaceAim.wrap(190), -170) && near(SpaceAim.wrap(-190), 170), "wrap")

    // Opening: the first window goes where you look; the next goes beside it, not on top.
    var s = SpaceWindows()
    let a = s.open(.web(url: "https://example.com"), title: "A", layoutWidth: 1280, layoutHeight: 800, at: SpaceAim(yawDeg: 0, pitchDeg: 0))!
    check(near(a.yawDeg, 0) && s.focused == a.id, "first window at the aim and focused")
    let b = s.open(.launcher, title: "B", layoutWidth: 960, layoutHeight: 600, at: SpaceAim(yawDeg: 2, pitchDeg: 0))!
    check(s.overlapping(b) == nil, "second window does not overlap the first")
    check(abs(b.yawDeg) > 20, "second window moved beside the first")
    check(s.focused == b.id, "the new window is focused")

    // The pointer finds the window it is on, with u, v from the top left.
    let hitA = s.hit(SpaceAim(yawDeg: 0, pitchDeg: 0))
    check(hitA?.id == a.id && near(hitA?.u ?? -1, 0.5, 1e-9) && near(hitA?.v ?? -1, 0.5, 1e-9), "hit in the middle of A")
    let upperLeft = s.hit(SpaceAim(yawDeg: 10, pitchDeg: 5))
    check(upperLeft?.id == a.id && (upperLeft?.u ?? 1) < 0.5 && (upperLeft?.v ?? 1) < 0.5, "up and left of the middle is u, v < 0.5")
    check(s.hit(SpaceAim(yawDeg: 180, pitchDeg: 0)) == nil, "nothing behind")
    if let p = s.point(a.id, u: 0.25, v: 0.75) {
        let h = s.hit(SpaceAim.of(p))
        check(h?.id == a.id && near(h?.u ?? 0, 0.25, 1e-9) && near(h?.v ?? 0, 0.75, 1e-9), "point and hit agree")
    } else {
        check(false, "point on A")
    }

    // Moving, resizing, pushing, bending; nothing while locked.
    s.move(a.id, dYawDeg: 5, dPitchDeg: 100)
    check(near(s.window(a.id)!.yawDeg, 5) && near(s.window(a.id)!.pitchDeg, SpaceLayout.maxPitchDeg), "move, pitch clamped")
    s.resize(a.id, dWidthDeg: -100)
    check(near(s.window(a.id)!.widthDeg, SpaceLayout.minWidthDeg), "resize clamped to the minimum")
    let d0 = s.window(a.id)!.distance
    s.push(a.id, steps: 1)
    check(near(s.window(a.id)!.distance, d0 * SpaceWindows.pushStep), "push one step")
    s.push(a.id, steps: -50)
    check(near(s.window(a.id)!.distance, SpaceLayout.minDistance), "pull clamped")
    s.bend(a.id, dCurve: 10)
    check(near(s.window(a.id)!.curve, PanelCurve.maxCurve), "bend clamped")
    s.locked = true
    let before = s
    s.move(a.id, dYawDeg: 10, dPitchDeg: 0)
    s.resize(a.id, dWidthDeg: 10)
    s.push(a.id, steps: 2)
    s.moveAll(dYawDeg: 3, dPitchDeg: 3)
    s.arrange(.row)
    check(s == before, "locked: nothing moves or resizes")
    s.locked = false

    // Snapping: a window dropped near another's edge lines up one gap away at the same pitch.
    var t = SpaceWindows()
    let l = t.open(.web(url: "x"), title: "L", layoutWidth: 1280, layoutHeight: 800, at: SpaceAim(yawDeg: 0, pitchDeg: 0))!
    var r = t.open(.web(url: "y"), title: "R", layoutWidth: 1280, layoutHeight: 800, at: SpaceAim(yawDeg: -60, pitchDeg: 0))!
    t.move(r.id, dYawDeg: 60 - 40 - SpaceLayout.gapDeg - 1.5, dPitchDeg: 2) // its left edge 1.5 deg past where it snaps
    check(t.snap(r.id), "snaps when close")
    r = t.window(r.id)!
    check(near(SpaceAim.wrap(l.yawDeg - r.yawDeg), 40 + SpaceLayout.gapDeg, 1e-9) && near(r.pitchDeg, 0), "snapped one gap to the right, level")
    t.move(r.id, dYawDeg: -20, dPitchDeg: 0)
    check(!t.snap(r.id), "no snap when far")

    // Arranging: three across, centred.
    var u = SpaceWindows()
    for k in 0..<3 {
        u.open(.web(url: "\(k)"), title: "\(k)", layoutWidth: 1280, layoutHeight: 800, at: SpaceAim(yawDeg: Double(k) * 80, pitchDeg: 0))
    }
    u.arrange(.row)
    let yaws = u.windows.map { $0.yawDeg }.sorted()
    check(yaws.count == 3 && near(yaws[1], 0, 1e-9) && near(yaws[0], -yaws[2], 1e-9), "row arrangement is centred")
    check(u.windows.allSatisfy { u.overlapping($0) == nil }, "arranged windows do not overlap")

    // Focus order follows the windows left to right (yaw falling), wrapping.
    var f = u
    let leftmost = f.windows.max { $0.yawDeg < $1.yawDeg }!.id
    let rightmost = f.windows.min { $0.yawDeg < $1.yawDeg }!.id
    f.focused = rightmost
    f.focusNext(forward: true)
    check(f.focused == leftmost, "focus wraps from the right end to the left")

    // Closing moves the focus to another window.
    f.close(f.focused!)
    check(f.windows.count == 2 && f.focused != nil, "close keeps a focus")

    // At most maxWindows.
    var m = SpaceWindows()
    for k in 0..<(SpaceWindows.maxWindows + 2) {
        m.open(.web(url: "\(k)"), title: "\(k)", layoutWidth: 800, layoutHeight: 600, widthDeg: 20, at: SpaceAim(yawDeg: 0, pitchDeg: 0))
    }
    check(m.windows.count == SpaceWindows.maxWindows, "no more than maxWindows")

    // Codable round trip (saved layouts).
    let data = try? JSONEncoder().encode(u)
    let again = data.flatMap { try? JSONDecoder().decode(SpaceWindows.self, from: $0) }
    check(again == u, "windows survive a save and load")

    // The pointer: drags move it, the view keeps it inside and says how far it went past.
    var p = SpacePointer()
    p.drag(dx: SpacePointer.pointsPerDeg * 10, dy: SpacePointer.pointsPerDeg * -5)
    check(near(p.aim.yawDeg, -10) && near(p.aim.pitchDeg, 5), "drag right and up moves right and up")
    let over = p.keep(inside: SpaceAim(yawDeg: 0, pitchDeg: 0), halfWidthDeg: 6, halfHeightDeg: 20)
    check(near(p.aim.yawDeg, -4) && near(over.yawDeg, -6), "kept inside, overshoot reported")
}
