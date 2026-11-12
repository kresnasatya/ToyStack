import Testing

@testable import Engine

@Suite
@MainActor
struct TextDirectionResolverTests {
    @Test(arguments: [
        "\u{05D0}", "\u{0627}", "\u{0710}", "\u{0750}", "\u{0780}",
        "\u{07CA}", "\u{08A0}", "\u{FB2A}", "\u{FB50}", "\u{FE8D}",
    ])

    func firstLetterFromARightToLeftScriptMakesAutoRightToLeft(letter: String) {
        #expect(Self.direction(html: #"<p id="p" dir="auto">\#(letter)</p>"#) == .rtl)
    }

    @Test func latinFirstLetterMakesAutoLeftToRight() {
        #expect(Self.direction(html: #"<p id="p" dir="auto">a \#u{05D0}</p>"#) == .ltr)
    }

    @Test func letterOutsideEveryRightToLeftScriptMakesAutoLeftToRight() {
        #expect(Self.direction(html: #"<p id="p" dir="auto">\#u{0905}</p>"#) == .ltr)
    }

    @Test func digitsAreSkippedWhenLookingForTheFirstLetter() {
        #expect(Self.direction(html: #"<p id="p" dir="auto">123 \#u{05D0}</p>"#) == .rtl)
    }

    @Test func textWithoutLettersKeepsTheInheritedDirection() {
        #expect(Self.direction(html: #"<div dir="rtl"><p id="p" dir="auto">123</p></div>"#) == .rtl)
    }

    private static func direction(html: String) -> TextDirection? {
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: """
                body { display: block; }
                div { display: block; }
                p { display: block; }
            """
        )
        return page.firstElement(id: "p")?.ref.style.computed.text.direction
    }
}
