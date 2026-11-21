import Testing

@testable import Engine

@Suite struct PathPercentEncodingTests {
    @Test(arguments: [
        ("/plain/page.js", "/plain/page.js"),
        ("/app/%5Blang%5D/page.js", "/app/%5Blang%5D/page.js"),
        ("/app/%5blang%5d/page.js", "/app/%5blang%5d/page.js"),
        ("/app/[lang]/page.js", "/app/%5Blang%5D/page.js"),
        ("/a b/c.js", "/a%20b/c.js"),
        ("/caf\u{E9}", "/caf%C3%A9"),
        ("/100%", "/100%25"),
        ("/a%zz/b", "/a%25zz/b"),
        ("/cut%4", "/cut%254"),
    ])
    func encodesPathForTheRequest(input: String, expected: String) {
        #expect(PathPercentEncoding.encode(input) == expected)
    }
}
