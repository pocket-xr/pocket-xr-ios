import SwiftUI
import UIKit

/// For CI in the Simulator: `-PXRSelfTest <seconds>` waits that long, then writes Documents/selftest.json (the same
/// report as Share report) and PNGs of the glasses picture at 1920x1080 and 3840x1080, and prints PXR-SELFTEST-DONE.
/// Run with `-PXRProbeHost 127.0.0.1` and Tools/FakeGlasses on the Mac to exercise the head tracking path.
enum SelfTest {
    static func runIfAsked() {
        let seconds = UserDefaults.standard.double(forKey: "PXRSelfTest")
        guard seconds > 0 else { return }
        Log.line("selftest: will report in \(seconds) s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { finish() }
        }
    }

    @MainActor
    private static func finish() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let model = AppModel.shared
        let report = Report.make(display: model.display, probe: Probe.shared.snapshot)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(report).write(to: docs.appendingPathComponent("selftest.json"))
            for (w, h) in [(1920.0, 1080.0), (3840.0, 1080.0)] {
                // GlassesPicture directly: ImageRenderer does not run GeometryReader and TimelineView like a screen.
                let head = Probe.shared.view()
                let sbs = w / h > 3
                let eye = CGSize(width: sbs ? w / 2 : w, height: h)
                let view = HStack(spacing: 0) {
                    GlassesPicture(size: eye, head: head, probe: report.probe, eye: sbs ? "left" : nil)
                    if sbs { GlassesPicture(size: eye, head: head, probe: report.probe, eye: "right") }
                }
                .frame(width: w, height: h)
                .background(Color.black)
                let r = ImageRenderer(content: view)
                r.scale = 1
                if let img = r.uiImage, let png = img.pngData() {
                    try png.write(to: docs.appendingPathComponent("glasses-\(Int(w))x\(Int(h)).png"))
                }
            }
            Log.line("selftest: written to \(docs.path)")
        } catch {
            Log.line("selftest: could not write: \(error)")
        }
        print("PXR-SELFTEST-DONE \(docs.path)")
    }
}
