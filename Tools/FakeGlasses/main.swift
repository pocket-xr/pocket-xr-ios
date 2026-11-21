import Darwin
import Foundation
import PocketXRCore

// A stand-in for the XREAL Aura's sensor stream: listens on 127.0.0.1:52998 (or the port given) and sends IMU reports
// in the glasses' framing at 1000 Hz, turning slowly left and right. For the iOS Simulator, whose apps reach the Mac's
// localhost, so the app's probe can be run in CI without glasses. Usage: FakeGlasses [port] [seconds]

let args = CommandLine.arguments
let port = args.count > 1 ? UInt16(args[1]) ?? ImuFramer.port : ImuFramer.port
let seconds = args.count > 2 ? Double(args[2]) ?? 600 : 600

setvbuf(stdout, nil, _IOLBF, 0)
signal(SIGPIPE, SIG_IGN)

let server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
var one: Int32 = 1
setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
var addr = sockaddr_in()
addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = port.bigEndian
inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
guard bound == 0, listen(server, 4) == 0 else {
    print("FakeGlasses: cannot listen on \(port): \(String(cString: strerror(errno)))")
    exit(1)
}
print("FakeGlasses: listening on 127.0.0.1:\(port) for \(Int(seconds)) s")

let start = Date()
while Date().timeIntervalSince(start) < seconds {
    let client = accept(server, nil, nil)
    guard client >= 0 else { continue }
    print("FakeGlasses: client connected")
    var t: UInt64 = 0
    var sent = 0
    let t0 = Date()
    while Date().timeIntervalSince(start) < seconds {
        // 10 reports per 10 ms. Yaw rate swings +-0.5 rad/s with a 6 s period; gravity on the Aura's +y.
        var batch = [UInt8]()
        for _ in 0..<10 {
            t += 1_000_000
            let phase = Double(t) / 1e9 * 2 * Double.pi / 6
            let s = ImuSample(timestampNs: t, gyro: SIMD3(0, 0.5 * sin(phase), 0), accel: SIMD3(0, 9.81, 0), temperature: 30)
            batch += ImuFramer.encode(s)
        }
        let n = batch.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
        if n <= 0 { break }
        sent += 10
        let due = t0.addingTimeInterval(Double(sent) / 1000)
        let wait = due.timeIntervalSinceNow
        if wait > 0 { usleep(useconds_t(wait * 1e6)) }
    }
    close(client)
    print("FakeGlasses: client gone after \(sent) reports")
}
close(server)
