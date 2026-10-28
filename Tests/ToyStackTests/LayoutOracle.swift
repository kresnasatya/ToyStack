import CoreGraphics
import Testing

@testable import Engine

// Differential oracle for incremental layout.
//
// Render the page as the incremental fields left it, then throw the layout
// tree away and build it again from the same DOM. Geometry and paint commands
// must be identical. Call this last in a test: the full rebuild replaces every
// layout object and re-attaches the DOM to the new tree.
@MainActor
func expectIncrementalMatchesFull(
    _ page: LayoutTestPage,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let incremental: String = renderSignature(page.frame)

    let savedDocument: DocumentLayout? = page.frame.document
    let savedObjects: [ObjectIdentifier: any LayoutObject] = layoutObjectMapping(
        page.frame
    )
    page.frame.document = nil
    page.frame.setNeedsLayout()
    page.frame.render()
    let full: String = renderSignature(page.frame)

    page.frame.document = savedDocument
    restoreLayoutObjects(savedObjects, in: page.frame)
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
        appendLayoutSignature(document, path: "0", into: &parts)
    }
    return parts.joined(separator: "\n")
}

// Every field must be clean once layout has run. A dirty field here means a
// value that the next pass will recompute from nothing, usually because the
// owner forgot to set it.
@MainActor
func expectAllLayoutFieldsClean(
    _ document: DocumentLayout,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for object in treeToList(document) {
        for (name, field) in layoutFields(of: object) {
            #expect(
                !field.isDirty,
                "\(type(of: object)).\(name) is still dirty",
                sourceLocation: sourceLocation
            )
        }
    }
}

@MainActor
private func appendLayoutSignature(
    _ object: any LayoutObject,
    path: String,
    into parts: inout [String]
) {
    var line: String = "\(path) \(type(of: object)) \(object.selfRect()) children=\(object.children.count)"
    if let text = object as? TextLayout {
        line += " word=\(text.word) display=\(text.displayWord ?? "") width=\(text.textWidth)"
    }
    parts.append(line)

    for (index, child) in object.children.enumerated() {
        appendLayoutSignature(child, path: "\(path).\(index)", into: &parts)
    }
}

@MainActor
private func layoutObjectMapping(
    _ frame: Frame
) -> [ObjectIdentifier: any LayoutObject] {
    var mapping: [ObjectIdentifier: any LayoutObject] = [:]
    for node in treeToList(frame.nodes) {
        guard let object = node.layoutObject else { continue }
        mapping[ObjectIdentifier(node)] = object
    }
    return mapping
}

@MainActor
private func restoreLayoutObjects(
    _ mapping: [ObjectIdentifier: any LayoutObject],
    in frame: Frame
) {
    for node in treeToList(frame.nodes) {
        node.layoutObject = mapping[ObjectIdentifier(node)]
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
