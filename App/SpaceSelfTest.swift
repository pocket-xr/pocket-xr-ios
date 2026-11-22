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
        c.type("hello")
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
