import Testing

@testable import Engine

@Suite
struct ScriptTypeTests {
    @Test func scriptWithoutTypeOrWithEmptyTypeRuns() {
        #expect(ScriptType.isClassic([:]))
        #expect(ScriptType.isClassic(["type": ""]))
        #expect(ScriptType.isClassic(["language": ""]))
    }

    @Test func javaScriptTypesRunWhateverTheirCaseAndSpacing() {
        #expect(ScriptType.isClassic(["type": "text/javascript"]))
        #expect(ScriptType.isClassic(["type": "  Text/JavaScript\n"]))
        #expect(ScriptType.isClassic(["type": "application/ecmascript"]))
        #expect(ScriptType.isClassic(["language": "JavaScript"]))
    }

    @Test func versionedLanguageAttributeRuns() {
        #expect(ScriptType.isClassic(["language": "JavaScript1.2"]))
        #expect(ScriptType.isClassic(["type": "application/x-javascript"]))
    }

    @Test func dataBlocksDoNotRun() {
        #expect(!ScriptType.isClassic(["type": "application/json"]))
        #expect(!ScriptType.isClassic(["type": "application/ld+json"]))
        #expect(!ScriptType.isClassic(["type": "text/plain"]))
        #expect(!ScriptType.isClassic(["language": "vbscript"]))
    }

    // HTML §4.12.1.1: the type string is compared whole, so parameters or a type made
    // only of spaces do not count as JavaScript.
    @Test func typeWithParametersOrOnlySpacesDoesNotRun() {
        #expect(!ScriptType.isClassic(["type": "text/javascript; charset=utf-8"]))
        #expect(!ScriptType.isClassic(["type": "   "]))
    }

    @Test func typeAttributeWinsOverLanguage() {
        #expect(!ScriptType.isClassic(["type": "text/plain", "language": "javascript"]))
    }

    @Test func modulesAndImportMapsAreNotRunAsClassicScripts() {
        #expect(!ScriptType.isClassic(["type": "module"]))
        #expect(!ScriptType.isClassic(["type": "importmap"]))
    }
}
