import CoreGraphics
import Testing

@testable import Engine

// Differential oracle for incremental layout.
//
// Render the page as the incremental fields left it, then throw the layout
// tree away and build it again from the same DOM. Geometry and paint commands
// must be identical. Call this last in a test: the full rebuild replaces every
// layout node and re-attaches the DOM to the new tree.
@MainActor
func expectIncrementalMatchesFull(
    _ page: LayoutTestPage,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let incremental: String = renderSignature(page.frame)

    let savedDocument: LayoutTree? = page.frame.document
    page.frame.setLayoutTree(nil)
    page.frame.setNeedsLayout()
    page.frame.render()
    let full: String = renderSignature(page.frame)

    page.frame.setLayoutTree(savedDocument)
    page.frame.markStructureChanged()
    page.frame.setNeedsPaint()

    #expect(
        incremental == full,
        "incremental layout diverged from a full rebuild:\n\(firstDifference(incremental, full))",
        sourceLocation: sourceLocation
    )
}

@MainActor
func renderSignature(_ frame: Frame) -> String {
    frame.setNeedsPaint()
    frame.paint()

    var parts: [String] = displaySignature(frame.displayList)
        .split(separator: "|")
        .map({ "display \($0)" })
    if let document = frame.document {
        appendLayoutSignature(document.root, path: "0", into: &parts)
    }
    return parts.joined(separator: "\n")
}

// Every field must be clean once layout has run. A dirty field here means a
// value that the next pass will recompute from nothing, usually because the
// owner forgot to set it.
@MainActor
func expectAllLayoutFieldsClean(
    _ document: LayoutTree,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for object in treeToList(document.root) {
        for field in LayoutField.allCases where document.isUsed(field, at: object.id) {
            #expect(
                !document.isDirty(field, at: object.id),
                "\(layoutKindName(object.kind)).\(field.rawValue) is still dirty",
                sourceLocation: sourceLocation
            )
        }
    }
}

@MainActor
private func appendLayoutSignature(
    _ object: LayoutRef,
    path: String,
    into parts: inout [String]
) {
    var line: String = "\(path) \(layoutKindName(object.kind)) \(object.selfRect()) children=\(object.children.count)"
    if object.isText {
        let data: TextData = object.textData
        line += " word=\(data.word) display=\(data.display ?? "") width=\(data.metrics.width)"
    }
    parts.append(line)

    for (index, child) in object.children.enumerated() {
        appendLayoutSignature(child, path: "\(path).\(index)", into: &parts)
    }
}

private func firstDifference(_ lhs: String, _ rhs: String) -> String {
    let left: [Substring] = lhs.split(separator: "\n", omittingEmptySubsequences: false)
    let right: [Substring] = rhs.split(separator: "\n", omittingEmptySubsequences: false)
    for index in 0..<max(left.count, right.count) {
        let a: Substring = index < left.count ? left[index] : "<missing>"
        let b: Substring = index < right.count ? right[index] : "<missing>"
        if a != b {
            return "line \(index + 1)\n  incremental: \(a)\n  full:        \(b)"
        }
    }
    return "signatures are equal"
}


@MainActor
func layoutKindName(_ kind: LayoutKind) -> String {
    switch kind {
    case .document:
        return "document"
    case .block:
        return "block"
    case .line:
        return "line"
    case .text:
        return "text"
    case .embed(let data):
        switch data {
        case .image:
            return "embed.image"
        case .input:
            return "embed.input"
        case .button:
            return "embed.button"
        case .iframe:
            return "embed.iframe"
        case .canvas:
            return "embed.canvas"
        }
    }
}
