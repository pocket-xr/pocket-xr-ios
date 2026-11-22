import AVFoundation
import Foundation
import PocketXRCore
import UIKit

/// What this phone keeps for each PC screen: the computer (address and port), its HTTPS port, the host's pinned
/// certificate and its name.
struct PcScreenStore: Codable, Equatable {
    var address = ""
    var httpsPort = 0
    var serverCert: Data?
    var pcName: String?

    var paired: Bool { serverCert != nil && !address.isEmpty }

    static func load(_ slot: Int) -> PcScreenStore {
        guard let d = UserDefaults.standard.data(forKey: "pcscreen.\(slot)"), let s = try? JSONDecoder().decode(PcScreenStore.self, from: d) else {
            return PcScreenStore()
        }
        return s
    }

    func save(_ slot: Int) {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: "pcscreen.\(slot)") }
    }

    /// Host and port from an address as typed or saved ("192.168.1.20", "192.168.1.20:50989").
    static func parse(_ text: String) -> (host: String, port: Int)? {
        PcHostAddress.parse(text)
    }
}

/// What the self-test reads back from a PC screen.
struct PcScreenReport: Codable {
    var slot = 0
    var address = ""
    var paired = false
    var state = ""
    var lastSay = ""
    var width = 0
    var height = 0
    var framesIn = 0
    var framesShown = 0
    var keyFrames = 0
    var audioPackets = 0
    var audioDecoded = 0
    var videoLayerFailed = false
}

/// A PC screen in the Space: another computer's screen streamed into a window, with the pointer, scrolling and typing
/// passed to it. Connecting (find, pair, launch, stream) runs in the background, the way Pocket XR for Windows' PC
/// screen session does it.
@MainActor
final class PcScreenContent: NSObject, SpaceContent {
    let slot: Int
    private let root = UIView()
    private let videoView = LayerFillView()
    private let say = UILabel()
    private var stream: PcStream?
    private var store: PcScreenStore
    private var streaming = false
    private var closing = false
    private var attempt = 0
    private var lostAt: Date?
    private var streamW = 1920, streamH = 1080
    private var activeHttp: NvHttp?
    private(set) var lastSay = ""
    private(set) var state = "starting"
    /// Readability: the stream asks for 3/4 of the pixels each way, so text on the PC is a third bigger.
    private(set) var readability = false

    /// Readability changed: a stream already running starts again at the new size.
    func setReadability(_ on: Bool) {
        guard on != readability else { return }
        readability = on
        guard streaming, let s = stream else { return }
        AppLog.line("pc screen \(slot + 1): Readability \(on ? "on" : "off"): starting the stream again at the new size")
        streaming = false
        stream = nil
        lostAt = nil
        // The same copy of the core must have stopped before it starts again.
        Task {
            await Task.detached { s.stop() }.value
            await connect()
        }
    }

    var view: UIView { root }
    var title: String { store.pcName.map { "\($0) (PC screen \(slot + 1))" } ?? "PC screen \(slot + 1)" }
    var onTitle: (() -> Void)?

    init(slot: Int) {
        self.slot = slot
        store = PcScreenStore.load(slot)
        super.init()
        root.backgroundColor = .black
        videoView.backgroundColor = .black
        videoView.frame = root.bounds
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(videoView)
        say.textColor = UIColor.white.withAlphaComponent(0.85)
        say.font = .systemFont(ofSize: 34, weight: .medium)
        say.numberOfLines = 0
        say.textAlignment = .center
        say.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(say)
        NSLayoutConstraint.activate([
            say.centerXAnchor.constraint(equalTo: root.centerXAnchor), say.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            say.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.8),
        ])
        let typedKey = slot == 0 ? "PXRPcAddress" : "PXRPcAddress\(slot + 1)"
        if let typed = UserDefaults.standard.string(forKey: typedKey), store.address.isEmpty {
            store.address = typed
            store.save(slot)
        }
        Task { await connect() }
    }

    private func show(_ text: String) {
        lastSay = text
        say.text = text
        say.isHidden = text.isEmpty
        AppLog.line("pc screen \(slot + 1): \(text)")
    }

    /// Where the stream's picture sits in the window: as large as fits, its shape kept, centred.
    private var fit: CGRect {
        let b = root.bounds
        guard b.width > 0, b.height > 0, streamW > 0, streamH > 0 else { return b }
        let s = min(b.width / CGFloat(streamW), b.height / CGFloat(streamH))
        let w = CGFloat(streamW) * s, h = CGFloat(streamH) * s
        return CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
    }

    func report() -> PcScreenReport {
        var r = PcScreenReport()
        r.slot = slot
        r.address = store.address
        r.paired = store.paired
        r.state = state
        r.lastSay = lastSay
        r.width = streamW
        r.height = streamH
        if let s = stream {
            r.framesIn = s.framesIn
            r.framesShown = s.framesShown
            r.keyFrames = s.keyFrames
            r.audioPackets = s.audioPackets
            r.audioDecoded = s.audioDecoded
            r.videoLayerFailed = s.videoLayer.sampleBufferRenderer.status == .failed
        }
        return r
    }

    // MARK: Connecting

    private func connect() async {
        guard !closing else { return }
        guard let id = PcIdentity.shared else {
            show("This phone's PC screen key could not be made (keychain). PC screens cannot connect.")
            state = "no identity"
            return
        }
        if store.address.isEmpty {
            state = "finding"
            guard await find() else { return }
        }
        if !store.paired {
            state = "pairing"
            guard await pair(id) else { return }
        }
        state = "launching"
        await startStream(id, fresh: lostAt == nil)
    }

    /// A computer for this PC screen: the Pocket XR helpers that answer, and their hosts' instances. The first instance
    /// no other PC screen uses; PC screen 1 the main one.
    private func find() async -> Bool {
        show("Looking for computers…")
        let slot = self.slot
        let taken = Set((0..<3).filter { $0 != slot }.map { PcScreenStore.load($0).address })
        // Computers that announce Moonlight's service (Pocket XR's computer side, Apollo, Sunshine), by mDNS.
        let announced = await PcFinder.browse(seconds: 2)
        AppLog.line("pc screen \(slot + 1): mDNS found \(announced.count): \(announced.map { "\($0.name) \($0.host):\($0.port)" }.joined(separator: ", "))")
        let found: (String, String)? = await Task.detached {
            for f in announced where !taken.contains("\(f.host):\(f.port)") {
                let http = NvHttp(host: f.host, httpPort: f.port, httpsPort: 0, serverCert: nil, identity: PcIdentity.shared!)
                if (try? await http.serverInfo(timeout: 1.5)) != nil {
                    let order = slot == 0 || announced.filter({ $0.host == f.host }).count < 2 ? announced : Array(announced.reversed())
                    if let pick = order.first(where: { $0.host == f.host && !taken.contains("\($0.host):\($0.port)") }) {
                        return ("\(pick.host):\(pick.port)", PcScreenPick.pcName(pick.name))
                    }
                }
            }
            for pc in PcHelperLink.findAll() {
                let ports = pc.sunshinePorts.isEmpty ? [50989, 51989, 52989, 47989, 48989, 49989] : pc.sunshinePorts
                var answering = [Int]()
                for p in ports {
                    let http = NvHttp(host: pc.address, httpPort: p, httpsPort: 0, serverCert: nil, identity: PcIdentity.shared!)
                    if (try? await http.serverInfo(timeout: 1.5)) != nil { answering.append(p) }
                }
                let order = slot == 0 ? answering : Array(answering.dropFirst()) + answering.prefix(1)
                if let p = order.first(where: { !taken.contains("\(pc.address):\($0)") }) {
                    return ("\(pc.address):\(p)", pc.name)
                }
            }
            return nil
        }.value
        guard let found else {
            show("No computer found. On the computer, turn on \"Let my phone show this computer\" in Pocket XR for Windows, Mac or "
                 + "Steam Deck, or run Apollo or Sunshine.\nOr type its address with the Keyboard key, then Return:")
            state = "none found"
            typing = ""
            return false
        }
        store.address = found.0
        store.pcName = found.1
        store.save(slot)
        onTitle?()
        return true
    }

    private func pair(_ id: PcIdentity) async -> Bool {
        guard let parsed = PcScreenStore.parse(store.address) else { show("The computer's address is not right: \(store.address)"); return false }
        let (host, port) = parsed
        let pin = UserDefaults.standard.string(forKey: "PXRPcPin") ?? NvHttp.newPin()
        let http = NvHttp(host: host, httpPort: port, httpsPort: 0, serverCert: nil, identity: id)
        do {
            let info = try await http.serverInfo()
            let name = PcScreenXml.value(info, "hostname") ?? host
            show("Pairing with \(name)…")
            let shown = self
            Task.detached {
                guard let helper = PcHelperLink.find(at: host) else {
                    await MainActor.run {
                        shown.show("On \(name), type the PIN \(pin) in Apollo's or Sunshine's PIN page (https://\(host):\(port + 1)/pin), "
                                   + "or in Pocket XR there when it asks.")
                    }
                    return
                }
                if !PcHelperLink.knows(helper) {
                    await MainActor.run { shown.show("On \(helper.name), say Yes to let this phone show it (once).") }
                    guard PcHelperLink.pair(helper) else {
                        await MainActor.run { shown.show("\(helper.name) did not allow this phone. Type the PIN \(pin) there instead (https://\(host):\(port + 1)/pin for Apollo or Sunshine).") }
                        return
                    }
                }
                if let why = PcHelperLink.givePin(helper, pin: pin, hostPort: port) {
                    await MainActor.run { shown.show("On \(name), type the PIN \(pin). (The helper said: \(why).)") }
                }
            }
            let state = try await http.pair(serverInfo: info, pin: pin)
            AppLog.line("pc screen \(slot + 1): pair with \(name) at \(store.address): \(state.rawValue)")
            guard state == .paired, let cert = http.serverCert else {
                show(state == .pinWrong ? "The PIN was wrong. Close this PC screen and open it again to try again." : "Pairing with \(name) did not work (\(state.rawValue)).")
                self.state = "pair failed"
                return false
            }
            store.httpsPort = NvHttp.httpsPort(of: info)
            store.serverCert = cert
            store.pcName = PcScreenLogicName.pcName(name)
            store.save(slot)
            onTitle?()
            return true
        } catch {
            show("The computer did not answer: \(error)")
            lost()
            return false
        }
    }

    private func startStream(_ id: PcIdentity, fresh: Bool) async {
        guard let parsed = PcScreenStore.parse(store.address) else { return }
        let (host, port) = parsed
        show("Connecting to \(store.pcName ?? host)…")
        let http = NvHttp(host: host, httpPort: port, httpsPort: store.httpsPort, serverCert: store.serverCert, identity: id)
        activeHttp = http
        do {
            let info = try await http.serverInfo()
            if PcScreenXml.value(info, "PairStatus") != "1" {
                AppLog.line("pc screen \(slot + 1): the host does not know this phone any more: pairing again")
                store.serverCert = nil
                store.save(slot)
                guard await pair(id) else { return }
                await startStream(id, fresh: fresh)
                return
            }
            // The picture at the window's own shape when the host makes a screen for it (Pocket XR hosts and Apollo do);
            // Readability asks for 3/4 of the pixels each way.
            let scale = readability ? 0.75 : 1.0
            let b = root.bounds.size
            let aspect = b.height > 0 ? Double(b.width / b.height) : 16.0 / 9.0
            var w = Int(1920 * scale), h = Int(Double(w) / aspect)
            w = max(640, w / 8 * 8)
            h = max(360, h / 8 * 8)
            let fps = 60
            let kbps = Int(min(max(40_000.0 * Double(w * h) / (1920.0 * 1080.0), 8_000), 150_000))
            let apps = PcScreenXml.apps(try await http.appList())
            guard let app = PcScreenXml.desktopApp(apps) else { show("The computer lists nothing to show."); return }
            var verb = "launch"
            let running = PcScreenXml.currentGame(info)
            if running != 0 {
                if fresh { try? await http.quit() } else if running == app.id { verb = "resume" }
            }
            if let helper = await Task.detached(operation: { PcHelperLink.find(at: host) }).value,
               let says = await Task.detached(operation: { PcHelperLink.hostInfo(helper) }).value, says.virtual {
                let ready = await Task.detached(operation: { PcHelperLink.screenPrepare(helper, hostPort: port, width: w, height: h, fps: fps) }).value
                AppLog.line("pc screen \(slot + 1): screen-prepare \(w)x\(h)@\(fps): \(ready ? "ready" : "not ready")")
            }
            let s = PcStream(slot: slot)
            let riKey = PcCrypto.random(16)
            let riKeyId = Int32.random(in: 0..<Int32.max)
            AppLog.line("pc screen \(slot + 1): \(verb) \(app.name) on \(host):\(port) at \(w)x\(h)@\(fps), \(kbps / 1000) Mbps")
            let rtsp = try await http.launch(verb, appId: app.id, width: w, height: h, fps: fps, riKey: riKey, riKeyId: riKeyId,
                                             virtualDisplay: true, localAudio: false, surroundAudioInfo: (0x3 << 16) | 2,
                                             coreQuery: s.launchQuery)
            guard !closing else { return }
            streamW = w
            streamH = h
            attach(s)
            s.onEvent = { [weak self] e in self?.event(e) }
            stream = s
            let appVersion = PcScreenXml.value(info, "appversion") ?? "7.1.431.-1"
            let gfe = PcScreenXml.value(info, "GfeVersion")
            let codecs = Int32(PcScreenXml.value(info, "ServerCodecModeSupport") ?? "") ?? 0
            state = "starting stream"
            let ret = await Task.detached {
                s.start(address: host, appVersion: appVersion, gfeVersion: gfe, rtspSessionUrl: rtsp, codecSupport: codecs,
                        width: w, height: h, fps: fps, bitrateKbps: kbps, riKey: riKey, riKeyId: riKeyId)
            }.value
            if ret != 0 {
                show("The stream did not start (\(ret)).")
                lost()
            }
        } catch {
            show((error as? HostError).map { $0.code == 403 ? "The computer refused this phone (403): allow it to launch there." : "\($0)" }
                 ?? "The computer did not answer. Is it on, with Pocket XR's computer side running?")
            lost()
        }
    }

    private func attach(_ s: PcStream) {
        videoView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        s.videoLayer.frame = videoView.bounds
        videoView.layer.addSublayer(s.videoLayer)
    }

    private func event(_ e: PcStream.Event) {
        switch e {
        case .stage(let text):
            state = text
        case .started:
            streaming = true
            state = "streaming"
            attempt = 0
            lostAt = nil
            show("")
        case .terminated(let err):
            streaming = false
            state = "ended \(err)"
            show("The stream stopped (\(err)).")
            lost()
        case .failed(let text):
            state = "failed: \(text)"
            show("Could not connect: \(text).")
        }
    }

    /// Tries again after 1, 2, 4, 8 s, then every 10 s, for 3 minutes.
    private func lost() {
        guard !closing else { return }
        stream?.stop()
        stream = nil
        streaming = false
        if lostAt == nil { lostAt = Date(); attempt = 0 }
        let lostFor = Date().timeIntervalSince(lostAt!)
        guard lostFor < 180 else {
            show(lastSay + " Close this PC screen and open it again to try again.")
            return
        }
        let wait = attempt < 4 ? Double(1 << attempt) : 10
        attempt += 1
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
            await self?.connect()
        }
    }

    /// Closing the window ends the host's session, so the computer removes the screen it made.
    func close() {
        closing = true
        let s = stream
        stream = nil
        let http = activeHttp
        Task.detached {
            s?.stop()
            try? await http?.quit()
        }
    }

    // MARK: Input

    private func streamPoint(_ p: CGPoint) -> (Int, Int)? {
        let f = fit
        guard f.width > 0, f.height > 0, f.contains(p) else { return nil }
        return (Int((p.x - f.minX) / f.width * CGFloat(streamW)), Int((p.y - f.minY) / f.height * CGFloat(streamH)))
    }

    func click(at p: CGPoint) {
        guard streaming, let s = stream, let at = streamPoint(p) else { return }
        s.mousePosition(x: at.0, y: at.1, refWidth: streamW, refHeight: streamH)
        s.mouseButton(PcStream.buttonLeft, down: true)
        s.mouseButton(PcStream.buttonLeft, down: false)
    }

    func hover(at p: CGPoint) {
        guard streaming, let s = stream, let at = streamPoint(p) else { return }
        s.mousePosition(x: at.0, y: at.1, refWidth: streamW, refHeight: streamH)
    }

    func scroll(at p: CGPoint, dx: CGFloat, dy: CGFloat) {
        guard streaming, let s = stream else { return }
        hover(at: p)
        // 120 a notch; content moving down (dy > 0) is a scroll down, which the host takes as negative.
        if dy != 0 { s.scroll(Int(-dy * 1.5)) }
        if dx != 0 { s.hscroll(Int(dx * 1.5)) }
    }

    /// The address being typed after no computer was found; nil when not asking for one.
    private var typing: String?

    func type(_ text: String) {
        if var t = typing {
            t += text.filter { $0.isLetter || $0.isNumber || ".:-[]%".contains($0) }
            typing = t
            say.text = lastSay + "\n\n" + t
            return
        }
        guard streaming, let s = stream else { return }
        s.text(text)
    }

    /// The typed address is used: this PC screen connects there.
    private func useTyped() {
        guard let t = typing?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return }
        guard PcScreenStore.parse(t) != nil else { show("That is not an address: \(t)"); typing = ""; return }
        typing = nil
        store.address = t
        store.save(slot)
        lostAt = nil
        Task { await connect() }
    }

    /// Key names as the Space sends them, to Windows virtual-key codes (the host maps them for a Mac or Linux).
    static let keys: [String: Int] = [
        "Enter": 0x0D, "Backspace": 0x08, "Tab": 0x09, "Escape": 0x1B, "ArrowLeft": 0x25, "ArrowUp": 0x26,
        "ArrowRight": 0x27, "ArrowDown": 0x28, "PageUp": 0x21, "PageDown": 0x22, "Delete": 0x2E, "Home": 0x24, "End": 0x23,
    ]

    func key(_ name: String) {
        if var t = typing {
            switch name {
            case "Enter": useTyped()
            case "Backspace": if !t.isEmpty { t.removeLast(); typing = t; say.text = lastSay + "\n\n" + t }
            case "Escape": typing = ""; say.text = lastSay
            default: break
            }
            return
        }
        guard streaming, let s = stream, let vk = Self.keys[name] else { return }
        s.key(vk)
    }

    /// For the self-test: an address typed as the user would.
    func typeAddressForTest(_ address: String) {
        typing = ""
        type(address)
        key("Enter")
    }

    /// Back on a PC screen: the browser's Back key.
    func goBack() { stream?.key(0xA6) }
    /// Reload: the stream again, with a key frame.
    func reload() { stream?.requestKeyFrame() }
}

/// The PC's name from an instance's mDNS or host name: "Mike(2)" and "MIKE screen 2" are both "Mike"'s.
enum PcScreenLogicName {
    static func pcName(_ serviceName: String) -> String {
        PcScreenPick.pcName(serviceName)
    }
}

/// A view whose sublayers (the stream's video layer) always fill it.
final class LayerFillView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.forEach { $0.frame = bounds }
        CATransaction.commit()
    }
}
