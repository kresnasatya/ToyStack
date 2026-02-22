// The Swift Programming Language
// https://docs.swift.org/swift-book

@main
struct ToyStack {
    static func main() async throws {
        let url = URL("https://example.com")
        let (headers, content) = try await url.request()
        print("Headers: ", headers)
        print("Content: ", content)
    }
}
