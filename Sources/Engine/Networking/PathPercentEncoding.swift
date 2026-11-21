import Foundation

// MARK: - PathPercentEncoding
enum PathPercentEncoding {
    private static let percentSign: UInt8 = UInt8(ascii: "%")
    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)
    private static let allowed: CharacterSet = .urlPathAllowed

    static func encode(_ path: String) -> String {
        let bytes: [UInt8] = Array(path.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index: Int = 0
        while index < bytes.count {
            let byte: UInt8 = bytes[index]
            if byte == percentSign, isEscape(bytes, at: index) {
                output.append(contentsOf: bytes[index..<index + 3])
                index += 3
                continue
            }
            // URL Standard §4.4 path state keeps a stray "%" as-is, but Foundation's
            // percentEncodedPath traps on it, so it is written as "%25" instead.
            if byte < 0x80, byte != percentSign, allowed.contains(Unicode.Scalar(byte)) {
                output.append(byte)
            } else {
                output.append(percentSign)
                output.append(hexDigits[Int(byte >> 4)])
                output.append(hexDigits[Int(byte & 0x0F)])
            }
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func isEscape(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index + 2 < bytes.count else { return false }
        return isHexDigit(bytes[index + 1]) && isHexDigit(bytes[index + 2])
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
            UInt8(ascii: "a")...UInt8(ascii: "f"),
            UInt8(ascii: "A")...UInt8(ascii: "F"):
            return true
        default:
            return false
        }
    }
}
