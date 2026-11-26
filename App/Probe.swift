import Darwin
import Foundation
import PocketXRCore

/// What the probe has found so far. Read by the phone screen, the glasses picture and the self-test.
struct ProbeState: Codable, Equatable {
    enum Link: String, Codable { case looking, connecting, streaming, lost }

    var link: Link = .looking
    var via = ""
    var lastError = ""
    var tries = 0
    var interfaces = ""
    var routes = [String]()
    var reports = 0
    var imuReports = 0
    var imuRateHz = 0.0
    var yawDeg = 0.0
    var pitchDeg = 0.0
    var yawMinDeg = 0.0
    var yawMaxDeg = 0.0
    var biasReady = false
    /// 0.1.1: the sensor axes in use are the One family's.
    var axesOne = false
}

/// 0.1.1: the glasses kept between launches. "setup.glasses" is the setup check's pick ("aura", "one", "air", ...);
/// "setup.glasses.picked" is true once the user picked the Aura or the One there or with the axes switch, which then
/// wins over gravity. Before 0.1.1 the axes always started as the Aura's and the switch was forgotten at each launch.
enum GlassesChoice {
    static let key = "setup.glasses"
    static let pickedKey = "setup.glasses.picked"

    static var axes: HeadFusion.Axes { UserDefaults.standard.string(forKey: key) == "one" ? .one : .aura }
    static var picked: Bool { UserDefaults.standard.bool(forKey: pickedKey) }

    static func save(_ a: HeadFusion.Axes, picked: Bool) {
        UserDefaults.standard.set(a == .one ? "one" : "aura", forKey: key)
        if picked { UserDefaults.standard.set(true, forKey: pickedKey) }
    }
}

/// The glasses' sensor stream over their USB network: TCP 52998 on 169.254.2.1 (NCM) or 169.254.1.1 (ECM), found and
/// opened the same way as on the Mac (PocketXRCore's GlassesNet). Whether iOS brings that network up for the XREAL
/// Aura and One family at all is what phase 0 is for; until it is tried on a USB-C iPhone it is unknown.
///
/// For the Simulator, `-PXRProbeHost 127.0.0.1` points the probe at Tools/FakeGlasses on the Mac instead.
final class Probe: @unchecked Sendable {
    static let shared = Probe()

    private let lock = NSLock()
    private var state = ProbeState(axesOne: GlassesChoice.axes == .one)
    private var started = false
    private var axes: HeadFusion.Axes = GlassesChoice.axes
    private var fusion = HeadFusion(axes: GlassesChoice.axes)
    /// The drawing pose: prediction to the frame's light, draw smoothing, the Still lock, Smooth Follow (the same
    /// chain as on the Mac and Steam Deck, PocketXRCore's HeadPose).
    private lazy var pose = HeadPose(fusion: fusion)

    /// Called on the main queue whenever the state changes, at most about 30 times a second.
    var onChange: ((ProbeState) -> Void)?

    var snapshot: ProbeState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    /// The head's orientation now, for the glasses picture.
    func view() -> Quat {
        lock.lock()
        let f = fusion
        lock.unlock()
        return f.view()
    }

    /// [picked]: the user chose them (the axes switch or the setup check), so gravity no longer decides.
    func setAxes(_ a: HeadFusion.Axes, picked: Bool) {
        GlassesChoice.save(a, picked: picked)
        lock.lock()
        let changed = axes != a
        axes = a
        if changed {
            fusion = HeadFusion(axes: a)
            pose = HeadPose(fusion: fusion)
            state.yawMinDeg = 0
            state.yawMaxDeg = 0
        }
        state.axesOne = a == .one
        let s = state
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onChange?(s) }
        guard changed else { return }
        AppLog.line("probe: sensor axes set to \(a == .aura ? "Aura" : "One family")\(picked ? " (picked)" : "")")
        DispatchQueue.main.async { MainActor.assumeIsolated { GlassesControl.shared.use(one: a == .one) } }
    }

    private var currentAxes: HeadFusion.Axes {
        lock.lock(); defer { lock.unlock() }
        return axes
    }

    func recentre() {
        lock.lock()
        let p = pose
        lock.unlock()
        p.recentre(yawDeg: 0, followTilt: true)
    }

    /// The pose to draw the next frame with, from HeadPose.
    func drawPose(now: Double, framePeriod: Double, options: TrackingOptions) -> Quat {
        lock.lock()
        let p = pose
        lock.unlock()
        return p.drawPose(now: now, framePeriod: framePeriod, options: options)
    }

    /// Whether the Still lock holds the picture now.
    var held: Bool {
        lock.lock()
        let p = pose
        lock.unlock()
        return p.held
    }

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()
        let t = Thread { [weak self] in self?.run() }
        t.name = "glasses-probe"
        t.qualityOfService = .userInteractive
        t.start()
    }

    private func update(_ change: (inout ProbeState) -> Void) {
        lock.lock()
        change(&state)
        let s = state
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.onChange?(s) }
    }

    private func run() {
        let overrideHost = UserDefaults.standard.string(forKey: "PXRProbeHost")
        if let h = overrideHost { AppLog.line("probe: using test host \(h) instead of the glasses") }
        var lastLogged = ""
        while true {
            let interfaces = GlassesNet.describeInterfaces()
            let routes = GlassesNet.routes()
            update {
                $0.interfaces = interfaces
                $0.routes = routes.map { $0.description }
                $0.tries += 1
                $0.link = .connecting
            }
            do {
                let fd: Int32
                let via: String
                if let h = overrideHost {
                    fd = try GlassesNet.connect(host: h, port: ImuFramer.port, route: nil, timeoutS: 2)
                    via = "\(h):\(ImuFramer.port) (test host)"
                } else {
                    (fd, via) = try GlassesNet.open(port: ImuFramer.port) { AppLog.line("probe: \($0)") }
                }
                AppLog.line("probe: sensor stream open via \(via)")
                update { $0.link = .streaming; $0.via = via; $0.lastError = "" }
                read(fd, control: overrideHost == nil)
                close(fd)
                AppLog.line("probe: sensor stream closed")
                update { $0.link = .lost }
            } catch {
                let msg = "\(error)"
                if msg != lastLogged {
                    AppLog.line("probe: \(msg); interfaces: \(interfaces)")
                    lastLogged = msg
                }
                update { $0.link = .looking; $0.lastError = msg }
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    /// [control]: start the glasses' control link once the glasses are known (not with the Simulator's test host).
    private func read(_ fd: Int32, control: Bool) {
        let framer = ImuFramer()
        // 0.1.1: the first quarter second tells an Aura from a One by gravity, unless the user picked them; the
        // control link starts after it, so the glasses are set up as what they are.
        var guess = AxesGuess()
        var known = false
        let picked = GlassesChoice.picked
        var buf = [UInt8](repeating: 0, count: 16384)
        var windowStart = ProcessInfo.processInfo.systemUptime
        var windowImu = 0
        var lastPublish = 0.0
        while true {
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n == 0 { return }
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                AppLog.line("probe: read failed: \(String(cString: strerror(errno)))")
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let samples = framer.feed(Array(buf[0..<n]))
            lock.lock()
            let f = fusion
            lock.unlock()
            for s in samples {
                f.report(s, arrived: now)
                guess.add(s)
            }
            if !known && guess.done {
                known = true
                let inUse = currentAxes
                let name: (HeadFusion.Axes) -> String = { $0 == .aura ? "Aura" : "One family" }
                if let g = guess.result {
                    if g == inUse {
                        AppLog.line("probe: gravity reads like the \(name(g)) axes in use")
                    } else if picked {
                        AppLog.line("probe: gravity reads like the \(name(g)), but the \(name(inUse)) was picked; keeping it")
                    } else {
                        AppLog.line("probe: gravity reads like the \(name(g)), not the \(name(inUse))")
                        setAxes(g, picked: false)
                    }
                } else {
                    AppLog.line("probe: gravity did not tell the glasses' axes (moving or on their side); keeping the \(name(inUse))")
                }
                if control {
                    let one = currentAxes == .one
                    DispatchQueue.main.async { MainActor.assumeIsolated { GlassesControl.shared.startIfLinked(one: one) } }
                }
            }
            windowImu += samples.count
            if now - lastPublish >= 1.0 / 30 {
                lastPublish = now
                let q = f.view()
                let forward = q.rotate(SIMD3(0, 0, -1))
                let yaw = q.yaw * 180 / .pi
                let pitch = asin(max(-1, min(1, forward.y))) * 180 / .pi
                let elapsed = now - windowStart
                let rate: Double? = elapsed >= 1 ? Double(windowImu) / elapsed : nil
                if elapsed >= 1 { windowStart = now; windowImu = 0 }
                update {
                    $0.reports = framer.reports
                    $0.imuReports = framer.imu
                    if let r = rate { $0.imuRateHz = r }
                    $0.yawDeg = yaw
                    $0.pitchDeg = pitch
                    $0.yawMinDeg = min($0.yawMinDeg, yaw)
                    $0.yawMaxDeg = max($0.yawMaxDeg, yaw)
                    $0.biasReady = f.biasReady
                }
            }
        }
    }
}
