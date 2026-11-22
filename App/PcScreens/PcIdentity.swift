import CommonCrypto
import CryptoKit
import CMoonlightShared
import Foundation
import Security

/// PC screens: this phone's identity as a Moonlight client, made once, as Pocket XR for Windows and moonlight-android
/// make it: a random 16-hex-digit client id and a self-signed RSA 2048 certificate named "NVIDIA GameStream Client",
/// valid for 20 years. The host pins the certificate when paired.
///
/// The key and the certificate live in the app's keychain: iOS joins them into the identity TLS needs for its client
/// certificate (it has no public way to join them otherwise).
final class PcIdentity: @unchecked Sendable {
    static let keyTag = Data("com.hayeco.pocketxr.pcscreens.client".utf8)
    static let label = "Pocket XR PC screens client"

    let uniqueId: String
    let certDer: Data
    /// The certificate in PEM with Unix line endings: hosts refuse others (moonlight-android's note).
    let pemCert: Data
    /// The certificate's own signature bytes, which the pairing hashes.
    let certSignature: Data
    let key: SecKey
    let identity: SecIdentity?

    private static let gate = NSLock()
    private static var made: PcIdentity?

    static var shared: PcIdentity? {
        gate.lock(); defer { gate.unlock() }
        if made == nil { made = load() }
        return made
    }

    private init(id: String, der: Data, key: SecKey, identity: SecIdentity?) {
        uniqueId = id
        certDer = der
        self.key = key
        self.identity = identity
        let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        pemCert = Data("-----BEGIN CERTIFICATE-----\n\(b64)\n-----END CERTIFICATE-----\n".utf8)
        certSignature = Der.signature(of: der) ?? Data()
    }

    func sign(_ data: Data) -> Data {
        (SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, nil) as Data?) ?? Data()
    }

    private static func load() -> PcIdentity? {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "pcscreens.clientId"), let der = d.data(forKey: "pcscreens.clientCert"),
           let key = storedKey() {
            return PcIdentity(id: id, der: der, key: key, identity: findIdentity(der: der))
        }
        // Anything left from an earlier identity goes, so the keychain never holds two.
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag] as CFDictionary)
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: label] as CFDictionary)

        var error: Unmanaged<CFError>?
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048,
            kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrApplicationTag: keyTag, kSecAttrLabel: label],
        ]
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error), let pub = SecKeyCopyPublicKey(key),
              let pubData = SecKeyCopyExternalRepresentation(pub, nil) as Data? else {
            AppLog.line("pc screens: could not make a key: \(String(describing: error?.takeRetainedValue()))")
            return nil
        }
        guard let der = Der.selfSigned(commonName: "NVIDIA GameStream Client", publicKeyPkcs1: pubData, years: 20, sign: { tbs in
            SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(tbs) as CFData, nil) as Data?
        }), let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            AppLog.line("pc screens: could not make the certificate")
            return nil
        }
        let added = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: cert, kSecAttrLabel: label] as CFDictionary, nil)
        if added != errSecSuccess && added != errSecDuplicateItem { AppLog.line("pc screens: keychain refused the certificate (\(added))") }
        var raw = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, raw.count, &raw)
        let id = raw.map { String(format: "%02x", $0) }.joined()
        d.set(id, forKey: "pcscreens.clientId")
        d.set(der, forKey: "pcscreens.clientCert")
        AppLog.line("pc screens: made this phone's client id, certificate and key")
        return PcIdentity(id: id, der: der, key: key, identity: findIdentity(der: der))
    }

    private static func storedKey() -> SecKey? {
        var out: CFTypeRef?
        let q: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag, kSecAttrKeyType: kSecAttrKeyTypeRSA,
                                  kSecReturnRef: true]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let k = out else { return nil }
        return (k as! SecKey)
    }

    /// The keychain's identity whose certificate is ours.
    private static func findIdentity(der: Data) -> SecIdentity? {
        var out: CFTypeRef?
        let q: [CFString: Any] = [kSecClass: kSecClassIdentity, kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitAll]
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let list = out as? [SecIdentity] else {
            AppLog.line("pc screens: no identity in the keychain (\(status))")
            return nil
        }
        for i in list {
            var c: SecCertificate?
            if SecIdentityCopyCertificate(i, &c) == errSecSuccess, let c, SecCertificateCopyData(c) as Data == der { return i }
        }
        AppLog.line("pc screens: the keychain's identities do not hold this certificate")
        return nil
    }
}

/// The small crypto the pairing and the stream need, on Apple's own libraries.
enum PcCrypto {
    static func random(_ n: Int) -> Data {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b)
    }

    static func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }
    static func sha1(_ d: Data) -> Data { Data(Insecure.SHA1.hash(data: d)) }

    /// AES-128 ECB over the data padded with zeros to whole blocks, as Moonlight's pairing does.
    static func aesEcb(_ data: Data, key: Data, encrypt: Bool) -> Data {
        var padded = [UInt8](data)
        while padded.count % 16 != 0 { padded.append(0) }
        var out = [UInt8](repeating: 0, count: padded.count)
        var moved = 0
        let k = [UInt8](key)
        _ = CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                    k, k.count, nil, padded, padded.count, &out, out.count, &moved)
        return Data(out.prefix(moved))
    }

    /// Verifies [signature] over [data] with the RSA key in a DER certificate (SHA-256, PKCS#1 v1.5).
    static func verify(certDer: Data, data: Data, signature: Data) -> Bool {
        guard let cert = SecCertificateCreateWithData(nil, certDer as CFData), let pub = SecCertificateCopyKey(cert) else { return false }
        return SecKeyVerifySignature(pub, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, signature as CFData, nil)
    }

    /// Hands moonlight-common-c its AES-GCM (CommonCrypto has no public GCM): CryptoKit, called from C.
    static func installGcm() {
        pxr_set_gcm { encrypt, key, keyLength, iv, ivLength, tag, tagLength, input, length, output in
            guard let key, let iv, let tag, let output, keyLength > 0, ivLength > 0, tagLength > 0 else { return 0 }
            let k = SymmetricKey(data: Data(bytes: key, count: Int(keyLength)))
            guard let nonce = try? AES.GCM.Nonce(data: Data(bytes: iv, count: Int(ivLength))) else { return 0 }
            let inData = length > 0 && input != nil ? Data(bytes: input!, count: Int(length)) : Data()
            do {
                if encrypt != 0 {
                    let box = try AES.GCM.seal(inData, using: k, nonce: nonce)
                    box.ciphertext.copyBytes(to: output, count: Int(length))
                    let t = box.tag.prefix(Int(tagLength))
                    t.copyBytes(to: tag, count: t.count)
                } else {
                    let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: inData, tag: Data(bytes: tag, count: Int(tagLength)))
                    let plain = try AES.GCM.open(box, using: k)
                    plain.copyBytes(to: output, count: Int(length))
                }
                return 1
            } catch {
                return 0
            }
        }
    }
}

/// Just enough DER (X.509): a self-signed certificate made, and a certificate's signature read. From Pocket XR for
/// Mac's HostIdentity.swift.
enum Der {
    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] { [tag] + length(content.count) + content }
    static func seq(_ parts: [UInt8]...) -> [UInt8] { tlv(0x30, parts.flatMap { $0 }) }
    static func oid(_ bytes: [UInt8]) -> [UInt8] { tlv(0x06, bytes) }
    static let null: [UInt8] = [0x05, 0x00]
    static let sha256WithRsa: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    static func utcTime(_ d: Date) -> [UInt8] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss"
        return tlv(0x17, Array((f.string(from: d) + "Z").utf8))
    }

    static func selfSigned(commonName: String, publicKeyPkcs1: Data, years: Int, sign: ([UInt8]) -> Data?) -> Data? {
        var serial = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F
        serial[0] |= 0x01
        let name = seq(tlv(0x31, seq(oid([0x55, 0x04, 0x03]), tlv(0x0C, Array(commonName.utf8)))))
        let alg = seq(oid(sha256WithRsa), null)
        let now = Date().addingTimeInterval(-300)
        let validity = seq(utcTime(now), utcTime(now.addingTimeInterval(Double(years) * 365.25 * 86400)))
        let spki = seq(seq(oid(rsaEncryption), null), tlv(0x03, [0] + Array(publicKeyPkcs1)))
        let tbs = seq(tlv(0xA0, tlv(0x02, [2])), tlv(0x02, serial), alg, name, validity, name, spki)
        guard let signature = sign(tbs) else { return nil }
        return Data(seq(tbs, alg, tlv(0x03, [0] + Array(signature))))
    }

    /// The signature of a DER certificate: the content of its third top-level element (a BIT STRING), less the
    /// unused-bits byte.
    static func signature(of der: Data) -> Data? {
        let b = [UInt8](der)
        func read(_ at: Int) -> (tag: UInt8, start: Int, end: Int)? {
            guard at + 2 <= b.count else { return nil }
            let tag = b[at]
            var len = Int(b[at + 1])
            var p = at + 2
            if len & 0x80 != 0 {
                let n = len & 0x7F
                guard n <= 4, p + n <= b.count else { return nil }
                len = 0
                for i in 0..<n { len = len << 8 | Int(b[p + i]) }
                p += n
            }
            guard p + len <= b.count else { return nil }
            return (tag, p, p + len)
        }
        guard let top = read(0), top.tag == 0x30, let tbs = read(top.start), let alg = read(tbs.end),
              let sig = read(alg.end), sig.tag == 0x03, sig.end > sig.start + 1 else { return nil }
        return Data(b[(sig.start + 1)..<sig.end])
    }
}
