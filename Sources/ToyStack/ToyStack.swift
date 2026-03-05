// The Swift Programming Language
// https://docs.swift.org/swift-book

@main
struct ToyStack {
    static func main() async throws {
        let url = URL("https://example.com")
        let (headers, content) = try await url.request()
        print("Headers: ", headers)
        print("Content: ", content)

        // Test HTMLParser
        let html = content
        let parser = HTMLParser(body: html)
        let root = parser.parse()
        print(root)

        // Test HTMLParser - part 2
        let html2 = "<html><body><p>Hello</p></body></html>"
        let parser2 = HTMLParser(body: html2)
        let root2 = parser2.parse()
        print(root2)

        // Test Element and TextNode from DOMNode
        // Top-down: create parent first, then the children
        let div = Element(tag: "div", attributes: ["class": "wrapper"], parent: nil)
        let p = Element(tag: "p", attributes: [:], parent: div)
        let text = TextNode(text: "You're amazing!", parent: p)

        div.children.append(p)
        p.children.append(text)

        print(div)
        print(div.children[0])
        print(div.children[0].children[0])

        // Test Rect
        let rect = Rect(left: 10, top: 20, right: 100, bottom: 80)
        print("Contains (50, 50): ", rect.containsPoint(50, 50))
        print("Contains (5, 50): ", rect.containsPoint(5, 50))
        print("Contains (100, 50): ", rect.containsPoint(100, 50))
        print("CGRect: ", rect.cgRect)
    }
}
