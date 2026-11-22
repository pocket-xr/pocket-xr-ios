import PocketXRCore
import SwiftUI
import UIKit

/// The phone's screen: the Space's preview when no glasses are connected (else a line saying it is on the glasses),
/// the trackpad, and the window and Space keys.
struct PhoneHome: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var space = SpaceController.shared
    @State private var keyboard = false
    @State private var showProbe = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Pocket XR").font(.headline)
                Spacer()
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
                Button { showProbe = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Glasses and tracking")
            }
            .padding(.horizontal, 4)
            if space.onGlasses {
                Label("The Space is on your glasses", systemImage: "eyeglasses")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36)
            } else {
                SpacePreview()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomLeading) {
                        Text("Preview: no glasses connected").font(.caption2).padding(6).foregroundStyle(.white.opacity(0.6))
                    }
            }
            ZStack {
                TrackpadRepresentable()
                KeyCatcherRepresentable(active: $keyboard).frame(width: 1, height: 1).opacity(0.01)
            }
            .frame(maxHeight: .infinity)
            if space.mode != .none {
                Text(modeHint).font(.footnote).foregroundStyle(Color.accentColor)
            }
            keys
        }
        .padding(12)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showProbe) { ProbeView().environmentObject(model) }
    }

    private var statusLine: String {
        let p = model.probe
        if p.link == .streaming { return String(format: "Head tracking %.0f Hz", p.imuRateHz) }
        return model.display.connected ? "Glasses connected, no head tracking" : "No glasses"
    }

    private var modeHint: String {
        switch space.mode {
        case .move: return "Drag to move the window. Tap to finish."
        case .resize: return "Drag to resize the window. Tap to finish."
        case .depth: return "Drag up to push the window back, down to pull it closer. Tap to finish."
        case .moveAll: return "Drag to move every window, pinch to resize them all. Tap to finish."
        case .none: return ""
        }
    }

    private var keys: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                key("square.grid.2x2", "Apps") { _ = space.openLauncher() }
                key("switch.2", "Control") { _ = space.openControlCenter() }
                key("keyboard", "Keyboard", on: keyboard) { keyboard.toggle() }
                key("chevron.backward", "Back") { space.back() }
                key("scope", "Recentre") { space.recentre() }
            }
            HStack(spacing: 8) {
                key("arrow.up.and.down.and.arrow.left.and.right", "Move", on: space.mode == .move) { space.setMode(.move) }
                key("arrow.up.left.and.arrow.down.right", "Resize", on: space.mode == .resize) { space.setMode(.resize) }
                key("square.3.layers.3d", "Depth", on: space.mode == .depth) { space.setMode(.depth) }
                key(space.space.locked ? "lock.fill" : "lock.open", "Lock", on: space.space.locked) { space.setLocked(!space.space.locked) }
                key("dot.radiowaves.up.forward", "Pointer", on: space.spatialMouse) {
                    space.spatialMouse.toggle()
                    SpatialMouse.shared.set(space.spatialMouse)
                }
            }
        }
    }

    private func key(_ symbol: String, _ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(on ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The phone's root: forwards a hardware keyboard's keys to the Space when nothing else takes them.
final class PhoneHostingController: UIHostingController<AnyView> {
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let k = press.key else { continue }
            if let name = Self.names[k.keyCode] {
                SpaceController.shared.key(name)
                handled = true
            } else if !k.characters.isEmpty, k.modifierFlags.intersection([.command, .control]).isEmpty {
                SpaceController.shared.type(k.characters)
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    static let names: [UIKeyboardHIDUsage: String] = [
        .keyboardReturnOrEnter: "Enter", .keyboardDeleteOrBackspace: "Backspace", .keyboardTab: "Tab",
        .keyboardEscape: "Escape", .keyboardUpArrow: "ArrowUp", .keyboardDownArrow: "ArrowDown",
        .keyboardLeftArrow: "ArrowLeft", .keyboardRightArrow: "ArrowRight", .keyboardPageUp: "PageUp",
        .keyboardPageDown: "PageDown",
    ]
}
