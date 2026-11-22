import Darwin
import Foundation
import PocketXRCore

/// PC screens: the Pocket XR helper words on the computer streamed from (UDP and TCP 47610), as the phone and Pocket XR
/// for Windows use them (PcHelperLink.cs): found by "POCKETXR-FIND 1", allowed once there (op pair, a Yes on that
/// computer), then it gives the host the pairing PIN for this phone (apollo-pin), says what the computer is (status),
/// and readies a virtual screen before a stream (screen-prepare). Blocking calls: run them off the main thread.
enum PcHelperLink {
    static let port: UInt16 = 47610

    struct Pc: Equatable, Sendable {
        var address: String
        var port: Int
        var name: String
        var sunshinePorts: [Int]
    }

    /// This phone's name as the computer shows it.
    static var thisName: String { "\(UIDeviceName.name) Pocket XR" }

    /// Every helper answering a broadcast within [wait] seconds, plus the computers asked directly.
    static func findAll(wait: Double = 1.5, alsoAsk: [String] = []) -> [Pc] {
        var found = [Pc]()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return found }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, socklen_t(MemoryLayout<Int32>.size))
        let ask = Array("POCKETXR-FIND 1".utf8)
        for target in ["255.255.255.255"] + alsoAsk {
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = port.bigEndian
            guard inet_pton(AF_INET, target, &a.sin_addr) == 1 else { continue }
            _ = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, ask, ask.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        let end = Date().addingTimeInterval(wait)
        var buf = [UInt8](repeating: 0, count: 1024)
        while Date() < end {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let left = Int32(max(1, end.timeIntervalSinceNow * 1000))
            guard poll(&pfd, 1, left) > 0 else { break }
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            guard n > 0 else { continue }
            var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = from.sin_addr
            inet_ntop(AF_INET, &addr, &ip, socklen_t(INET_ADDRSTRLEN))
            let address = String(cString: ip)
            if let h = here(String(decoding: buf[0..<n], as: UTF8.self)), !found.contains(where: { $0.address == address }) {
                found.append(Pc(address: address, port: h.port, name: h.name, sunshinePorts: h.ports))
            }
        }
        return found
    }

    /// "POCKETXR-HERE 1 <port> <name> [ports]": the helper's port, the computer's name, and the host ports the Linux
    /// helper lists (none from the others).
    static func here(_ text: String) -> (port: Int, name: String, ports: [Int])? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 3).map(String.init)
        guard parts.count >= 4, parts[0] == "POCKETXR-HERE" else { return nil }
        let p = Int(parts[2]) ?? Int(port)
        var name = parts[3]
        var ports = [Int]()
        if let last = name.split(separator: " ").last, last.split(separator: ",").allSatisfy({ $0.count >= 4 && $0.count <= 5 && Int($0) != nil }),
           name.contains(" ") {
            ports = last.split(separator: ",").compactMap { Int($0) }
            name = String(name.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
        }
        return (p, name, ports)
    }

    /// The helper on [host] only, asked there directly.
    static func find(at host: String) -> Pc? {
        findAll(wait: 1.2, alsoAsk: [host]).first { $0.address == host }
    }

    // MARK: Tokens: the computers that allowed this phone

    private static let tokensKey = "pcscreens.helperTokens"

    private static func tokens() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: tokensKey) as? [String: String] ?? [:]
    }

    private static func token(_ pc: Pc) -> String? { tokens()[pc.name] }

    private static func save(_ pc: Pc, _ token: String?) {
        var t = tokens()
        t[pc.name] = token
        UserDefaults.standard.set(t, forKey: tokensKey)
    }

    static func knows(_ pc: Pc) -> Bool { token(pc) != nil }

    /// One request, one line of JSON back.
    private static func ask(_ pc: Pc, _ request: [String: Any], wait: Double) -> [String: Any]? {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = UInt16(pc.port).bigEndian
        guard inet_pton(AF_INET, pc.address, &a.sin_addr) == 1 else { return nil }
        var tv = timeval(tv_sec: Int(wait), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var stv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &stv, socklen_t(MemoryLayout<timeval>.size))
        let ok = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard ok == 0, let json = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        let line = [UInt8](json) + [0x0A]
        guard send(fd, line, line.count, 0) == line.count else { return nil }
        var got = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !got.contains(0x0A) {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            got += buf[0..<n]
        }
        let text = got.split(separator: 0x0A).first.map { Data($0) } ?? Data(got)
        return (try? JSONSerialization.jsonObject(with: text)) as? [String: Any]
    }

    private static func ok(_ a: [String: Any]?) -> Bool { a?["ok"] as? Bool == true }

    /// That computer's user is asked once whether this phone may use its helper. True if allowed.
    static func pair(_ pc: Pc) -> Bool {
        let a = ask(pc, ["op": "pair", "phone": thisName], wait: 65)
        guard ok(a), let t = a?["token"] as? String, !t.isEmpty else { return false }
        save(pc, t)
        return true
    }

    /// What the helper says of its computer: its system ("", "mac", "linux", "linux-virtual") and whether it makes a
    /// virtual screen per PC screen. Nil if not allowed or no answer.
    static func hostInfo(_ pc: Pc) -> (os: String, virtual: Bool)? {
        guard let t = token(pc), let a = ask(pc, ["op": "status", "token": t], wait: 4) else { return nil }
        if !ok(a) {
            if a["why"] as? String == "not paired" { save(pc, nil) }
            return nil
        }
        return (a["os"] as? String ?? "", a["virtual"] as? Bool ?? false)
    }

    /// The helper gives [pin] to the host on HTTP port [hostPort]. Nil when it worked, else why not.
    static func givePin(_ pc: Pc, pin: String, hostPort: Int) -> String? {
        guard let t = token(pc) else { return "not paired" }
        guard let a = ask(pc, ["op": "apollo-pin", "token": t, "pin": pin, "name": thisName, "port": hostPort], wait: 50) else { return "no answer" }
        if a["why"] as? String == "not paired" { save(pc, nil) }
        return ok(a) ? nil : (a["why"] as? String ?? "refused")
    }

    /// PC VR, as the phone does it (PcVrHelper.kt): "start" starts SteamVR and lets this phone's ALVR ([alvr], its
    /// hostname) in, "status" says how SteamVR is ("off", "starting", "ready"), "idr" asks for a key frame.
    static func pcVr(_ pc: Pc, op: String, alvr: String) -> [String: Any]? {
        guard let t = token(pc) else { return nil }
        var req: [String: Any] = ["op": op, "token": t]
        if !alvr.isEmpty { req["alvr"] = alvr }
        return ask(pc, req, wait: op == "start" ? 20 : 4)
    }

    /// A Mac's or Linux's helper brings the virtual screen of the host on [hostPort] out at this size before the
    /// stream launches. True once ready.
    static func screenPrepare(_ pc: Pc, hostPort: Int, width: Int, height: Int, fps: Int) -> Bool {
        guard let t = token(pc) else { return false }
        return ok(ask(pc, ["op": "screen-prepare", "token": t, "port": hostPort, "width": width, "height": height, "fps": fps], wait: 10))
    }
}

/// The phone's name, read once on the main thread for the helper words.
enum UIDeviceName {
    nonisolated(unsafe) static var name = "iPhone"
}
