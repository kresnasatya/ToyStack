import Foundation

/// Tagged payload of one layout node.
enum LayoutKind {
    case document(DocumentData)
    case block(BlockData)
    case line(LineData)
    case text(TextData)
    case embed(EmbedData)
}

extension LayoutKind {
    var isBlock: Bool {
        if case .block = self { return true }
        return false
    }
}
