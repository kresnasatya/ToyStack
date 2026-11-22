import Foundation

// MARK: - ScriptType

enum ScriptType {
    private static let asciiWhitespace: CharacterSet = CharacterSet(charactersIn: "\t\n\u{0C}\r ")

    // HTML §4.12.1.1 "prepare the script element", steps 10–11: a script with an empty type,
    // an empty language, or neither attribute is classic; otherwise only a type string that is a
    // JavaScript MIME type essence match is. Anything else (JSON data blocks, templates,
    // "text/plain") is data the page reads itself, and is not run.
    static func isClassic(_ attributes: [String: String]) -> Bool {
        if let type: String = attributes["type"] {
            if type.isEmpty { return true }
            return MIMEType.isJavaScriptEssenceMatch(type.trimmingCharacters(in: asciiWhitespace))
        }
        if let language: String = attributes["language"] {
            if language.isEmpty { return true }
            return MIMEType.isJavaScriptEssenceMatch("text/" + language)
        }
        return true
    }
}
