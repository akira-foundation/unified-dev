import CommonCrypto
import CryptoKit
import Foundation

enum PassphraseEnvelope {
    struct Unreadable: Error, Equatable {}

    private struct Header: Decodable {
        let alg: String
        let enc: String
        let p2s: String
        let p2c: Int
    }

    static let algorithm = "PBES2-HS256+A128KW"
    static let encryption = "A256GCM"
    static let iterationLimit = 1_000_000

    static func open(_ compact: String, passphrase: String) throws -> Data {
        let parts = compact.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 5,
              let headerData = decode(parts[0]),
              let header = try? JSONDecoder().decode(Header.self, from: headerData),
              header.alg == algorithm, header.enc == encryption,
              header.p2c > 0, header.p2c <= iterationLimit,
              let saltInput = decode(Substring(header.p2s)),
              let wrapped = decode(parts[1]),
              let nonce = decode(parts[2]),
              let ciphertext = decode(parts[3]),
              let tag = decode(parts[4])
        else { throw Unreadable() }

        let salt = Data(algorithm.utf8) + Data([0]) + saltInput
        let wrapping = try derive(passphrase: passphrase, salt: salt, rounds: header.p2c, length: 16)
        do {
            let content = try AES.KeyWrap.unwrap(wrapped, using: SymmetricKey(data: wrapping))
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: content, authenticating: Data(parts[0].utf8))
        } catch {
            throw Unreadable()
        }
    }

    static func decode(_ text: Substring) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    private static func derive(passphrase: String, salt: Data, rounds: Int, length: Int) throws -> Data {
        var derived = Data(count: length)
        let password = Array(passphrase.utf8)
        let status = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password.map { CChar(bitPattern: $0) }, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                    output.bindMemory(to: UInt8.self).baseAddress, length
                )
            }
        }
        guard status == kCCSuccess else { throw Unreadable() }
        return derived
    }
}
