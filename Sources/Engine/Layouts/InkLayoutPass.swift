import CoreGraphics

// MARK: - InkLayoutPass

extension LayoutTree {
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

    private func childInk(_ child: LayoutID) -> InkExtent {
        guard isBlock(child) else { return InkExtent(selfRect(child)) }
        return self[block: child].paint.ink ?? .unbounded
    }

    private func clipsContent(_ id: LayoutID) -> Bool {
        switch domView(id).style.computed.layout.overflow {
        case .hidden, .clip, .scroll:
            return true
        case .visible, .auto, .other:
            return false
        }
    }
}
