import Foundation

/// Closed key for every field that can invalidate layout.
///
/// Layout fields belong to a layout node; style fields belong to the DOM
/// node whose computed style the layout reads.
enum FieldKey: Hashable {
    case layout(LayoutID, LayoutField)
    case style(NodeID, StyleProperty)
}
