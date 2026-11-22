import Testing

@testable import Engine

@Suite
struct BorderShorthandTests {
    private static let sides: [String] = ["top", "right", "bottom", "left"]

    private func declarations(_ body: String) -> [String: String] {
        return CSSParser(body).body()
    }

    @Test func borderSetsEverySide() {
        let props: [String: String] = declarations("border: 2px dashed red;")

        for side in Self.sides {
            #expect(props["border-\(side)-width"] == "2px")
            #expect(props["border-\(side)-style"] == "dashed")
            #expect(props["border-\(side)-color"] == "red")
        }
        #expect(props["border-width"] == nil)
    }

    @Test func borderSideShorthandSetsOnlyThatSide() {
        let props: [String: String] = declarations("border-bottom: 1px solid gray;")

        #expect(props == [
            "border-bottom-width": "1px",
            "border-bottom-style": "solid",
            "border-bottom-color": "gray",
        ])
    }

    @Test func borderWidthTakesOneToFourValues() {
        let four: [String: String] = declarations("border-width: 1px 2px 3px 4px;")
        #expect(four["border-top-width"] == "1px")
        #expect(four["border-right-width"] == "2px")
        #expect(four["border-bottom-width"] == "3px")
        #expect(four["border-left-width"] == "4px")

        let two: [String: String] = declarations("border-width: 1px 2px;")
        #expect(two["border-bottom-width"] == "1px")
        #expect(two["border-left-width"] == "2px")

        let three: [String: String] = declarations("border-width: 1px 2px 3px;")
        #expect(three["border-left-width"] == "2px")
    }

    @Test func borderStyleAndColorSpreadLikeBorderWidth() {
        let props: [String: String] = declarations(
            "border-style: solid none; border-color: red rgb(0, 0, 255) gold;"
        )

        #expect(props["border-top-style"] == "solid")
        #expect(props["border-right-style"] == "none")
        #expect(props["border-bottom-style"] == "solid")
        #expect(props["border-left-style"] == "none")
        #expect(props["border-right-color"] == "rgb(0, 0, 255)")
        #expect(props["border-bottom-color"] == "gold")
        #expect(props["border-left-color"] == "rgb(0, 0, 255)")
    }

    @Test func outlineKeepsItsSingleProperties() {
        let props: [String: String] = declarations("outline: 3px solid blue;")

        #expect(props == [
            "outline-width": "3px",
            "outline-style": "solid",
            "outline-color": "blue",
        ])
    }

    @Test func unitlessZeroIsTheWidth() {
        let props: [String: String] = declarations("border: 0 solid #e5e7eb;")

        for side in Self.sides {
            #expect(props["border-\(side)-width"] == "0")
            #expect(props["border-\(side)-style"] == "solid")
            #expect(props["border-\(side)-color"] == "#e5e7eb")
        }
    }
}
