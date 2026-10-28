import Foundation

final class StyleFields {
    private var fields: [String: ProtectedField<String?>] = [:]
    private var needsRestyle: Bool = true

    @MainActor
    subscript(_ key: String) -> String? {
        get {
            guard let field = fields[key] else { return nil }
            return field.peek() ?? nil
        }
        set {
            field(for: key).set(newValue)
        }
    }

    @MainActor
    func read(_ key: String, notify: any InvalidatableField) -> String? {
        return field(for: key).read(notify: notify)
    }

    @MainActor
    func markAll() {
        needsRestyle = true
        for field in fields.values {
            field.mark()
        }
    }

    @MainActor
    func apply(_ values: [String: String]) {
        var written: Int = 0
        var changed: Int = 0

        for key in Array(fields.keys) where values[key] == nil {
            guard let field = fields[key] else { continue }
            let before: String? = field.peek() ?? nil
            field.set(nil)
            written += 1
            if before != nil { changed += 1 }
        }

        for (key, value) in values {
            let field: ProtectedField<String?> = field(for: key)
            let before: String? = field.peek() ?? nil
            field.set(value)
            written += 1
            if before != value { changed += 1 }
        }

        needsRestyle = false
        profiler.count("style.fields.set", by: written)
        profiler.count("style.fields.changed", by: changed)
    }

    @MainActor
    func snapshot() -> [String: String] {
        var result: [String: String] = [:]
        for (key, field) in fields {
            if let value = field.peek() ?? nil {
                result[key] = value
            }
        }
        return result
    }

    @MainActor
    var isEmpty: Bool {
        return fields.values.allSatisfy({ ($0.peek() ?? nil) == nil })
    }

    @MainActor
    var isDirty: Bool {
        if needsRestyle { return true }
        return fields.values.contains(where: { $0.isDirty })
    }

    @MainActor
    private func field(for key: String) -> ProtectedField<String?> {
        if let field = fields[key] { return field }
        let field: ProtectedField<String?> = ProtectedField("style.\(key)", cleanValue: nil)
        fields[key] = field
        return field
    }
}
