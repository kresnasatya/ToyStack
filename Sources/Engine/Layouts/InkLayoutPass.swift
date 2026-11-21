import CoreGraphics

// MARK: - InkLayoutPass

extension LayoutTree {
    /// Runs once the block's children are laid out. A child block that layout
    /// skipped keeps its stored extent, which is still right: nothing inside
    /// it moved.
    mutating func recordInk(_ id: LayoutID) {
        let own: InkExtent = InkExtent(selfRect(id))
        var ink: InkExtent = own
        if !clipsContent(id) {
            for child in childrenIDs(of: id) {
                ink = ink.union(childInk(child))
            }
        }
        guard self[block: id].paint.ink != ink else { return }
        self[block: id].paint.ink = ink
    }

    /// Floats and absolutely positioned children are layout children of
    /// their block, so a block's extent already covers them when they hang
    /// outside its box.
    private func childInk(_ child: LayoutID) -> InkExtent {
        guard isBlock(child) else { return InkExtent(selfRect(child)) }
        return self[block: child].paint.ink ?? .unbounded
    }

    /// The same boxes paint clips to their padding box.
    private func clipsContent(_ id: LayoutID) -> Bool {
        switch domView(id).style.computed.layout.overflow {
        case .hidden, .clip, .scroll:
            return true
        case .visible, .auto, .other:
            return false
        }
    }
}
