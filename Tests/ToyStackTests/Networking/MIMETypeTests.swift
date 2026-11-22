import Testing

@testable import Engine

@Suite
struct MIMETypeTests {
    @Test func serverSendingXJavaScriptIsTreatedAsJavaScript() {
        #expect(MIMEType.isJavaScript("application/x-javascript"))
        #expect(MIMEType.isJavaScript("Application/X-JavaScript; charset=utf-8"))
    }

    // MIME Sniffing §4.6 lists text/javascript1.0 through text/javascript1.5, and no others.
    @Test func versionedJavaScriptTypesStopAtOnePointFive() {
        #expect(MIMEType.isJavaScriptEssenceMatch("text/javascript1.0"))
        #expect(MIMEType.isJavaScriptEssenceMatch("text/javascript1.5"))
        #expect(!MIMEType.isJavaScriptEssenceMatch("text/javascript1.6"))
        #expect(!MIMEType.isJavaScriptEssenceMatch("text/javascript2.0"))
    }

    @Test func nonJavaScriptTypesAreRefused() {
        #expect(!MIMEType.isJavaScript("application/json"))
        #expect(!MIMEType.isJavaScript("text/plain"))
        #expect(!MIMEType.isJavaScript(nil))
    }
}
