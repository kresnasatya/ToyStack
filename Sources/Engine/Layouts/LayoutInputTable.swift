import Foundation

/// The single static description of what every layout field reads.
///
/// One entry per node kind and field. This table is the only place that
/// declares an edge: `DependencyIndex.rebuild(from:)` reconstructs the reverse
/// index from it alone.
enum LayoutInputTable {
    /// Style changes that can alter which fields are inputs, not just their
    /// values. Only these need the dependency table reindexed.
    static let structuralStyleProperties: Set<StyleProperty> = [
        .display, .position, .direction, .whiteSpace, .aspectRatio, .maxWidth,
    ]

    static func inputs(
        for id: LayoutID,
        field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        switch tree[node: id].kind {
        case .document:
            return documentInputs(id, field, in: tree)
        case .block:
            return blockInputs(id, field, in: tree)
        case .line:
            return lineInputs(id, field, in: tree)
        case .text:
            return textInputs(id, field, in: tree)
        case .embed:
            return embedInputs(id, field, in: tree)
        }
    }

    // MARK: - Document

    private static func documentInputs(
        _ id: LayoutID,
        _ field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        switch field {
        case .zoom, .children:
            return []
        case .width, .x, .y:
            return [.layout(id, .zoom)]
        case .height:
            guard let child: LayoutID = tree.childrenIDs(of: id).first else { return [] }
            let childDom: NodeID = tree.domID(of: child)
            return [
                .layout(child, .height),
                .style(childDom, .paddingTop),
                .style(childDom, .paddingBottom),
            ]
        case .previous, .font, .ascent, .descent, .inlineContent:
            return []
        }
    }

    // MARK: - Block

    private static func blockInputs(
        _ id: LayoutID,
        _ field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        let dom: NodeID = tree.domID(of: id)
        let parent: LayoutID? = tree.parentID(of: id)
        let previous: LayoutID? = tree.previousID(of: id)
        switch field {
        case .previous:
            return []
        case .zoom:
            var keys: [FieldKey] = [.style(dom, .zoom)]
            if let parent { keys.insert(.layout(parent, .zoom), at: 0) }
            return keys
        case .x:
            var keys: [FieldKey] = [
                .layout(id, .zoom),
                .style(dom, .paddingLeft),
                .style(dom, .position),
                .style(dom, .left),
            ]
            if let parent { keys.insert(.layout(parent, .x), at: 0) }
            return keys
        case .y:
            var keys: [FieldKey] = [
                .layout(id, .previous),
                .layout(id, .zoom),
                .style(dom, .paddingTop),
                .style(dom, .top),
                .style(dom, .marginTop),
            ]
            if let parent { keys.insert(.layout(parent, .y), at: 0) }
            if let previous {
                let previousDom: NodeID = tree.domID(of: previous)
                keys += [
                    .layout(previous, .y),
                    .layout(previous, .height),
                    .style(previousDom, .marginBottom),
                    .style(previousDom, .paddingBottom),
                ]
            }
            return keys
        case .width:
            var keys: [FieldKey] = [
                .layout(id, .zoom),
                .style(dom, .paddingLeft),
                .style(dom, .paddingRight),
                .style(dom, .width),
            ]
            if let parent { keys.insert(.layout(parent, .width), at: 0) }
            return keys
        case .inlineContent:
            return blockContentInputs(id, in: tree)
        case .children:
            return tree.blockChildrenInputs(id)
        case .height:
            return tree.blockHeightInputs(id)
        case .font, .ascent, .descent:
            return []
        }
    }

    private static func blockContentInputs(
        _ id: LayoutID,
        in tree: LayoutTree
    ) -> [FieldKey] {
        return tree.inlineContentInputs(id)
    }

    // MARK: - Line

    private static func lineInputs(
        _ id: LayoutID,
        _ field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        let parent: LayoutID? = tree.parentID(of: id)
        switch field {
        case .zoom:
            return parent.map({ [.layout($0, .zoom)] }) ?? []
        case .width:
            return parent.map({ [.layout($0, .width)] }) ?? []
        case .x:
            return parent.map({ [.layout($0, .x)] }) ?? []
        case .y:
            var keys: [FieldKey] = parent.map({ [.layout($0, .y)] }) ?? []
            if let previous: LayoutID = tree.previousID(of: id) {
                keys += [.layout(previous, .y), .layout(previous, .height)]
            }
            return keys
        case .height:
            return [.layout(id, .ascent), .layout(id, .descent)]
        case .ascent:
            return lineChildKeys(id, in: tree, field: .ascent)
        case .descent:
            return lineChildKeys(id, in: tree, field: .descent)
        case .children, .previous, .font, .inlineContent:
            return []
        }
    }

    private static func lineChildKeys(
        _ id: LayoutID,
        in tree: LayoutTree,
        field: LayoutField
    ) -> [FieldKey] {
        return tree.children(of: id)
            .filter({ tree.isText($0) || tree.isEmbed($0) })
            .map({ .layout($0, field) })
    }

    // MARK: - Text

    private static func textInputs(
        _ id: LayoutID,
        _ field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        let dom: NodeID = tree.domID(of: id)
        switch field {
        case .zoom:
            var keys: [FieldKey] = [.style(dom, .zoom)]
            if let parent: LayoutID = tree.parentID(of: id) {
                keys.append(.layout(parent, .zoom))
            }
            return keys
        case .font:
            return [.layout(id, .zoom)] + fontInputs(for: dom, in: tree.inputs)
        case .width, .height, .ascent, .descent:
            return [.layout(id, .font)]
        case .x, .y, .children, .previous, .inlineContent:
            return []
        }
    }

    // MARK: - Embed

    private static func embedInputs(
        _ id: LayoutID,
        _ field: LayoutField,
        in tree: LayoutTree
    ) -> [FieldKey] {
        let dom: NodeID = tree.domID(of: id)
        let parent: LayoutID? = tree.parentID(of: id)
        let data: EmbedData
        if case .embed(let value) = tree[node: id].kind {
            data = value
        } else {
            preconditionFailure("LayoutInputTable.embedInputs on non-embed node")
        }
        switch field {
        case .zoom:
            var keys: [FieldKey] = [.style(dom, .zoom)]
            if let parent { keys.insert(.layout(parent, .zoom), at: 0) }
            return keys
        case .font:
            return [.layout(id, .zoom)] + fontInputs(for: dom, in: tree.inputs)
        case .children, .x, .y, .previous, .inlineContent:
            return []
        case .width:
            return embedWidthInputs(id, parent: parent, dom: dom, data: data)
        case .height:
            var keys: [FieldKey] = embedHeightInputs(id, dom: dom, data: data)
            if case .button = data {
                keys += tree.children(of: id).map({ .layout($0, .height) })
            }
            return keys
        case .ascent:
            if case .button = data {
                // `makeEmbed` seeds ascent with `.height`; `layoutButton`
                // declares `.font` on top of it.
                return [.layout(id, .height), .layout(id, .font)]
            }
            return [.layout(id, .height)]
        case .descent:
            if case .button = data {
                return [.layout(id, .font)]
            }
            return []
        }
    }

    private static func embedWidthInputs(
        _ id: LayoutID,
        parent: LayoutID?,
        dom: NodeID,
        data: EmbedData
    ) -> [FieldKey] {
        switch data {
        case .image:
            var keys: [FieldKey] = [
                .layout(id, .zoom),
                .style(dom, .aspectRatio),
                .style(dom, .maxWidth),
            ]
            if let parent { keys.insert(.layout(parent, .width), at: 0) }
            return keys
        case .input:
            return [.layout(id, .font), .layout(id, .zoom)]
        case .button:
            return [.layout(id, .zoom)]
        case .iframe:
            return [.layout(id, .zoom), .style(dom, .aspectRatio)]
        case .canvas:
            return [.layout(id, .zoom)]
        }
    }

    private static func embedHeightInputs(
        _ id: LayoutID,
        dom: NodeID,
        data: EmbedData
    ) -> [FieldKey] {
        switch data {
        case .image:
            return [
                .layout(id, .width),
                .layout(id, .zoom),
                .layout(id, .font),
                .style(dom, .aspectRatio),
            ]
        case .input:
            return [.layout(id, .font)]
        case .button:
            return [.layout(id, .font)]
        case .iframe:
            return [.layout(id, .zoom), .style(dom, .aspectRatio)]
        case .canvas:
            return [.layout(id, .zoom)]
        }
    }

    // MARK: - Shared

}
