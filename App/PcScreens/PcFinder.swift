import Foundation
import Network

/// PC screens: computers on the local network that announce Moonlight's service (_nvstream._tcp): Pocket XR's
/// computer side, Apollo and Sunshine all do. Each found service is opened once to learn its address and port.
enum PcFinder {
    struct Found: Equatable, Sendable {
        var name: String
        var host: String
        var port: Int
    }

    /// Every service found within [seconds].
    static func browse(seconds: Double = 2) async -> [Found] {
        let browser = NWBrowser(for: .bonjour(type: "_nvstream._tcp", domain: nil), using: .tcp)
        let box = Box()
        browser.browseResultsChangedHandler = { results, _ in box.set(Array(results)) }
        browser.start(queue: .global())
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        browser.cancel()
        var out = [Found]()
        for r in box.get() {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            if let at = await resolve(r.endpoint), !out.contains(where: { $0.host == at.0 && $0.port == at.1 }) {
                out.append(Found(name: name, host: at.0, port: at.1))
            }
        }
        return out
    }

    /// The IPv4 address and port behind a service, by opening it.
    private static func resolve(_ endpoint: NWEndpoint) async -> (String, Int)? {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        let result: (String, Int)? = await withCheckedContinuation { cont in
            let once = Once()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(h, p) = c.currentPath?.remoteEndpoint {
                        var host = "\(h)"
                        if let pct = host.firstIndex(of: "%") { host = String(host[..<pct]) }
                        once.run { cont.resume(returning: (host, Int(p.rawValue))) }
                    } else {
                        once.run { cont.resume(returning: nil) }
                    }
                case .failed, .cancelled:
                    once.run { cont.resume(returning: nil) }
                default:
                    break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { once.run { cont.resume(returning: nil) } }
        }
        c.cancel()
        return result
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var results = [NWBrowser.Result]()
        func set(_ r: [NWBrowser.Result]) { lock.lock(); results = r; lock.unlock() }
        func get() -> [NWBrowser.Result] { lock.lock(); defer { lock.unlock() }; return results }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ f: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { f() }
        }
    }
}
