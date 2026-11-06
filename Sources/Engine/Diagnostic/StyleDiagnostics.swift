import Foundation

// MARK: - StyleDiagnostics

/// Opt-in audit log for style passes.
///
/// When `TOYSTACK_STYLE_LOG=1` is set, every style pass writes a header
/// (viewport or other, width, flipped media queries, applied node count) and
/// one line for every node whose font size changes. That names the nodes that
/// a resize failed to update, which the trace counters cannot express.
///
/// The log goes to `/tmp/toystack-style.log`. It is a diagnostic only; with
/// the variable unset nothing is written and no file is created.
@MainActor
enum StyleDiagnostics {
    static let isEnabled: Bool =
        ProcessInfo.processInfo.environment["TOYSTACK_STYLE_LOG"] == "1"

    static let path: String = "/tmp/toystack-style.log"

    private static let handle: FileHandle? = {
        guard isEnabled else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private static func write(_ line: String) {
        guard let handle else { return }
        guard let data: Data = line.data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    static func begin(width: CGFloat, viewport: Bool, flipped: Int, applied: Int) {
        guard isEnabled else { return }
        let stamp: String = String(format: "%.3f", Date().timeIntervalSince1970)
        write(
            "=== pass at=\(stamp) width=\(Int(width)) viewport=\(viewport ? 1 : 0) flipped=\(flipped) applied=\(applied)\n"
        )
    }

    static func fontChange(node: DOMRef, from oldSize: CGFloat, to newSize: CGFloat) {
        guard isEnabled, oldSize != newSize else { return }
        let element: ElementRef? = node.element
        let tag: String = element?.tag ?? "text"
        let id: String = element?.attributes["id"] ?? ""
        let cls: String = element?.attributes["class"] ?? ""
        let parent: String = node.parent.map({ ref in
            let el: ElementRef? = ref.element
            return "<\(el?.tag ?? "text")>#\(el?.attributes["id"] ?? "")"
        }) ?? "-"
        let raw: String =
            element?.children.compactMap({ $0.text }).map(\.text).joined()
            ?? node.text?.text
            ?? ""
        let text: String = raw
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        write(
            "font-size \(oldSize) -> \(newSize) <\(tag)>#\(id) .\(cls) parent=\(parent) '\(String(text.prefix(36)))'\n"
        )
    }
}
