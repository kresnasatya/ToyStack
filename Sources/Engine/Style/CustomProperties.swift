// MARK: - CustomProperties

/// CSS Variables 1 §2: a custom property is inherited, and its computed value
/// is its specified value with variables substituted, or the guaranteed-invalid
/// value. ToyStack keeps only the valid ones, so a missing name means the
/// guaranteed-invalid value.
struct CustomProperties: Equatable {
    private(set) var values: [String: String]

    static let none: CustomProperties = CustomProperties(values: [:])
    static let maximumLength: Int = 1 << 16

    private init(values: [String: String]) {
        self.values = values
    }

    init(declarations: [String: String], inherited: CustomProperties) {
        guard declarations.keys.contains(where: CustomProperties.isCustom) else {
            self = inherited
            return
        }
        var resolver: VariableResolver = VariableResolver(
            declared: declarations.filter({ CustomProperties.isCustom($0.key) }),
            values: inherited.values
        )
        for name in resolver.declared.keys {
            _ = resolver.value(of: name)
        }
        self.values = resolver.values
    }

    /// CSS Variables 1 §2: a custom property name starts with two dashes, and
    /// "--" alone is reserved.
    static func isCustom(_ name: String) -> Bool {
        return name.hasPrefix("--") && name.utf8.count > 2
    }

    static func usesVariables(_ declarations: [String: String]) -> Bool {
        return declarations.contains(where: { isCustom($0.key) || containsVar($0.value) })
    }

    static func containsVar(_ value: String) -> Bool {
        var text: String = value
        return text.withUTF8({ VariableResolver.containsVar($0) })
    }

    /// CSS Variables 1 §2.2: a property whose value meets the guaranteed-invalid
    /// value becomes invalid at computed-value time. ToyStack drops that
    /// declaration, so the property inherits or takes its initial value.
    func substituted(into declarations: [String: String]) -> [String: String] {
        var resolver: VariableResolver = VariableResolver(declared: [:], values: values)
        var result: [String: String] = [:]
        result.reserveCapacity(declarations.count)
        var longhandsByShorthand: [String: [String: String]] = [:]
        for (name, value) in declarations where !CustomProperties.isCustom(name) {
            if let pending = PendingSubstitution(cascaded: value) {
                if longhandsByShorthand[value] == nil {
                    let substituted: String? = resolver.substitute(pending.value)
                    longhandsByShorthand[value] = substituted.flatMap({
                        CSSParser.longhands(of: pending.shorthand, value: $0)
                    }) ?? [:]
                }
                if let longhand = longhandsByShorthand[value]?[name] {
                    result[name] = longhand
                }
            } else if let substituted = resolver.substitute(value) {
                result[name] = substituted
            }
        }
        return result
    }
}

// MARK: - VariableResolver

private struct VariableResolver {
    let declared: [String: String]
    var values: [String: String]
    private var progress: [String: Progress] = [:]
    private var stack: [String] = []

    private enum Progress {
        case active
        case cyclic
        case done
    }

    init(declared: [String: String], values: [String: String]) {
        self.declared = declared
        self.values = values
    }

    /// CSS Variables 1 §3: custom properties that reference each other in a
    /// cycle all compute to the guaranteed-invalid value.
    mutating func value(of name: String) -> String? {
        switch progress[name] {
        case .done?:
            return values[name]
        case .active?, .cyclic?:
            markCycle(from: name)
            return nil
        case nil:
            break
        }
        guard let raw = declared[name] else { return values[name] }
        progress[name] = .active
        stack.append(name)
        let result: String? = computedValue(raw, inherited: values[name])
        stack.removeLast()
        values[name] = progress[name] == .cyclic ? nil : result
        progress[name] = .done
        return values[name]
    }

    mutating func substitute(_ value: String) -> String? {
        var text: String = value
        return text.withUTF8({ bytes in
            guard VariableResolver.containsVar(bytes) else { return value }
            return substitute(bytes)
        })
    }

    private mutating func computedValue(_ raw: String, inherited: String?) -> String? {
        switch raw {
        case "initial": return nil
        case "inherit", "unset": return inherited
        default: return substitute(raw)
        }
    }

    private mutating func markCycle(from name: String) {
        guard let start: Int = stack.lastIndex(of: name) else { return }
        for member in stack[start...] {
            progress[member] = .cyclic
        }
    }

    private mutating func substitute(_ bytes: UnsafeBufferPointer<UInt8>) -> String? {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index: Int = 0
        var quote: UInt8? = nil
        while index < bytes.count {
            let byte: UInt8 = bytes[index]
            if let open = quote {
                output.append(byte)
                if byte == UInt8(ascii: "\\"), index + 1 < bytes.count {
                    output.append(bytes[index + 1])
                    index += 2
                    continue
                }
                if byte == open {
                    quote = nil
                }
                index += 1
                continue
            }
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
                output.append(byte)
                index += 1
                continue
            }
            guard VariableResolver.startsVar(bytes, at: index) else {
                output.append(byte)
                index += 1
                continue
            }
            let open: Int = index + 4
            guard let close: Int = VariableResolver.closingParenthesis(bytes, from: open),
                let replacement: String = replaceVar(UnsafeBufferPointer(rebasing: bytes[open..<close]))
            else { return nil }
            output.append(contentsOf: replacement.utf8)
            guard output.count <= CustomProperties.maximumLength else { return nil }
            index = close + 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// CSS Variables 1 §3: the first argument names the custom property, and
    /// everything after the first comma is the fallback, which may be empty.
    private mutating func replaceVar(_ arguments: UnsafeBufferPointer<UInt8>) -> String? {
        let comma: Int? = VariableResolver.topLevelComma(arguments)
        let nameBytes: Slice<UnsafeBufferPointer<UInt8>> = VariableResolver.trimmed(
            arguments[0..<(comma ?? arguments.count)]
        )
        let name: String = String(decoding: nameBytes, as: UTF8.self)
        guard CustomProperties.isCustom(name) else { return nil }
        if let result: String = value(of: name) {
            return result
        }
        guard let comma else { return nil }
        let fallback: Slice<UnsafeBufferPointer<UInt8>> = VariableResolver.trimmed(
            arguments[(comma + 1)..<arguments.count]
        )
        return substitute(String(decoding: fallback, as: UTF8.self))
    }

    static func containsVar(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bytes.count >= 4 else { return false }
        for index in 0...(bytes.count - 4) where startsVar(bytes, at: index) {
            return true
        }
        return false
    }

    private static func startsVar(_ bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> Bool {
        guard index + 4 <= bytes.count,
            bytes[index] | 0x20 == UInt8(ascii: "v"),
            bytes[index + 1] | 0x20 == UInt8(ascii: "a"),
            bytes[index + 2] | 0x20 == UInt8(ascii: "r"),
            bytes[index + 3] == UInt8(ascii: "(")
        else { return false }
        return index == 0 || !isNameByte(bytes[index - 1])
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"), 0x80...:
            return true
        default:
            return false
        }
    }

    private static func closingParenthesis(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        var depth: Int = 1
        var index: Int = start
        var quote: UInt8? = nil
        while index < bytes.count {
            let byte: UInt8 = bytes[index]
            if let open = quote {
                if byte == UInt8(ascii: "\\") {
                    index += 2
                    continue
                }
                if byte == open {
                    quote = nil
                }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: "(") {
                depth += 1
            } else if byte == UInt8(ascii: ")") {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private static func topLevelComma(_ bytes: UnsafeBufferPointer<UInt8>) -> Int? {
        var depth: Int = 0
        var index: Int = 0
        var quote: UInt8? = nil
        while index < bytes.count {
            let byte: UInt8 = bytes[index]
            if let open = quote {
                if byte == UInt8(ascii: "\\") {
                    index += 2
                    continue
                }
                if byte == open {
                    quote = nil
                }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: "(") {
                depth += 1
            } else if byte == UInt8(ascii: ")") {
                depth -= 1
            } else if byte == UInt8(ascii: ","), depth == 0 {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func trimmed(_ bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Slice<UnsafeBufferPointer<UInt8>> {
        var start: Int = bytes.startIndex
        var end: Int = bytes.endIndex
        while start < end, isWhitespace(bytes[start]) {
            start += 1
        }
        while end > start, isWhitespace(bytes[end - 1]) {
            end -= 1
        }
        return bytes[start..<end]
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        return byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
            || byte == UInt8(ascii: "\r") || byte == 0x0C
    }
}
