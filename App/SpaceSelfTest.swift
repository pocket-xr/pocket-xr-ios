import PocketXRCore
import UIKit
import WebKit

/// For CI in the Simulator: `-PXRDemo YES` (with `-PXRFreshSpace YES`) opens two test pages beside the launcher,
/// then drives the Space the way the trackpad does: aims the pointer at the page's button and clicks, clicks into a
/// text field and types, scrolls a list, opens a site from the launcher, and checks that Lock screens stops a move.
/// Each result is read back from the page itself, and everything goes to Documents/space.json.
@MainActor
enum SpaceSelfTest {
    struct Results: Codable {
        var windowsAtStart = 0
        var buttonText = ""
        var fieldValue = ""
        var listScrollTop = 0.0
        var windowsAfterLauncherClick = 0
        var lockedMoveBlocked = false
        /// After clicking into the web field, the key catcher holds the focus and no keyboard is up.
        var keyboardStayedDown = false
        var shapedToPhone = false
        var controlCenterLocked = false
        var closedByWindowKey = false
        var sideBySideOn = false
        var arrangedWithoutOverlap = false
        var errors = [String]()
        var done = false
    }

    static func runIfAsked() {
        guard UserDefaults.standard.bool(forKey: "PXRDemo") else { return }
        Task { @MainActor in await run() }
    }

    private static func wait(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1e9))
    }

    private static func js(_ web: WKWebView, _ script: String) async -> Any? {
        await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            web.evaluateJavaScript(script) { value, _ in c.resume(returning: value) }
        }
    }

    /// Aims at an element's middle on a web window and clicks, as a trackpad tap would.
    private static func clickElement(_ c: SpaceController, _ id: UUID, _ web: WKWebView, _ element: String, _ r: inout Results) async {
        guard let host = c.host(id) else { r.errors.append("no host"); return }
        var xy: [Double]?
        for _ in 0..<10 {
            let raw = await js(web, "typeof __pxrRect === 'function' ? __pxrRect('\(element)') : 'not ready'")
            if let a = raw as? [NSNumber], a.count == 2 { xy = a.map { $0.doubleValue }; break }
            AppLog.line("demo: rect for \(element): \(String(describing: raw))")
            await wait(0.3)
        }
        guard let xy = xy else { r.errors.append("no rect for \(element)"); return }
        c.aim(at: id, u: xy[0] / Double(host.bounds.width), v: xy[1] / Double(host.bounds.height))
        if c.hover?.id != id { r.errors.append("pointer on another window for \(element)") }
        c.click()
        await wait(0.6)
    }

    static func run() async {
        let c = SpaceController.shared
        var r = Results()
        AppLog.line("demo: starting")
        await wait(1.5)
        guard let a = c.openWeb(TestPage.url), let b = c.openWeb(TestPage.url) else {
            r.errors.append("could not open windows")
            write(r)
            return
        }
        c.arrange(.row)
        r.windowsAtStart = c.space.windows.count
        let webOnly = c.space.windows.filter { $0.id == a || $0.id == b }
        r.arrangedWithoutOverlap = !webOnly.isEmpty && webOnly.allSatisfy { w in !webOnly.contains { o in
            o.id != w.id && abs(SpaceAim.wrap(o.yawDeg - w.yawDeg)) < (o.widthDeg + w.widthDeg) / 2 } }
        await wait(3)
        guard let web = (c.host(a)?.content as? WebContent)?.web else {
            r.errors.append("no web view")
            write(r)
            return
        }

        // Click the button.
        await clickElement(c, a, web, "btn", &r)
        r.buttonText = await js(web, "document.getElementById('out').textContent") as? String ?? ""

        // Click into the field and type.
        await clickElement(c, a, web, "field", &r)
        await wait(0.5)
        if let k = KeyCatcher.current {
            r.keyboardStayedDown = k.isFirstResponder && !k.showsKeyboard
        }
        c.type("hellp")
        await wait(0.3)
        c.key("Backspace")
        c.type("o")
        await wait(0.5)
        r.fieldValue = await js(web, "document.getElementById('field').value") as? String ?? ""

        // Scroll the list with two fingers' worth of movement.
        await clickElement(c, a, web, "list", &r)
        c.scroll(dx: 0, dy: 400)
        await wait(0.5)
        r.listScrollTop = await js(web, "document.getElementById('list').scrollTop") as? Double ?? 0

        // Open a site from the launcher: aim at the Test page tile and click.
        if let lid = c.space.windows.first(where: { $0.kind == .launcher })?.id, let host = c.host(lid),
           let panel = host.content as? LauncherPanel, let tile = panel.tiles.last {
            let before = c.space.windows.count
            let mid = tile.convert(CGPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: host)
            c.aim(at: lid, u: Double(mid.x / host.bounds.width), v: Double(mid.y / host.bounds.height))
            if c.hover?.id != lid { r.errors.append("pointer not on the launcher") }
            AppLog.line("demo: launcher tile at \(mid) of \(host.bounds.size)")
            c.click()
            await wait(0.5)
            r.windowsAfterLauncherClick = c.space.windows.count
            if r.windowsAfterLauncherClick != before + 1 { r.errors.append("launcher click opened \(r.windowsAfterLauncherClick - before)") }
        } else {
            r.errors.append("no launcher")
        }

        // Lock screens: a move does nothing.
        c.setLocked(true)
        let yaw = c.space.window(a)?.yawDeg
        c.setMode(.move)
        c.pointerMove(dx: 200, dy: 0)
        r.lockedMoveBlocked = c.space.window(a)?.yawDeg == yaw
        c.setLocked(false)
        c.recentre()

        // Control Center: open it, click "Lock screens" and a shape, read the results back.
        if let cid = c.openControlCenter(), let host = c.host(cid), let panel = host.content as? ControlCenterPanel {
            c.focusForTest(a)
            panel.refresh()
            host.layoutIfNeeded()
            let lock = panel.lockSwitchForTest
            let lockMid = lock.convert(CGPoint(x: lock.bounds.midX, y: lock.bounds.midY), to: host)
            c.aim(at: cid, u: Double(lockMid.x / host.bounds.width), v: Double(lockMid.y / host.bounds.height))
            c.click()
            r.controlCenterLocked = c.space.locked
            c.setLocked(false)
            c.focusForTest(a)
            panel.refresh()
            host.layoutIfNeeded()
            if let phone = panel.shapeButtonForTest(.phone) {
                let mid = phone.convert(CGPoint(x: phone.bounds.midX, y: phone.bounds.midY), to: host)
                c.aim(at: cid, u: Double(mid.x / host.bounds.width), v: Double(mid.y / host.bounds.height))
                c.focusForTest(a)
                // A click focuses the window it lands on; the shape keys act on the web window focused before, so
                // the Control Center keeps the last web window as "This window".
                c.click()
                if let w = c.space.window(a) {
                    r.shapedToPhone = WindowShape.current(width: w.layoutWidth, height: w.layoutHeight - Double(WindowHost.barHeight)) == .phone
                        && c.host(a)?.bounds.width == CGFloat(w.layoutWidth)
                }
                if !r.shapedToPhone { r.errors.append("shape did not reach the window") }
            } else {
                r.errors.append("no shape button")
            }
        } else {
            r.errors.append("no Control Center")
        }

        // A window key: Close on the second test page's bar.
        if let host = c.host(b) {
            let closeX = host.bounds.width - 40, barY = host.bounds.height - WindowHost.barHeight / 2
            c.aim(at: b, u: Double(closeX / host.bounds.width), v: Double(barY / host.bounds.height))
            if c.hover?.id != b { r.errors.append("pointer not on the second page's bar") }
            c.click()
            r.closedByWindowKey = c.space.window(b) == nil
        }

        // Side by side, as for glasses in 3D: left on for the screenshot CI takes afterwards.
        c.view.forceSideBySide = true
        c.view.layoutIfNeeded()
        r.sideBySideOn = c.view.sideBySide

        r.done = true
        AppLog.line("demo: done, \(r.errors.isEmpty ? "no errors" : r.errors.joined(separator: "; "))")
        write(r)
    }

    private static func write(_ r: Results) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(r).write(to: docs.appendingPathComponent("space.json"))
    }
}
