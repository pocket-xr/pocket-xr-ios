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
}

/// The glasses' sensor stream over their USB network: TCP 52998 on 169.254.2.1 (NCM) or 169.254.1.1 (ECM), found and
/// opened the same way as on the Mac (PocketXRCore's GlassesNet). Whether iOS brings that network up for the XREAL
/// Aura and One family at all is what phase 0 is for; until it is tried on a USB-C iPhone it is unknown.
///
/// For the Simulator, `-PXRProbeHost 127.0.0.1` points the probe at Tools/FakeGlasses on the Mac instead.
final class Probe: @unchecked Sendable {
    static let shared = Probe()

    private let lock = NSLock()
    private var state = ProbeState()
    private var started = false
    private var axes: HeadFusion.Axes = .aura
    private var fusion = HeadFusion(axes: .aura)

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

    func setAxes(_ a: HeadFusion.Axes) {
        lock.lock()
        axes = a
        fusion = HeadFusion(axes: a)
        state.yawMinDeg = 0
        state.yawMaxDeg = 0
        lock.unlock()
        Log.line("probe: sensor axes set to \(a == .aura ? "Aura" : "One family")")
    }

    func recentre() {
        lock.lock()
        let f = fusion
        lock.unlock()
        f.recentre()
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
        if let h = overrideHost { Log.line("probe: using test host \(h) instead of the glasses") }
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
                    (fd, via) = try GlassesNet.open(port: ImuFramer.port) { Log.line("probe: \($0)") }
                }
                Log.line("probe: sensor stream open via \(via)")
                update { $0.link = .streaming; $0.via = via; $0.lastError = "" }
                read(fd)
                close(fd)
                Log.line("probe: sensor stream closed")
                update { $0.link = .lost }
            } catch {
                let msg = "\(error)"
                if msg != lastLogged {
                    Log.line("probe: \(msg); interfaces: \(interfaces)")
                    lastLogged = msg
                }
                update { $0.link = .looking; $0.lastError = msg }
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func read(_ fd: Int32) {
        let framer = ImuFramer()
        var buf = [UInt8](repeating: 0, count: 16384)
        var windowStart = ProcessInfo.processInfo.systemUptime
        var windowImu = 0
        var lastPublish = 0.0
        while true {
            let n = buf.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n == 0 { return }
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }
                Log.line("probe: read failed: \(String(cString: strerror(errno)))")
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let samples = framer.feed(Array(buf[0..<n]))
            lock.lock()
            let f = fusion
            lock.unlock()
            for s in samples { f.report(s, arrived: now) }
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
