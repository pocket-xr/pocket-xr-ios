import AVFoundation
import Photos
import UIKit

/// Record: a video of what the glasses show (the Space), saved to Photos. Each frame is a snapshot of the Space's view
/// at up to 30 a second, written as H.264 at the view's own size (1080p on the glasses), as Android's Record makes a
/// clean 1080p video. Snapshots include web pages and PC screens; whether the snapshot keeps up at 30 a second on a
/// phone is untested.
@MainActor
final class Recorder {
    static let shared = Recorder()

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0
    private weak var view: UIView?
    private var size = CGSize.zero
    private(set) var recording = false
    private(set) var frames = 0
    private(set) var lastFile: URL?
    var onChange: (() -> Void)?

    /// Starts recording [view]. False if it could not.
    @discardableResult
    func begin(_ view: UIView) -> Bool {
        guard !recording, view.bounds.width > 0 else { return false }
        // Even sizes, at most 1920 wide, the view's shape kept.
        let scale = min(1, 1920 / view.bounds.width)
        let w = Int(view.bounds.width * scale) / 2 * 2, h = Int(view.bounds.height * scale) / 2 * 2
        size = CGSize(width: w, height: h)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pocket XR \(Self.stamp()).mp4")
        do {
            let wr = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
            ])
            inp.expectsMediaDataInRealTime = true
            let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h, kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ])
            wr.add(inp)
            guard wr.startWriting() else { AppLog.line("record: could not start: \(String(describing: wr.error))"); return false }
            wr.startSession(atSourceTime: .zero)
            writer = wr
            input = inp
            adaptor = ad
        } catch {
            AppLog.line("record: could not start: \(error)")
            return false
        }
        self.view = view
        frames = 0
        start = CACurrentMediaTime()
        lastFrame = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
        recording = true
        lastFile = url
        AppLog.line("record: started, \(w)x\(h)")
        onChange?()
        return true
    }

    @objc private func tick(_ l: CADisplayLink) {
        guard recording, let view, let input, let adaptor, input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        let now = l.timestamp
        guard now - lastFrame >= 1.0 / 31 else { return }
        lastFrame = now
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let pb else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
        UIGraphicsPopContext()
        let t = CMTime(seconds: now - start, preferredTimescale: 600)
        if adaptor.append(pb, withPresentationTime: t) { frames += 1 }
    }

    /// Stops and saves to Photos (unless [toPhotos] is false). Calls [done] with the file, or nil if nothing was made.
    func end(toPhotos: Bool = true, done: ((URL?) -> Void)? = nil) {
        guard recording, let writer, let input else { done?(nil); return }
        recording = false
        link?.invalidate()
        link = nil
        input.markAsFinished()
        let url = writer.outputURL
        let made = frames
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let ok = writer.status == .completed && made > 0
                    AppLog.line("record: stopped, \(made) frames, \(ok ? "saved" : "failed: \(String(describing: writer.error))")")
                    self?.writer = nil
                    self?.input = nil
                    self?.adaptor = nil
                    self?.onChange?()
                    if ok && toPhotos { Self.saveToPhotos(url) }
                    done?(ok ? url : nil)
                }
            }
        }
    }

    private static func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                AppLog.line("record: Photos not allowed; the video stays in the app's files")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { ok, error in
                AppLog.line("record: \(ok ? "saved to Photos" : "Photos refused it: \(String(describing: error))")")
            }
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
