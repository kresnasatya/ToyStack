import Foundation

// MARK: - MIMEType

enum MIMEType {

    static func essence(_ contentType: String?) -> String {
        guard let contentType else { return "" }
        let head = contentType.split(separator: ";", maxSplits: 1).first ?? ""
        return head.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static let javaScriptTypes: Set<String> = [
        "application/ecmascript",
        "application/javascript",
        "application/x-ecmascript",
        "application/x-ecmascript",
        "text/ecmascript",
        "text/javascript",
        "text/jscript",
        "text/livescript",
        "text/x-ecmascript",
        "text/x-javascript",
    ]

    static func isJavaScript(_ contentType: String?) -> Bool {
        javaScriptTypes.contains(essence(contentType))
    }

    static func isCSS(_ contentType: String?) -> Bool {
        essence(contentType) == "text/css"
    }
}
