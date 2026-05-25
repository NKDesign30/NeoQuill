import CryptoKit
import Foundation

enum AudioFingerprint {
    static func sha256(samples: [Float]) -> String {
        var hasher = SHA256()
        var count = UInt64(samples.count).littleEndian
        withUnsafeBytes(of: &count) { buffer in
            hasher.update(bufferPointer: buffer)
        }
        samples.withUnsafeBufferPointer { buffer in
            hasher.update(bufferPointer: UnsafeRawBufferPointer(buffer))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
