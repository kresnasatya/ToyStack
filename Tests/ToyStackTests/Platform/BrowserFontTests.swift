import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
struct BrowserFontTests {
    @Test func fontCacheHandlesConcurrentLookups() {
        let missing: [String] = (0..<8).map { "missing-\($0)" }
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let family: String = index.isMultiple(of: 2) ? "serif" : "monospace"
            let font: BrowserFont = getFont(
                size: 16 + index % 4,
                weight: index.isMultiple(of: 3) ? "bold" : "normal",
                style: index.isMultiple(of: 5) ? "italic" : "roman",
                family: family
            )
            _ = font.measure("thread-safe font cache")
            _ = missing[index % missing.count]
        }
        let first: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")
        let second: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")
        #expect(first.size == second.size)
    }

    @Test func caretOffsetsStepOncePerCharacterAndEndAtTheMeasuredWidth() {
        let font: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")

        let offsets: [CGFloat] = font.caretOffsets("hello")

        #expect(offsets.count == 6)
        #expect(offsets.first == 0)
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy({ $0 < $1 }))
        #expect(abs((offsets.last ?? 0) - font.measure("hello")) < 0.5)
    }

    @Test func caretOffsetsNeverSplitAnEmoji() {
        let font: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")

        #expect(font.caretOffsets("a👍🏽b").count == 4)
        #expect(font.caretOffsets("").count == 1)
    }
}
