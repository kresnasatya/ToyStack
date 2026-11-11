import Foundation

/// The run owns the UTF-16 text and the character range of every item, so a
/// line fragment only stores `(start item, count)`.
final class TextRun {
    let text: String
    let starts: [Int]
    let ends: [Int]

    init(items: [InlineItem]) {
        var text: String = ""
        var starts: [Int] = []
        var ends: [Int] = []
        starts.reserveCapacity(items.count)
        ends.reserveCapacity(items.count)
        for item in items {
            starts.append(text.utf16.count)
            if case .text(let data) = item {
                if !text.isEmpty {
                    text += " "
                }
                text += data.display ?? data.word
            }
            ends.append(text.utf16.count)
        }
        self.text = text
        self.starts = starts
        self.ends = ends
    }

    func string(start: Int, count: Int) -> String {
        guard count > 0 else { return "" }
        let endIndex: Int = start + count - 1
        guard start >= 0, endIndex < starts.count, endIndex < ends.count else {
            return text
        }
        let lower: Int = starts[start]
        let upper: Int = ends[endIndex]
        guard upper > lower else { return "" }
        return (text as NSString).substring(with: NSRange(location: lower, length: upper - lower))
    }
}

struct TextFragment: Equatable {
    let block: LayoutID
    let start: Int
    let count: Int
}
