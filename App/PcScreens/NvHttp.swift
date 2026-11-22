import Foundation
import PocketXRCore
import Security

/// The host's answer was an error: an HTTP status, or a status_code other than 200 in its XML.
struct HostError: Error, CustomStringConvertible {
    var code: Int
    var message: String
    var description: String { "host said \(code) \(message)".trimmingCharacters(in: .whitespaces) }
}

/// PC screens: the host's web side (Pocket XR on a computer, Apollo or Sunshine; GameStream's protocol): serverinfo,
/// pairing, the app list, launch, resume and cancel. Ported from Pocket XR for Windows' NvHttp.cs, itself from
/// moonlight-android's NvHTTP and PairingManager (GPLv3).
final class NvHttp: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    let httpPort: Int
    var httpsPort: Int
    /// The host's certificate pinned when this phone paired; HTTPS to the host must present exactly this.
    private(set) var serverCert: Data?
    private let id: PcIdentity

    init(host: String, httpPort: Int, httpsPort: Int, serverCert: Data?, identity: PcIdentity) {
        self.host = host
        self.httpPort = httpPort
        self.httpsPort = httpsPort
        self.serverCert = serverCert
        self.id = identity
    }

    private var hostInUrl: String { host.contains(":") ? "[\(host)]" : host }

    /// One request on a session of its own: no TLS session is resumed (Apollo refuses a resumed session with a client
    /// certificate, seen by Pocket XR for Windows on 20 Nov 2026).
    private func fetch(_ url: URL, timeout: Double) async throws -> (Int, String) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout > 0 ? timeout : 600
        config.timeoutIntervalForResource = timeout > 0 ? timeout : 600
        config.urlCache = nil
        config.tlsMaximumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    private func url(_ secure: Bool, _ path: String, _ query: String?) -> URL {
        let base = secure ? "https://\(hostInUrl):\(httpsPort)/" : "http://\(hostInUrl):\(httpPort)/"
        let q = (query.map { $0.isEmpty ? "" : $0 + "&" } ?? "") + "uniqueid=\(id.uniqueId)&uuid=\(UUID().uuidString)"
        return URL(string: base + path + "?" + q)!
    }

    private func get(_ secure: Bool, _ path: String, _ query: String? = nil, timeout: Double = 10) async throws -> String {
        let (status, body) = try await fetch(url(secure, path, query), timeout: timeout)
        if status < 200 || status > 299 { throw HostError(code: status, message: HTTPURLResponse.localizedString(forStatusCode: status)) }
        let (code, message) = PcScreenXml.status(body)
        if code != 200 && code != 0 { throw HostError(code: code, message: message) }
        return body
    }

    // MARK: TLS: the host's pinned certificate, and this phone's client certificate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = space.serverTrust, let pinned = serverCert,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
                  SecCertificateCopyData(leaf) as Data == pinned else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
        case NSURLAuthenticationMethodClientCertificate:
            guard let identity = id.identity else {
                AppLog.line("pc screens: the host asks for this phone's certificate and the keychain has none")
                completionHandler(.performDefaultHandling, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(identity: identity, certificates: nil, persistence: .forSession))
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: Calls

    /// The host's serverinfo: over HTTPS when paired (only then does it say PairStatus 1), else plain HTTP.
    func serverInfo(timeout: Double = 5) async throws -> String {
        if serverCert != nil {
            if httpsPort <= 0 { httpsPort = Self.httpsPort(of: try await get(false, "serverinfo", timeout: timeout)) }
            do {
                return try await get(true, "serverinfo", timeout: timeout)
            } catch let e as HostError where e.code == 401 {
                AppLog.line("pc screens: \(host):\(httpsPort) over HTTPS: \(e)")
            } catch let e as URLError where e.code == .cancelled || e.code == .serverCertificateUntrusted {
                AppLog.line("pc screens: \(host):\(httpsPort): the host's certificate changed")
            }
        }
        return try await get(false, "serverinfo", timeout: timeout)
    }

    static func httpsPort(of serverInfo: String) -> Int {
        Int(PcScreenXml.value(serverInfo, "HttpsPort") ?? "").flatMap { $0 > 0 ? $0 : nil } ?? 47984
    }

    func appList() async throws -> String { try await get(true, "applist") }

    /// Launch (or resume) the app at this size. Returns the RTSP session URL the host gave (nil from older hosts).
    func launch(_ verb: String, appId: Int, width: Int, height: Int, fps: Int, riKey: Data, riKeyId: Int32,
                virtualDisplay: Bool, localAudio: Bool, surroundAudioInfo: Int, coreQuery: String) async throws -> String? {
        let query = "appid=\(appId)&mode=\(width)x\(height)x\(fps)&additionalStates=1&sops=0"
            + "&rikey=\(PcScreenXml.hex(riKey))&rikeyid=\(riKeyId)&localAudioPlayMode=\(localAudio ? 1 : 0)"
            + "&virtualDisplay=\(virtualDisplay ? 1 : 0)&surroundAudioInfo=\(surroundAudioInfo)"
            + "&remoteControllersBitmap=0&gcmap=0&gcpersist=0" + coreQuery
        let xml = try await get(true, verb, query, timeout: 60)
        let ok = PcScreenXml.value(xml, verb == "launch" ? "gamesession" : "resume")
        if ok == nil || ok == "0" { throw HostError(code: 0, message: "the host refused to \(verb) the app") }
        return PcScreenXml.value(xml, "sessionUrl0")
    }

    /// Ends the host's session, so the host removes the session's virtual display.
    func quit() async throws { _ = try await get(true, "cancel") }

    private func unpair() async { _ = try? await get(false, "unpair", timeout: 5) }

    enum PairState: String { case paired, pinWrong, failed, alreadyInProgress }

    /// Pairs with the host using [pin], which the user (or the Pocket XR helper on that computer) gives the host
    /// while this waits. On success, `serverCert` is the host's certificate, to be saved.
    func pair(serverInfo: String, pin: String) async throws -> PairState {
        let sha256 = PcScreenXml.majorVersion(serverInfo) >= 7
        let hashLen = sha256 ? 32 : 20
        func hash(_ d: Data) -> Data { sha256 ? PcCrypto.sha256(d) : PcCrypto.sha1(d) }
        if httpsPort <= 0 { httpsPort = Self.httpsPort(of: serverInfo) }

        let salt = PcCrypto.random(16)
        let aesKey = hash(salt + Data(pin.utf8)).prefix(16)

        // The host answers only once the PIN has been given there: a long wait.
        let getCert = try await pairStep(false, "phrase=getservercert&salt=\(PcScreenXml.hex(salt))&clientcert=\(PcScreenXml.hex(id.pemCert))", timeout: 0)
        guard PcScreenXml.value(getCert, "paired") == "1" else { return .failed }
        guard let plain = PcScreenXml.value(getCert, "plaincert"), !plain.isEmpty, let certPem = PcScreenXml.unhex(plain) else {
            await unpair()
            return .alreadyInProgress
        }
        // The host sends its certificate as PEM text in hex.
        guard let serverDer = Self.derFromPem(certPem) else { await unpair(); return .failed }
        serverCert = serverDer

        let challenge = PcCrypto.random(16)
        let r1 = try await pairStep(false, "clientchallenge=" + PcScreenXml.hex(PcCrypto.aesEcb(challenge, key: aesKey, encrypt: true)))
        guard PcScreenXml.value(r1, "paired") == "1", let resp = PcScreenXml.unhex(PcScreenXml.value(r1, "challengeresponse") ?? "") else {
            await unpair(); return .failed
        }
        let dec = PcCrypto.aesEcb(resp, key: aesKey, encrypt: false)
        guard dec.count >= hashLen + 16 else { await unpair(); return .failed }
        let serverResponse = dec.prefix(hashLen)
        let serverChallenge = dec.subdata(in: hashLen..<(hashLen + 16))

        let clientSecret = PcCrypto.random(16)
        let respHash = hash(serverChallenge + id.certSignature + clientSecret)
        let r2 = try await pairStep(false, "serverchallengeresp=" + PcScreenXml.hex(PcCrypto.aesEcb(respHash, key: aesKey, encrypt: true)))
        guard PcScreenXml.value(r2, "paired") == "1", let secretResp = PcScreenXml.unhex(PcScreenXml.value(r2, "pairingsecret") ?? ""),
              secretResp.count > 16 else {
            await unpair(); return .failed
        }
        let serverSecret = secretResp.prefix(16)
        let serverSig = secretResp.suffix(from: secretResp.startIndex + 16)
        guard PcCrypto.verify(certDer: serverDer, data: Data(serverSecret), signature: Data(serverSig)) else {
            await unpair(); return .failed
        }
        let expected = hash(challenge + (Der.signature(of: serverDer) ?? Data()) + serverSecret)
        guard expected == Data(serverResponse) else {
            await unpair()
            return .pinWrong
        }

        let clientPairingSecret = clientSecret + id.sign(clientSecret)
        let r3 = try await pairStep(false, "clientpairingsecret=" + PcScreenXml.hex(clientPairingSecret))
        guard PcScreenXml.value(r3, "paired") == "1" else { await unpair(); return .failed }

        let r4 = try await pairStep(true, "phrase=pairchallenge")
        guard PcScreenXml.value(r4, "paired") == "1" else { await unpair(); return .failed }
        return .paired
    }

    private func pairStep(_ secure: Bool, _ args: String, timeout: Double = 10) async throws -> String {
        let (status, body) = try await fetch(url(secure, "pair", "devicename=roth&updateState=1&" + args), timeout: timeout)
        if status < 200 || status > 299 { throw HostError(code: status, message: HTTPURLResponse.localizedString(forStatusCode: status)) }
        return body
    }

    /// A PEM certificate's DER bytes (or the bytes as they are if they are already DER).
    static func derFromPem(_ pem: Data) -> Data? {
        let text = String(decoding: pem, as: UTF8.self)
        guard text.contains("BEGIN CERTIFICATE") else { return pem.first == 0x30 ? pem : nil }
        let b64 = text.components(separatedBy: "\n").filter { !$0.hasPrefix("-----") }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    }

    /// A four-digit PIN.
    static func newPin() -> String { String(format: "%04d", Int.random(in: 0..<10000)) }
}

/// The host's XML answers, read the way Pocket XR for Windows' PcScreenLogic reads them.
enum PcScreenXml {
    static func value(_ xml: String, _ tag: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"), let close = xml.range(of: "</\(tag)>", range: open.upperBound..<xml.endIndex) else { return nil }
        return String(xml[open.upperBound..<close.lowerBound]).replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func status(_ xml: String) -> (Int, String) {
        func attr(_ name: String) -> String? {
            guard let r = xml.range(of: "\(name)=\""), let end = xml.range(of: "\"", range: r.upperBound..<xml.endIndex) else { return nil }
            return String(xml[r.upperBound..<end.lowerBound])
        }
        return (Int(attr("status_code") ?? "") ?? 0, attr("status_message") ?? "")
    }

    /// The apps a host lists: id and name.
    static func apps(_ xml: String) -> [(id: Int, name: String)] {
        var out = [(id: Int, name: String)]()
        var rest = xml[...]
        while let open = rest.range(of: "<App>"), let close = rest.range(of: "</App>", range: open.upperBound..<rest.endIndex) {
            let inner = String(rest[open.upperBound..<close.lowerBound])
            if let title = value(inner, "AppTitle"), let id = Int(value(inner, "ID") ?? "") { out.append((id, title)) }
            rest = rest[close.upperBound...]
        }
        return out
    }

    /// The app a PC screen launches: "Desktop" if listed, else the first.
    static func desktopApp(_ apps: [(id: Int, name: String)]) -> (id: Int, name: String)? {
        apps.first { $0.name.caseInsensitiveCompare("Desktop") == .orderedSame } ?? apps.first
    }

    static func apolloVirtual(_ info: String) -> Bool {
        value(info, "VirtualDisplayCapable") == "true" && value(info, "VirtualDisplayDriverReady") != "false"
    }

    static func majorVersion(_ info: String) -> Int {
        let v = value(info, "appversion") ?? ""
        return Int(v.split(separator: ".").first ?? "") ?? 0
    }

    /// The app running in the host's session, or 0 when it is free.
    static func currentGame(_ info: String) -> Int {
        (value(info, "state") ?? "").hasSuffix("_SERVER_BUSY") ? Int(value(info, "currentgame") ?? "") ?? 0 : 0
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined() }

    static func unhex(_ s: String) -> Data? {
        var out = Data(capacity: s.count / 2)
        var it = s.makeIterator()
        while let a = it.next() {
            guard let b = it.next(), let v = UInt8(String([a, b]), radix: 16) else { return nil }
            out.append(v)
        }
        return out
    }
}
