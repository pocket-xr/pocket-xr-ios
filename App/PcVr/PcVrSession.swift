import AVFoundation
import CoreMedia
import Foundation
import GameController
import PocketXRCore
import UIKit
#if canImport(PXRAlvrLink)
import CAlvr
import PXRAlvrLink
#endif

/// PC VR: SteamVR games from a Windows PC, through ALVR (the same version as Pocket XR for Android: 21.0.0-dev14, with
/// the streamer the Pocket XR PC helper installs). The picture is drawn full screen on the glasses, one half per eye;
/// the head pose is the Space's head tracking; Joy-Cons (or any game controller) are the two hands. As Android does it
/// (pocketxr_alvr.cpp, PcVrRenderer.kt), except that iOS has no ALVR decoder: ALVR hands this app the video and
/// VideoToolbox (an AVSampleBufferDisplayLayer) decodes it, and there is no late rotation warp yet.
///
/// Untested end to end: it needs SteamVR on a PC, the glasses' head tracking on an iPhone (phase 0's open question),
/// and the glasses in 3D (side by side).
@MainActor
final class PcVrSession: ObservableObject {
    static let shared = PcVrSession()

    @Published private(set) var active = false
    @Published private(set) var state = ""
    /// The picture: ALVR's video, decoded and shown by a sample buffer layer (thread safe: ALVR calls it on its own thread).
    let video = PcVrVideo()
    var videoLayer: AVSampleBufferDisplayLayer { video.layer }
    /// The glasses should be in 3D while PC VR runs (both eyes differ). Read by the glasses' control link.
    nonisolated(unsafe) static var wants3D = false

    /// Whether this build has ALVR's client core linked.
    static var available: Bool {
        #if canImport(PXRAlvrLink)
        return pxr_alvr_linked() == 1
        #else
        return false
        #endif
    }

    private var link: CADisplayLink?
    private var helper: PcHelperLink.Pc?
    private var leaveHeldSince: Double?
    private init() {}

    private func say(_ s: String) {
        state = s
        AppLog.line("pc vr: \(s)")
    }

    // MARK: Opening and closing

    func open() {
        guard !active else { return }
        guard Self.available else { say(L("PC VR is not in this build.")); return }
        active = true
        Self.wants3D = true
        GlassesControl.shared.apply()
        SpaceController.shared.pcVrChanged()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        startAlvr()
        say(L("Looking for your PC…"))
        Task { await startSteamVr() }
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func close() {
        guard active else { return }
        link?.invalidate()
        link = nil
        stopAlvr()
        video.reset(hevc: false)
        active = false
        Self.wants3D = false
        GlassesControl.shared.apply()
        SpaceController.shared.pcVrChanged()
        say("")
    }

    /// The Pocket XR PC helper starts SteamVR and lets this phone's ALVR in (ops start and status, as on Android).
    private func startSteamVr() async {
        let host = alvrHostname()
        let found = await Task.detached { PcHelperLink.findAll().first }.value
        guard let pc = found else {
            say(L("No PC found. Install the Pocket XR PC helper on your Windows PC (once), with Steam and SteamVR."))
            return
        }
        helper = pc
        if !PcHelperLink.knows(pc) {
            say(String(format: L("On %@, say Yes to let this phone show it (once)."), pc.name))
            guard await Task.detached(operation: { PcHelperLink.pair(pc) }).value else {
                say(String(format: L("%@ did not allow this phone."), pc.name))
                return
            }
        }
        var last = ""
        for _ in 0..<90 {
            guard active else { return }
            let answer = await Task.detached { PcHelperLink.pcVr(pc, op: "start", alvr: host) }.value
            let steam = answer?["steamvr"] as? String ?? "no answer"
            if steam != last { AppLog.line("pc vr: \(pc.name) says SteamVR \(steam)") }
            last = steam
            switch steam {
            case "ready":
                say(String(format: L("Connecting to SteamVR on %@…"), pc.name))
                return
            case "starting":
                say(String(format: L("SteamVR is starting on %@…"), pc.name))
            default:
                say(String(format: L("%@ could not start SteamVR (%@)."), pc.name, steam))
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    // MARK: ALVR

    #if canImport(PXRAlvrLink)
    private var headId: UInt64 = 0
    private var handIds: (UInt64, UInt64) = (0, 0)
    private var buttonIds = [String: UInt64]()
    private var lastButtons = [String: Float]()
    private var streaming = false

    private func id(_ path: String) -> UInt64 { path.withCString { alvr_path_string_to_id($0) } }

    private func alvrHostname() -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = alvr_hostname(&buf)
        return n > 0 ? String(cString: buf) : ""
    }

    private func startAlvr() {
        alvr_initialize_logging()
        // Per eye 2144 x 1216 at 60 Hz, as on Android: another rate makes ALVR restart SteamVR.
        var rates: [Float] = [60]
        rates.withUnsafeBufferPointer { r in
            var caps = AlvrClientCapabilities()
            caps.default_view_width = 2144
            caps.default_view_height = 1216
            caps.max_view_width = 2144
            caps.max_view_height = 1216
            caps.refresh_rates = r.baseAddress
            caps.refresh_rates_count = 1
            caps.foveated_encoding = false
            caps.encoder_high_profile = true
            caps.encoder_10_bits = false
            caps.encoder_av1 = false
            caps.prefer_10bit = false
            caps.preferred_encoding_gamma = 1
            caps.prefer_hdr = false
            alvr_initialize(caps)
        }
        _ = rates
        alvr_resume()
        headId = id("/user/head")
        handIds = (id("/user/hand/left"), id("/user/hand/right"))
        video.onBroken = { [weak self] in
            if let pc = self?.helper { Task.detached { _ = PcHelperLink.pcVr(pc, op: "idr", alvr: "") } }
        }
        alvr_set_decoder_input_callback(Unmanaged.passUnretained(video).toOpaque()) { data in
            guard let ctx = data.callback_context, let ptr = data.buffer_ptr, data.buffer_size > 0 else { return true }
            let v = Unmanaged<PcVrVideo>.fromOpaque(ctx).takeUnretainedValue()
            v.frame(UnsafeBufferPointer(start: ptr, count: Int(data.buffer_size)), timestampNs: data.timestamp_ns)
            return true
        }
        AppLog.line("pc vr: ALVR started, this phone is \(alvrHostname())")
    }

    private func stopAlvr() {
        alvr_pause()
        alvr_destroy()
        streaming = false
        video.reset(hevc: false)
    }

    /// The view the PC draws for each eye: the glasses' field, 6 % wider (as on Android), eyes ±IPD/2 apart.
    private func sendViews() {
        let tanY = tan(GlassesOptics.auraFovYDeg / 2 * .pi / 180) * 1.06
        let tanX = tanY * 16 / 9
        let fov = AlvrFov(left: Float(-atan(tanX)), right: Float(atan(tanX)), up: Float(atan(tanY)), down: Float(-atan(tanY)))
        let ipd: Float = 0.063
        var views = [
            AlvrViewParams(pose: AlvrPose(orientation: AlvrQuat(x: 0, y: 0, z: 0, w: 1), position: (-ipd / 2, 0, 0)), fov: fov),
            AlvrViewParams(pose: AlvrPose(orientation: AlvrQuat(x: 0, y: 0, z: 0, w: 1), position: (ipd / 2, 0, 0)), fov: fov),
        ]
        views.withUnsafeMutableBufferPointer { alvr_send_view_params($0.baseAddress) }
    }

    /// Each hand is an Oculus Touch controller, as on Android: these inputs, sent once.
    private static let inputs = [
        "left": ["x/click", "x/touch", "y/click", "y/touch", "menu/click", "squeeze/value", "trigger/value", "trigger/touch",
                 "thumbstick/x", "thumbstick/y", "thumbstick/click", "thumbstick/touch", "thumbrest/touch"],
        "right": ["a/click", "a/touch", "b/click", "b/touch", "system/click", "squeeze/value", "trigger/value", "trigger/touch",
                  "thumbstick/x", "thumbstick/y", "thumbstick/click", "thumbstick/touch", "thumbrest/touch"],
    ]

    private func sendProfile() {
        let profile = id("/interaction_profiles/oculus/touch_controller")
        for (hand, list) in Self.inputs {
            let ids = list.map { id("/user/hand/\(hand)/input/\($0)") }
            for (name, i) in zip(list, ids) { buttonIds["\(hand)/\(name)"] = i }
            ids.withUnsafeBufferPointer { p in
                alvr_send_active_interaction_profile(hand == "left" ? handIds.0 : handIds.1, profile, p.baseAddress, UInt64(ids.count))
            }
        }
    }

    private func pollEvents() {
        var e = AlvrEvent()
        while alvr_poll_event(&e) {
            switch e.tag {
            case 1: // ALVR_EVENT_STREAMING_STARTED
                streaming = true
                video.reset(hevc: false)
                sendViews()
                sendProfile()
                say(L("PC VR"))
            case 2: // ALVR_EVENT_STREAMING_STOPPED
                streaming = false
                say(L("The stream stopped. Waiting for SteamVR…"))
            case 4: // ALVR_EVENT_DECODER_CONFIG
                let hevc = e.DECODER_CONFIG.codec == 1 // ALVR_CODEC_TYPE_HEVC
                video.reset(hevc: hevc)
                var buf = [CChar](repeating: 0, count: 64 * 1024)
                let n = Int(alvr_get_decoder_config(&buf))
                if n > 0 {
                    let bytes = buf.prefix(n).map { UInt8(bitPattern: $0) }
                    bytes.withUnsafeBufferPointer { video.frame($0, timestampNs: 0) }
                }
                AppLog.line("pc vr: decoder \(hevc ? "HEVC" : "H.264"), \(n) bytes of parameter sets")
            default:
                break
            }
        }
    }

    /// The head and both hands, predicted as far ahead as ALVR's pipeline is long.
    private func sendTracking() {
        let offset = min(max(alvr_get_total_prediction_offset_ns(), 1), 150_000_000)
        let target = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + (offset > 1 ? offset : 60_000_000)
        let q = SpaceController.shared.head
        let headQ = AlvrQuat(x: Float(q.x), y: Float(q.y), z: Float(q.z), w: Float(q.w))
        var motions = [AlvrDeviceMotion(device_id: headId, pose: AlvrPose(orientation: headQ, position: (0, 1.6, 0)),
                                        linear_velocity: (0, 0, 0), angular_velocity: (0, 0, 0))]
        if GCController.controllers().contains(where: { $0.extendedGamepad != nil }) {
            // Held in front of the body, turned with the head's heading (Joy-Cons have no position).
            let yaw = Quat.aboutY(q.yaw)
            for (side, hid) in [(-0.18, handIds.0), (0.18, handIds.1)] {
                let p = yaw.rotate(SIMD3(side, -0.35, -0.35))
                let o = AlvrQuat(x: Float(yaw.x), y: Float(yaw.y), z: Float(yaw.z), w: Float(yaw.w))
                motions.append(AlvrDeviceMotion(device_id: hid, pose: AlvrPose(orientation: o, position: (Float(p.x), Float(1.6 + p.y), Float(p.z))),
                                                linear_velocity: (0, 0, 0), angular_velocity: (0, 0, 0)))
            }
        }
        motions.withUnsafeBufferPointer { alvr_send_tracking(target, $0.baseAddress, UInt64($0.count), nil, nil) }
    }

    /// A game controller (two Joy-Cons together, or any gamepad) as both hands, by position, as Android maps Joy-Cons.
    private func sendButtons(now: Double) {
        guard let pad = GCController.controllers().compactMap({ $0.extendedGamepad }).first else { return }
        var values: [String: Float] = [
            "left/x/click": pad.buttonX.value, "left/y/click": pad.buttonY.value, "left/menu/click": pad.buttonOptions?.value ?? 0,
            "left/squeeze/value": pad.leftShoulder.value, "left/trigger/value": pad.leftTrigger.value,
            "left/thumbstick/x": pad.leftThumbstick.xAxis.value, "left/thumbstick/y": pad.leftThumbstick.yAxis.value,
            "left/thumbstick/click": pad.leftThumbstickButton?.value ?? 0,
            "right/a/click": pad.buttonA.value, "right/b/click": pad.buttonB.value, "right/system/click": pad.buttonMenu.value,
            "right/squeeze/value": pad.rightShoulder.value, "right/trigger/value": pad.rightTrigger.value,
            "right/thumbstick/x": pad.rightThumbstick.xAxis.value, "right/thumbstick/y": pad.rightThumbstick.yAxis.value,
            "right/thumbstick/click": pad.rightThumbstickButton?.value ?? 0,
        ]
        // Touches follow presses; the thumb rests when nothing is touched.
        for hand in ["left", "right"] {
            let pressed = values.filter { $0.key.hasPrefix(hand) && $0.key.hasSuffix("/click") && $0.value > 0.5 }
            for (k, v) in pressed { values[k.replacingOccurrences(of: "/click", with: "/touch")] = v }
            values["\(hand)/trigger/touch"] = (values["\(hand)/trigger/value"] ?? 0) > 0.05 ? 1 : 0
            let stick = abs(values["\(hand)/thumbstick/x"] ?? 0) + abs(values["\(hand)/thumbstick/y"] ?? 0)
            values["\(hand)/thumbstick/touch"] = stick > 0.1 ? 1 : 0
            values["\(hand)/thumbrest/touch"] = pressed.isEmpty && stick <= 0.1 ? 1 : 0
        }
        for (k, v) in values where lastButtons[k] != v {
            guard let pid = buttonIds[k] else { continue }
            lastButtons[k] = v
            var value = AlvrButtonValue()
            if k.hasSuffix("/value") || k.contains("thumbstick/x") || k.contains("thumbstick/y") {
                value.tag = ALVR_BUTTON_VALUE_SCALAR
                value.scalar = v
            } else {
                value.tag = ALVR_BUTTON_VALUE_BINARY
                value.binary = v > 0.5
            }
            alvr_send_button(pid, value)
        }
        // Back to the Space: hold the controller's Home (or menu) button for 2 seconds, as on Android.
        let home = (pad.buttonHome?.isPressed ?? false) || pad.buttonMenu.isPressed && pad.buttonOptions?.isPressed == true
        if home {
            if leaveHeldSince == nil { leaveHeldSince = now }
            if now - (leaveHeldSince ?? now) >= 2 { close() }
        } else {
            leaveHeldSince = nil
        }
    }

    @objc private func frame(_ l: CADisplayLink) {
        pollEvents()
        if streaming {
            sendTracking()
            sendButtons(now: l.timestamp)
        }
    }
    #else
    private func alvrHostname() -> String { "" }
    private func startAlvr() {}
    private func stopAlvr() {}
    @objc private func frame(_ l: CADisplayLink) {}
    #endif

    /// For the self-test: ALVR starts, says this phone's name and its service, and stops again.
    static func selfTest() -> (hostname: String, service: String) {
        #if canImport(PXRAlvrLink)
        var caps = AlvrClientCapabilities()
        var rates: [Float] = [60]
        let made: (String, String) = rates.withUnsafeMutableBufferPointer { r in
            caps.default_view_width = 2144
            caps.default_view_height = 1216
            caps.max_view_width = 2144
            caps.max_view_height = 1216
            caps.refresh_rates = UnsafePointer(r.baseAddress)
            caps.refresh_rates_count = 1
            caps.preferred_encoding_gamma = 1
            alvr_initialize(caps)
            var h = [CChar](repeating: 0, count: 256)
            var s = [CChar](repeating: 0, count: 256)
            let hn = alvr_hostname(&h), sn = alvr_mdns_service(&s)
            alvr_resume()
            alvr_pause()
            alvr_destroy()
            return (hn > 0 ? String(cString: h) : "", sn > 0 ? String(cString: s) : "")
        }
        return made
        #else
        return ("", "")
        #endif
    }
}

/// PC VR's picture: frames from ALVR (NAL units, called on ALVR's thread) into a sample buffer layer that decodes in
/// hardware and shows them at once; ALVR is told each was decoded and shown, for its timing.
final class PcVrVideo: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()
    private let lock = NSLock()
    private var format: CMVideoFormatDescription?
    private var hevc = false
    private(set) var framesIn = 0
    private(set) var framesShown = 0
    /// Called (on ALVR's thread) when the layer failed and a key frame is needed.
    var onBroken: (() -> Void)?

    init() {
        layer.videoGravity = .resize
        layer.backgroundColor = UIColor.black.cgColor
    }

    func reset(hevc: Bool) {
        lock.lock()
        self.hevc = hevc
        format = nil
        lock.unlock()
        layer.sampleBufferRenderer.flush()
    }

    func frame(_ data: UnsafeBufferPointer<UInt8>, timestampNs: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        framesIn += 1
        var params = [Data]()
        var sample = Data()
        for r in PcStream.nals(data) {
            guard r.count > 0 else { continue }
            let first = data[r.lowerBound]
            let type = hevc ? Int((first >> 1) & 0x3F) : Int(first & 0x1F)
            let isParam = hevc ? (32...34).contains(type) : (type == 7 || type == 8)
            let nal = Data(data[r])
            if isParam {
                params.append(nal)
            } else {
                var len = UInt32(nal.count).bigEndian
                sample.append(Data(bytes: &len, count: 4))
                sample.append(nal)
            }
        }
        if !params.isEmpty, let f = PcStream.makeFormat(params, hevc: hevc) { format = f }
        guard let format, !sample.isEmpty, let sb = PcStream.sampleBuffer(sample, format: format) else { return }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
            onBroken?()
            return
        }
        renderer.enqueue(sb)
        framesShown += 1
        #if canImport(PXRAlvrLink)
        if timestampNs > 0 {
            alvr_report_frame_decoded(timestampNs)
            var meta = AlvrVideoFrameMetadata()
            _ = alvr_report_compositor_start(timestampNs, &meta)
            alvr_report_submit(timestampNs, 0)
        }
        #endif
    }
}
