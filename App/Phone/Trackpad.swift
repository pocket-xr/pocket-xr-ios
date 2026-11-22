import CoreMotion
import GameController
import PocketXRCore
import SwiftUI
import UIKit

/// The phone as a trackpad: one finger moves the pointer, a tap clicks, two fingers scroll, a pinch resizes the
/// focused window, three-finger swipes go between windows (left, right), open the launcher (up) and the Control
/// Center (down). A press that starts on a window's bar drags the window.
final class TrackpadView: UIView, UIGestureRecognizerDelegate {
    private var lastOne = CGPoint.zero
    private var lastTwo = CGPoint.zero
    private var lastScale: CGFloat = 1
    private let hint = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        isMultipleTouchEnabled = true
        hint.text = "Trackpad"
        hint.textColor = UIColor.white.withAlphaComponent(0.22)
        hint.font = .systemFont(ofSize: 15, weight: .medium)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([hint.centerXAnchor.constraint(equalTo: centerXAnchor), hint.centerYAnchor.constraint(equalTo: centerYAnchor)])

        let one = UIPanGestureRecognizer(target: self, action: #selector(onePan(_:)))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        let two = UIPanGestureRecognizer(target: self, action: #selector(twoPan(_:)))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(press(_:)))
        press.minimumPressDuration = 0.25
        press.allowableMovement = 8
        for r in [one, two, pinch, tap, press] as [UIGestureRecognizer] {
            r.delegate = self
            addGestureRecognizer(r)
        }
        for d in [UISwipeGestureRecognizer.Direction.left, .right, .up, .down] {
            let s = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:)))
            s.numberOfTouchesRequired = 3
            s.direction = d
            s.delegate = self
            addGestureRecognizer(s)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Two-finger scroll and pinch together; a press and the one-finger pan together (press then drag a window).
        let pair: Set<ObjectIdentifier> = [ObjectIdentifier(type(of: g)), ObjectIdentifier(type(of: other))]
        return pair == [ObjectIdentifier(UIPanGestureRecognizer.self), ObjectIdentifier(UIPinchGestureRecognizer.self)]
            || pair == [ObjectIdentifier(UIPanGestureRecognizer.self), ObjectIdentifier(UILongPressGestureRecognizer.self)]
    }

    @objc private func onePan(_ g: UIPanGestureRecognizer) {
        let p = g.translation(in: self)
        switch g.state {
        case .began:
            lastOne = p
        case .changed:
            SpaceController.shared.pointerMove(dx: Double(p.x - lastOne.x), dy: Double(p.y - lastOne.y), speed: 1.2)
            lastOne = p
        case .ended, .cancelled, .failed:
            SpaceController.shared.pressEnded()
        default: break
        }
    }

    @objc private func twoPan(_ g: UIPanGestureRecognizer) {
        let p = g.translation(in: self)
        switch g.state {
        case .began:
            lastTwo = p
        case .changed:
            // Natural scrolling: fingers up move the page up, so it scrolls down.
            SpaceController.shared.scroll(dx: Double(lastTwo.x - p.x) * 2.5, dy: Double(lastTwo.y - p.y) * 2.5)
            lastTwo = p
        default: break
        }
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            lastScale = g.scale
        case .changed:
            SpaceController.shared.pinch(scaleChange: Double(g.scale / max(lastScale, 0.01)))
            lastScale = g.scale
        default: break
        }
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        if g.state == .ended { SpaceController.shared.click() }
    }

    @objc private func press(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            SpaceController.shared.pressBegan()
        case .ended, .cancelled:
            SpaceController.shared.pressEnded()
        default: break
        }
    }

    @objc private func swipe(_ g: UISwipeGestureRecognizer) {
        SpaceController.shared.swipe(g.direction)
    }
}

/// Catches the phone keyboard's typing and sends it to the focused window. Becomes first responder when the
/// Keyboard button is pressed.
final class KeyCatcher: UIView, UIKeyInput {
    var hasText: Bool { true }
    override var canBecomeFirstResponder: Bool { true }
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no

    func insertText(_ text: String) {
        if text == "\n" { SpaceController.shared.key("Enter") } else { SpaceController.shared.type(text) }
    }

    func deleteBackward() { SpaceController.shared.key("Backspace") }

    /// The keyboard's shortcut row: Esc, Tab and the arrows.
    override var inputAccessoryView: UIView? {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        func item(_ title: String, _ key: String) -> UIBarButtonItem {
            UIBarButtonItem(title: title, primaryAction: UIAction { _ in SpaceController.shared.key(key) })
        }
        bar.items = [item("Esc", "Escape"), item("Tab", "Tab"), .flexibleSpace(), item("←", "ArrowLeft"), item("↑", "ArrowUp"),
                     item("↓", "ArrowDown"), item("→", "ArrowRight"), .flexibleSpace(),
                     UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.resignFirstResponder() })]
        return bar
    }
}

/// The Spatial Mouse: point the phone like a laser; its turn moves the pointer.
@MainActor
final class SpatialMouse {
    static let shared = SpatialMouse()
    private let motion = CMMotionManager()
    private(set) var running = false

    func set(_ on: Bool) {
        guard on != running, motion.isDeviceMotionAvailable else { return }
        running = on
        if on {
            motion.deviceMotionUpdateInterval = 1.0 / 120
            motion.startDeviceMotionUpdates(to: .main) { m, _ in
                guard let r = m?.rotationRate else { return }
                // Held like a remote, top forward: turning left is +z, tilting the top up is +x. Degrees to
                // trackpad points so the pointer follows the phone's aim one to one.
                let dt = 1.0 / 120
                let k = SpacePointer.pointsPerDeg * 180 / .pi * dt
                MainActor.assumeIsolated {
                    SpaceController.shared.pointerMove(dx: -r.z * k, dy: -r.x * k)
                }
            }
        } else {
            motion.stopDeviceMotionUpdates()
        }
    }
}

/// A Bluetooth or USB mouse moves the same pointer: left click clicks, the wheel scrolls.
@MainActor
final class MouseInput {
    static let shared = MouseInput()

    func start() {
        NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { n in
            guard let mouse = n.object as? GCMouse else { return }
            MainActor.assumeIsolated { MouseInput.shared.attach(mouse) }
        }
        for m in GCMouse.mice() { attach(m) }
    }

    private func attach(_ mouse: GCMouse) {
        AppLog.line("input: mouse connected")
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = { _, dx, dy in
            DispatchQueue.main.async { MainActor.assumeIsolated { SpaceController.shared.pointerMove(dx: Double(dx), dy: Double(-dy)) } }
        }
        input.leftButton.pressedChangedHandler = { _, _, pressed in
            if pressed { DispatchQueue.main.async { MainActor.assumeIsolated { SpaceController.shared.click() } } }
        }
        input.scroll.valueChangedHandler = { _, x, y in
            DispatchQueue.main.async { MainActor.assumeIsolated { SpaceController.shared.scroll(dx: Double(-x) * 20, dy: Double(-y) * 20) } }
        }
    }
}

// MARK: - SwiftUI wrappers

struct TrackpadRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TrackpadView { TrackpadView() }
    func updateUIView(_ uiView: TrackpadView, context: Context) {}
}

/// Hosts the Space's view on the phone when no glasses are connected.
struct SpacePreview: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        v.clipsToBounds = true
        DispatchQueue.main.async { SpaceController.shared.attachPreview(v) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        SpaceController.shared.attachPreview(nil)
    }
}

struct KeyCatcherRepresentable: UIViewRepresentable {
    @Binding var active: Bool

    func makeUIView(context: Context) -> KeyCatcher { KeyCatcher() }

    func updateUIView(_ v: KeyCatcher, context: Context) {
        if active, !v.isFirstResponder { DispatchQueue.main.async { v.becomeFirstResponder() } }
        if !active, v.isFirstResponder { DispatchQueue.main.async { v.resignFirstResponder() } }
    }
}
