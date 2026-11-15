import Foundation

public enum AddressInput {
    private static let schemePrefixes: [String] = [
        "http://", "https://", "file://", "about:", "view-source:", "data:",
    ]
    private static let searchPrefix: String = "https://google.com/search?q="
    private static let queryWordCharacters: CharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func url(for typed: String) -> WebURL? {
        let input: String = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            return nil
        }
        if schemePrefixes.contains(where: { (prefix: String) -> Bool in input.hasPrefix(prefix) }) {
            return WebURL(input)
        }
        if input.contains(".") && !input.contains(where: { (c: Character) -> Bool in c.isWhitespace }) {
            return WebURL("https://\(input)")
        }
        return WebURL(searchPrefix + searchQuery(input))
    }

    private static func searchQuery(_ text: String) -> String {
        let words: [String] = text.split(whereSeparator: { (c: Character) -> Bool in c.isWhitespace }).map {
            (word: Substring) -> String in
            word.addingPercentEncoding(withAllowedCharacters: queryWordCharacters) ?? ""
        }
        return words.joined(separator: "+")
    }
}
