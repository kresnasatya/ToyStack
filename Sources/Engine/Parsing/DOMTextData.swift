import Foundation

/// Text payload for a DOM node. Named `DOMTextData` because the layout
/// payload `TextData` already exists in the same module.
struct DOMTextData {
    var text: String
}
