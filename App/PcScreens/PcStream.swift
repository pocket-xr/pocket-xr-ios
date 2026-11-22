import AVFoundation
import AudioToolbox
import CMoonlight1
import CMoonlight2
import CMoonlight3
import CMoonlightShared
import CoreMedia
import Foundation
import UIKit
import VideoToolbox

/// One PC screen's stream: one of the three copies of Moonlight's stream core (slot 0, 1 or 2), its video into an
/// AVSampleBufferDisplayLayer (which decodes in hardware), its sound (Opus) through Apple's own decoder.
final class PcStream: @unchecked Sendable {
    static let videoH264: Int32 = 0x0001
    static let videoH265: Int32 = 0x0100
    static let audioStereo: Int32 = (0x3 << 16) | (2 << 8) | 0xCA
    static let streamAuto: Int32 = 2
    static let encryptAll: Int32 = -1
    static let colourRec709: Int32 = 1
    static let rangeLimited: Int32 = 0
    static let buttonLeft: Int32 = 1, buttonMiddle: Int32 = 2, buttonRight: Int32 = 3

    /// The formats this device decodes in hardware, as the host is offered them.
    static var decodableFormats: Int32 {
        var f = videoH264
        if VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) { f |= videoH265 }
        return f
    }

    let slot: Int
    private let api: UnsafePointer<PXR_API>
    let videoLayer = AVSampleBufferDisplayLayer()
    /// Sound plays from PC screen 1 only, as on the phone and Windows.
    let playsSound: Bool

    enum Event {
        case stage(String)
        case started
        case terminated(Int32)
        case failed(String)
    }

    /// Called on the main queue.
    var onEvent: ((Event) -> Void)?

    // Counts for the status line and the self-test. Written on the core's threads; read roughly.
    private(set) var framesIn = 0
    private(set) var framesShown = 0
    private(set) var keyFrames = 0
    private(set) var audioPackets = 0
    private(set) var audioDecoded = 0
    private(set) var width = 0
    private(set) var height = 0
    private(set) var format: Int32 = 0

    private var formatDescription: CMVideoFormatDescription?
    private var audio: OpusPlayer?

    init(slot: Int) {
        self.slot = slot
        switch slot {
        case 0: api = pxr1_pxr_api()
        case 1: api = pxr2_pxr_api()
        default: api = pxr3_pxr_api()
        }
        playsSound = slot == 0
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = UIColor.black.cgColor
    }

    var launchQuery: String { api.pointee.launchQuery!().map { String(cString: $0) } ?? "" }

    /// Starts the stream; blocks until it is up (0) or has failed (the core's error). Run off the main thread.
    func start(address: String, appVersion: String, gfeVersion: String?, rtspSessionUrl: String?, codecSupport: Int32,
               width: Int, height: Int, fps: Int, bitrateKbps: Int, riKey: Data, riKeyId: Int32) -> Int32 {
        self.width = width
        self.height = height
        var cb = PXR_CALLBACKS()
        cb.ctx = Unmanaged.passUnretained(self).toOpaque()
        cb.stage = { ctx, kind, stage, err in
            let s = PcStream.from(ctx)
            let name = s.api.pointee.stageName!(stage).map { String(cString: $0) } ?? "\(stage)"
            let text = kind == 0 ? "starting \(name)" : kind == 1 ? "\(name) done" : "\(name) failed (\(err))"
            AppLog.line("pc screen \(s.slot + 1): \(text)")
            if kind == 2 { s.post(.failed("\(name) failed (\(err))")) } else { s.post(.stage(text)) }
        }
        cb.started = { ctx in PcStream.from(ctx).post(.started) }
        cb.terminated = { ctx, err in
            let s = PcStream.from(ctx)
            AppLog.line("pc screen \(s.slot + 1): stream ended (\(err))")
            s.post(.terminated(err))
        }
        cb.log = { ctx, msg in
            guard let msg else { return }
            AppLog.line("pc screen \(PcStream.from(ctx).slot + 1) core: \(String(cString: msg))")
        }
        cb.status = { ctx, st in AppLog.line("pc screen \(PcStream.from(ctx).slot + 1): connection \(st == 0 ? "good" : "poor")") }
        cb.videoSetup = { ctx, fmt, w, h, fps in
            let s = PcStream.from(ctx)
            s.format = fmt
            s.formatDescription = nil
            AppLog.line("pc screen \(s.slot + 1): video \(fmt & PcStream.videoH265 != 0 ? "HEVC" : "H.264") \(w)x\(h)@\(fps)")
            return 0
        }
        cb.videoFrame = { ctx, data, length, frameType, _, _ in
            guard let data else { return 0 }
            return PcStream.from(ctx).frame(UnsafeBufferPointer(start: data, count: Int(length)), keyFrame: frameType == 1)
        }
        cb.audioInit = { ctx, rate, channels, _, _, samplesPerFrame, _ in
            let s = PcStream.from(ctx)
            guard s.playsSound else { return 0 }
            s.audio = OpusPlayer(sampleRate: Double(rate), channels: Int(channels), samplesPerFrame: Int(samplesPerFrame))
            AppLog.line("pc screen \(s.slot + 1): sound \(rate) Hz, \(channels) channels, \(samplesPerFrame) a packet: \(s.audio?.ready == true ? "ready" : "no decoder")")
            return 0
        }
        cb.audioSample = { ctx, data, length in
            let s = PcStream.from(ctx)
            s.audioPackets += 1
            guard let data, let a = s.audio else { return }
            if a.play(UnsafeBufferPointer(start: data, count: Int(length))) { s.audioDecoded += 1 }
        }
        let fpsX100 = Int32(fps * 100)
        return address.withCString { a in
            appVersion.withCString { v in
                (gfeVersion ?? "").withCString { g in
                    (rtspSessionUrl ?? "").withCString { r in
                        riKey.withUnsafeBytes { k in
                            api.pointee.start!(a, v, gfeVersion == nil ? nil : g, rtspSessionUrl == nil ? nil : r, codecSupport,
                                              Int32(width), Int32(height), Int32(fps), Int32(bitrateKbps), 1392, Self.streamAuto,
                                              Self.audioStereo, Self.decodableFormats, fpsX100,
                                              k.bindMemory(to: UInt8.self).baseAddress, riKeyId, Self.encryptAll,
                                              Self.colourRec709, Self.rangeLimited, 0, &cb)
                        }
                    }
                }
            }
        }
    }

    func stop() {
        api.pointee.stop!()
        audio?.stop()
        audio = nil
    }

    private static func from(_ ctx: UnsafeMutableRawPointer?) -> PcStream {
        Unmanaged<PcStream>.fromOpaque(ctx!).takeUnretainedValue()
    }

    private func post(_ e: Event) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(e) }
    }

    // MARK: Video

    /// One whole frame in Annex B: parameter sets (on key frames) make the format; the rest is shown at once.
    private func frame(_ data: UnsafeBufferPointer<UInt8>, keyFrame: Bool) -> Int32 {
        framesIn += 1
        let hevc = format & Self.videoH265 != 0
        var params = [Data]()
        var sample = Data()
        for r in Self.nals(data) {
            guard r.count > 0 else { continue }
            let first = data[r.lowerBound]
            let type = hevc ? Int((first >> 1) & 0x3F) : Int(first & 0x1F)
            let isParam = hevc ? (type == 32 || type == 33 || type == 34) : (type == 7 || type == 8)
            let nal = Data(data[r])
            if isParam {
                params.append(nal)
            } else {
                var len = UInt32(nal.count).bigEndian
                sample.append(Data(bytes: &len, count: 4))
                sample.append(nal)
            }
        }
        if keyFrame { keyFrames += 1 }
        if !params.isEmpty, let fd = Self.makeFormat(params, hevc: hevc) {
            formatDescription = fd
        }
        guard let fd = formatDescription else { return -1 } // no parameter sets yet: ask for a key frame
        guard !sample.isEmpty, let sb = Self.sampleBuffer(sample, format: fd) else { return 0 }
        let renderer = videoLayer.sampleBufferRenderer
        if renderer.status == .failed {
            AppLog.line("pc screen \(slot + 1): the video layer failed (\(String(describing: renderer.error))): asking for a key frame")
            renderer.flush()
            return -1
        }
        renderer.enqueue(sb)
        framesShown += 1
        return 0
    }

    /// The NAL units of an Annex B buffer (start codes left out).
    static func nals(_ d: UnsafeBufferPointer<UInt8>) -> [Range<Int>] {
        var starts = [(code: Int, data: Int)]()
        var i = 0
        let n = d.count
        while i + 2 < n {
            if d[i] == 0 && d[i + 1] == 0 && d[i + 2] == 1 {
                starts.append((code: i > 0 && d[i - 1] == 0 ? i - 1 : i, data: i + 3))
                i += 3
            } else {
                i += 1
            }
        }
        var out = [Range<Int>]()
        for (k, s) in starts.enumerated() {
            let end = k + 1 < starts.count ? starts[k + 1].code : n
            if end > s.data { out.append(s.data..<end) }
        }
        return out
    }

    private static func makeFormat(_ params: [Data], hevc: Bool) -> CMVideoFormatDescription? {
        var out: CMVideoFormatDescription?
        let ptrs = params.map { p -> UnsafeMutablePointer<UInt8> in
            let m = UnsafeMutablePointer<UInt8>.allocate(capacity: p.count)
            p.copyBytes(to: m, count: p.count)
            return m
        }
        defer { ptrs.forEach { $0.deallocate() } }
        let pointers = ptrs.map { UnsafePointer($0) }
        let sizes = params.map { $0.count }
        let status: OSStatus
        if hevc {
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: params.count,
                                                                         parameterSetPointers: pointers, parameterSetSizes: sizes,
                                                                         nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &out)
        } else {
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: params.count,
                                                                         parameterSetPointers: pointers, parameterSetSizes: sizes,
                                                                         nalUnitHeaderLength: 4, formatDescriptionOut: &out)
        }
        if status != noErr { AppLog.line("pc screens: video format from the parameter sets failed (\(status))") }
        return out
    }

    private static func sampleBuffer(_ data: Data, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block else { return nil }
        let copied = data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count) }
        guard copied == noErr else { return nil }
        var sb: CMSampleBuffer?
        var size = data.count
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sb) == noErr, let sb else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sb
    }

    // MARK: Input

    func mousePosition(x: Int, y: Int, refWidth: Int, refHeight: Int) {
        _ = api.pointee.mousePosition!(Int16(clamping: x), Int16(clamping: y), Int16(clamping: max(refWidth, 1)), Int16(clamping: max(refHeight, 1)))
    }
    func mouseButton(_ button: Int32, down: Bool) { _ = api.pointee.mouseButton!(down ? 1 : 0, button) }
    func scroll(_ amount: Int) { _ = api.pointee.scroll!(Int16(clamping: amount)) }
    func hscroll(_ amount: Int) { _ = api.pointee.hscroll!(Int16(clamping: amount)) }
    /// A Windows virtual-key code, down then up.
    func key(_ vk: Int, modifiers: Int32 = 0) {
        let code = Int16(truncatingIfNeeded: 0x8000 | (vk & 0xFF))
        _ = api.pointee.key!(code, 1, modifiers)
        _ = api.pointee.key!(code, 0, modifiers)
    }
    func text(_ s: String) {
        let b = Array(s.utf8)
        b.withUnsafeBufferPointer { p in
            p.baseAddress?.withMemoryRebound(to: CChar.self, capacity: b.count) { _ = api.pointee.text!($0, UInt32(b.count)) }
        }
    }
    func requestKeyFrame() { api.pointee.requestIdr!() }
}

/// Opus packets to the speaker: Apple's own Opus decoder (AVAudioConverter) into an AVAudioEngine player.
final class OpusPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let opus: AVAudioFormat
    private let pcm: AVAudioFormat
    private let converter: AVAudioConverter
    private let samplesPerFrame: Int
    private var failures = 0
    private(set) var ready = false

    init?(sampleRate: Double, channels: Int, samplesPerFrame: Int) {
        var input = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
                                                mFramesPerPacket: UInt32(samplesPerFrame), mBytesPerFrame: 0,
                                                mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        guard let o = AVAudioFormat(streamDescription: &input),
              let p = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false),
              let c = AVAudioConverter(from: o, to: p) else {
            AppLog.line("pc screens: no Opus decoder for \(sampleRate) Hz, \(channels) channels")
            return nil
        }
        opus = o
        pcm = p
        converter = c
        self.samplesPerFrame = samplesPerFrame
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: p)
            try engine.start()
            player.play()
            ready = true
        } catch {
            AppLog.line("pc screens: sound could not start: \(error)")
        }
    }

    /// Decodes one packet and queues it. True if it decoded.
    func play(_ data: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = data.baseAddress, data.count > 0 else { return false }
        let packet = AVAudioCompressedBuffer(format: opus, packetCapacity: 1, maximumPacketSize: data.count)
        packet.data.copyMemory(from: base, byteCount: data.count)
        packet.byteLength = UInt32(data.count)
        packet.packetCount = 1
        packet.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                          mDataByteSize: UInt32(data.count))
        guard let out = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(max(samplesPerFrame, 960))) else { return false }
        var given = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if given {
                inputStatus.pointee = .noDataNow
                return nil
            }
            given = true
            inputStatus.pointee = .haveData
            return packet
        }
        guard status != .error, out.frameLength > 0 else {
            failures += 1
            if failures <= 3 || failures % 500 == 0 {
                AppLog.line("pc screens: an Opus packet of \(data.count) bytes did not decode (status \(status.rawValue), \(out.frameLength) frames, \(String(describing: error))), \(failures) so far")
            }
            return false
        }
        if ready { player.scheduleBuffer(out, completionHandler: nil) }
        return true
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}
