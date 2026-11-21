import CoreGraphics

// MARK: - FloatLayoutPass

extension LayoutTree {
    /// An anonymous block borrows the style of its first inline node, which
    /// may itself say `float`; only element blocks float or clear.
    func blockFloating(_ id: LayoutID) -> LayoutStyle.Floating {
        guard !hasExtraNodes(id) else { return .none }
        return domView(id).style.computed.layout.position.floating
    }

    /// Floats and absolutely positioned boxes take no space in the flow, so the
    /// next sibling is placed after whatever came before them.
    func isOutOfFlow(_ node: LayoutDOMView) -> Bool {
        let position: LayoutStyle.Positioning = node.style.computed.layout.position
        return position.kind == .absolute || position.floating.side != .none
    }

    /// CSS 2.1 §9.5.2: `clear` looks at every earlier float in the same block
    /// formatting context, including floats under other parents, and never at
    /// floats inside another formatting context.
    func floatBottom(before id: LayoutID, clearing clear: LayoutStyle.ClearSide) -> CGFloat? {
        var bottom: CGFloat? = nil
        var current: LayoutID = id
        while let parent: LayoutID = parentID(of: current), isBlock(parent) {
            for sibling in childrenIDs(of: parent) {
                if sibling == current { break }
                collectFloatBottom(in: sibling, clearing: clear, into: &bottom)
            }
            if establishesFormattingContext(parent) { break }
            current = parent
        }
        return bottom
    }

    mutating func noteClearing(_ id: LayoutID, _ clears: Bool) {
        if clears {
            self[document: rootID].clearingBlocks.insert(id)
        } else if !self[document: rootID].clearingBlocks.isEmpty {
            self[document: rootID].clearingBlocks.remove(id)
        }
    }

    /// Clearance reads floats that are not among a block's layout inputs, so
    /// a float added or resized under another parent would leave it stale.
    /// Clearing blocks are rare; they re-place themselves on every pass that
    /// does layout work instead.
    mutating func markClearingBlocks() {
        let blocks: Set<LayoutID> = self[document: rootID].clearingBlocks
        guard !blocks.isEmpty else { return }
        var live: Set<LayoutID> = []
        for id in blocks where contains(id) && isBlock(id) {
            markField(.y, at: id)
            live.insert(id)
        }
        self[document: rootID].clearingBlocks = live
    }

    // MARK: - Helpers

    private func collectFloatBottom(
        in id: LayoutID,
        clearing clear: LayoutStyle.ClearSide,
        into bottom: inout CGFloat?
    ) {
        guard isBlock(id), !hasExtraNodes(id) else { return }
        let side: LayoutStyle.FloatSide = blockFloating(id).side
        if side != .none {
            if clear.clears(side) {
                let edge: CGFloat = marginBoxBottom(id)
                bottom = max(bottom ?? edge, edge)
            }
            return
        }
        if establishesFormattingContext(id) { return }
        for child in childrenIDs(of: id) {
            collectFloatBottom(in: child, clearing: clear, into: &bottom)
        }
    }

    /// CSS 2.1 §9.4.1: floats, absolutely positioned boxes, and blocks whose
    /// overflow is not visible start a new block formatting context, as does
    /// the root element.
    private func establishesFormattingContext(_ id: LayoutID) -> Bool {
        guard let parent: LayoutID = parentID(of: id), isBlock(parent) else { return true }
        guard !hasExtraNodes(id) else { return false }
        let layout: LayoutStyle = domView(id).style.computed.layout
        return layout.position.floating.side != .none
            || layout.position.kind == .absolute
            || layout.position.kind == .fixed
            || layout.overflow != .visible
    }

    private func marginBoxBottom(_ id: LayoutID) -> CGFloat {
        let marginBottom: CGFloat = domView(id).style.computed.box.spacing.margin.bottom * zoom(id)
        return y(id) + height(id) + padding(id, .paddingBottom) + borderWidths(id).bottom + marginBottom
    }
}
