import Foundation
import PocketXRCore

/// The glasses' own settings over their USB network (the Aura and the One family), with PocketXRCore's
/// SettingsControl, ported from the Steam Deck and used by the Mac: for head tracking, Spatial Anchor and Ultrawide
/// off and follow mode; for Steady mode, Ultrawide on and the glasses' Spatial Anchor, so the glasses hold one wide
/// canvas themselves.
///
/// iOS cannot read which glasses are plugged in (no USB access), so the model follows the sensor axes chosen in the
/// probe screen: the Aura, or the One family. Whether iOS brings up the USB network at all is untested
/// (docs/STATUS.md); without it this never starts, and Steady mode is drawn by the app alone, for glasses that hold
/// the picture themselves (the One series in Anchor mode, the VITURE Beast).
@MainActor
final class GlassesControl {
    static let shared = GlassesControl()

    private var control: SettingsControl?
    private(set) var state = SettingsControl.State()
    var onState: ((SettingsControl.State) -> Void)?

    /// Starts once the glasses' sensor stream is up over their USB network (not the Simulator's test host).
    func startIfLinked(one: Bool) {
        guard control == nil, UserDefaults.standard.string(forKey: "PXRProbeHost") == nil else { return }
        let glasses = one ? Glasses(name: "XREAL One", family: .one, vendor: Glasses.xreal, product: 0x0437)
                          : Glasses(name: "XREAL Aura", family: .aura, vendor: Glasses.xreal, product: 0x043A)
        let c = SettingsControl(glasses: glasses) { s in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GlassesControl.shared.state = s
                    GlassesControl.shared.onState?(s)
                }
            }
        }
        // One picture for both eyes (docs/STATUS.md), so the glasses stay in 2D; PC VR's two eyes want 3D.
        c.want3D = { PcVrSession.wants3D }
        control = c
        c.start()
        AppLog.line("glasses: control link started for the \(glasses.name)")
    }

    /// Steady mode in the glasses (Ultrawide and their Spatial Anchor). Nothing is sent without the control link.
    func setSteady(_ on: Bool) { control?.setSteady(on) }

    var linked: Bool { control != nil && state.link }

    /// Puts the glasses' settings right again (after PC VR asks for 3D or ends).
    func apply() { control?.apply() }
}
