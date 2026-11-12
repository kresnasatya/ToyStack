import Testing

@testable import Engine

@Suite
struct PrePassStylesTests {
    @Test func interleavedEntriesComeBackInRecordOrder() {
        var block: ComputedStyle = .initial
        block.layout.display = .block
        var large: ComputedStyle = .initial
        large.text.font.size = 30
        var red: TextStyle = .initial
        red.color = BrowserColor(cssName: "red")
        var blue: TextStyle = .initial
        blue.color = BrowserColor(cssName: "blue")

        var styles: PrePassStyles = PrePassStyles()
        styles.append(block)
        styles.append(text: red)
        styles.append(text: blue)
        styles.append(large)

        #expect(styles[0] == .full(block))
        #expect(styles[1] == .text(red))
        #expect(styles[2] == .text(blue))
        #expect(styles[3] == .full(large))
    }
}
