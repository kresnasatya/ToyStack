/// Single owner of a layout tree value.
///
/// The tree is a value, so something has to hold it. The frame owns the box;
/// the DOM keeps a weak reference so DOM-side code can resolve layout ids
/// without owning layout state.
final class LayoutBox {
    var tree: LayoutTree

    init(_ tree: LayoutTree) {
        self.tree = tree
    }
}
