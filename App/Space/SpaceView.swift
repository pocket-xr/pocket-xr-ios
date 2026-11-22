import PocketXRCore
import QuartzCore
import simd
import UIKit

/// The Space drawn with Core Animation: every window is a live UIKit view (a web page, the launcher, the Control
/// Center) given a 3D transform each frame from the head's pose, so web pages, video and typing stay live at the
/// display's rate. One picture for both eyes: a live web page cannot be drawn from two eye positions, so there is
/// no per-window depth for web windows (docs/STATUS.md). When the glasses are in 3D (a side-by-side display such as
/// 3840x1080), the view's replicator layer shows the one eye's picture twice, once in each half.
final class SpaceView: UIView {
    /// The glasses' vertical field of view; the phone's preview uses the same so it shows what the glasses would.
    var fovYDeg = GlassesOptics.auraFovYDeg
    /// Draws side by side whatever the view's shape (the self-test).
    var forceSideBySide = false {
        didSet { setNeedsLayout() }
    }

    override class var layerClass: AnyClass { CAReplicatorLayer.self }

    /// One eye's picture: every window and the pointer. Half the view in side by side, else all of it.
    private let eye = UIView()

    /// Side by side now: the view is at least 3.2 times as wide as tall (the Android rule), or forced.
    private(set) var sideBySide = false

    private var link: CADisplayLink?
    private let pointerLayer = CALayer()
    private let pointerRing = CALayer()
    private var hosts = [UUID: WindowHost]()
    private var order = [UUID]()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false
        eye.clipsToBounds = true
        eye.backgroundColor = .black
        eye.isUserInteractionEnabled = false
        addSubview(eye)
        pointerRing.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        pointerRing.cornerRadius = 11
        pointerRing.borderWidth = 2
        pointerRing.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        pointerRing.shadowColor = UIColor(red: 0.35, green: 0.58, blue: 1, alpha: 1).cgColor
        pointerRing.shadowOpacity = 0.9
        pointerRing.shadowRadius = 6
        pointerRing.shadowOffset = .zero
        pointerLayer.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        pointerLayer.cornerRadius = 4
        pointerLayer.backgroundColor = UIColor.white.cgColor
        eye.layer.addSublayer(pointerRing)
        eye.layer.addSublayer(pointerLayer)
        pointerRing.zPosition = 1000
        pointerLayer.zPosition = 1001
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sbs = forceSideBySide || GlassesOptics.isSideBySide(width: Int(bounds.width), height: Int(bounds.height))
        if sbs != sideBySide { AppLog.line("space: \(sbs ? "side by side" : "one picture") at \(Int(bounds.width))x\(Int(bounds.height))") }
        sideBySide = sbs
        eye.frame = sbs ? CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height) : bounds
        if let r = layer as? CAReplicatorLayer {
            r.instanceCount = sbs ? 2 : 1
            r.instanceTransform = CATransform3DMakeTranslation(bounds.width / 2, 0, 0)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// The window views, kept in step with the controller's windows.
    func sync(hosts all: [UUID: WindowHost]) {
        for (id, h) in hosts where all[id] == nil { h.removeFromSuperview() }
        for (id, h) in all where h.superview !== eye {
            h.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            eye.insertSubview(h, at: 0)
            hosts[id] = h
        }
        hosts = all
    }

    @objc private func step(_ l: CADisplayLink) {
        let c = SpaceController.shared
        c.tick(now: l.timestamp, period: max(l.targetTimestamp - l.timestamp, 1.0 / 240), view: self)
        draw(head: c.head, windows: c.space.windows, focused: c.space.focused, pointer: c.pointer.aim,
             pointerDistance: c.pointerDistance, hovering: c.hover != nil)
    }

    /// The view's half field of view, degrees: (horizontal, vertical).
    var halfFovDeg: (Double, Double) {
        let b = eye.bounds
        let aspect = Double(max(b.width, 1) / max(b.height, 1))
        let halfY = fovYDeg / 2
        let halfX = atan(tan(halfY * .pi / 180) * aspect) * 180 / .pi
        return (halfX, halfY)
    }

    private func projection() -> simd_float4x4 {
        let bounds = eye.bounds
        let aspect = Double(max(bounds.width, 1) / max(bounds.height, 1))
        let p = SpaceMath.perspective(fovYDeg: fovYDeg, aspect: aspect)
        // Clip space to this view's points, measured from its middle, y down. Depth is kept but shrunk (painter's
        // order does the layering): a zero would make the matrix singular, and WebKit inverts its view's transform
        // (a NaN scroll offset and a crash, seen in the Simulator on 22 Nov 2026).
        let s = simd_float4x4(diagonal: SIMD4(Float(bounds.width / 2), Float(-bounds.height / 2), 0.001, 1))
        return s * p
    }

    private func draw(head: Quat, windows: [SpaceWindow], focused: UUID?, pointer: SpaceAim, pointerDistance: Double, hovering: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pv = projection() * SpaceMath.view(head: head, eyeX: 0)
        let centre = CGPoint(x: eye.bounds.midX, y: eye.bounds.midY)
        let forward = head.rotate(SIMD3(0, 0, -1))
        // Farthest first, so nearer windows draw over them.
        let sorted = windows.sorted { $0.distance > $1.distance }
        let ids = sorted.map { $0.id }
        if ids != order {
            for id in ids { if let h = hosts[id] { eye.bringSubviewToFront(h) } }
            order = ids
        }
        for w in sorted {
            guard let h = hosts[w.id] else { continue }
            h.isActiveWindow = w.id == focused
            let p = w.placement
            // Behind the head or nearly so: hidden (Core Animation cannot clip a layer crossing the eye).
            let mid = PanelCurve.point(p, x: 0, y: 0)
            let len = (mid.x * mid.x + mid.y * mid.y + mid.z * mid.z).squareRoot()
            let cosAngle = (mid.x * forward.x + mid.y * forward.y + mid.z * forward.z) / max(len, 1e-9)
            var visible = cosAngle > 0.2
            let size = h.bounds.size
            // The layer's own points (from its middle, y down) to the unit quad, then into the Space.
            let local = simd_float4x4(diagonal: SIMD4(Float(1 / max(size.width, 1)), Float(-1 / max(size.height, 1)), 1, 1))
            let m = pv * p.modelMatrix * local
            if visible {
                for corner in [SIMD4<Float>(-0.5, -0.5, 0, 1), SIMD4<Float>(0.5, -0.5, 0, 1), SIMD4<Float>(-0.5, 0.5, 0, 1), SIMD4<Float>(0.5, 0.5, 0, 1)] {
                    let q = pv * p.modelMatrix * corner
                    if q.w < 0.05 { visible = false }
                }
            }
            h.isHidden = !visible
            guard visible else { continue }
            h.center = centre
            h.layer.transform = CATransform3D(
                m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.0.y), m13: CGFloat(m.columns.0.z), m14: CGFloat(m.columns.0.w),
                m21: CGFloat(m.columns.1.x), m22: CGFloat(m.columns.1.y), m23: CGFloat(m.columns.1.z), m24: CGFloat(m.columns.1.w),
                m31: CGFloat(m.columns.2.x), m32: CGFloat(m.columns.2.y), m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.2.w),
                m41: CGFloat(m.columns.3.x), m42: CGFloat(m.columns.3.y), m43: CGFloat(m.columns.3.z), m44: CGFloat(m.columns.3.w))
        }
        // The pointer, on the window it is over or at the default distance.
        let dir = pointer.direction * pointerDistance
        let q = pv * SIMD4<Float>(Float(dir.x), Float(dir.y), Float(dir.z), 1)
        let pointerVisible = q.w > 0.05
        pointerLayer.isHidden = !pointerVisible
        pointerRing.isHidden = !pointerVisible
        if pointerVisible {
            let pt = CGPoint(x: centre.x + CGFloat(q.x / q.w), y: centre.y + CGFloat(q.y / q.w))
            pointerLayer.position = pt
            pointerRing.position = pt
            pointerRing.opacity = hovering ? 1 : 0.55
        }
        CATransaction.commit()
    }
}
