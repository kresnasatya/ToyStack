import Foundation

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

extension LayoutKind {
    var documentPageZoom: CGFloat {
        if case .document(let data) = self { return data.pageZoom }
        return 1
    }
}
