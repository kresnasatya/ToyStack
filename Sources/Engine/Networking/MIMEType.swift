import Foundation

// MARK: - MIMEType

enum MIMEType {

    static func essence(_ contentType: String?) -> String {
        guard let contentType else { return "" }
        let head: String.SubSequence = contentType.split(separator: ";", maxSplits: 1).first ?? ""
        return head.trimmingCharacters(in: .whitespaces).lowercased()
    }

    // MIME Sniffing §4.6 "MIME type groups": the JavaScript MIME type essences.
    private static let javaScriptTypes: Set<String> = [
        "application/ecmascript",
        "application/javascript",
        "application/x-ecmascript",
        "application/x-javascript",
        "text/ecmascript",
        "text/javascript",
        "text/javascript1.0",
        "text/javascript1.1",
        "text/javascript1.2",
        "text/javascript1.3",
        "text/javascript1.4",
        "text/javascript1.5",
        "text/jscript",
        "text/livescript",
        "text/x-ecmascript",
        "text/x-javascript",
    ]

    static func isJavaScript(_ contentType: String?) -> Bool {
        javaScriptTypes.contains(essence(contentType))
    }

    static func isJavaScriptEssenceMatch(_ string: String) -> Bool {
        javaScriptTypes.contains(string.lowercased())
    }

    static func isCSS(_ contentType: String?) -> Bool {
        essence(contentType) == "text/css"
    }
}
