import Testing

@testable import Engine

@Suite
struct PageColorsTests {
    private let light: ColorPreferences = ColorPreferences(prefersDark: false, usesForcedColors: false)
    private let dark: ColorPreferences = ColorPreferences(prefersDark: true, usesForcedColors: false)
    private let forced: ColorPreferences = ColorPreferences(prefersDark: false, usesForcedColors: true)
    private let page: BrowserColor = BrowserColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255)

    @Test func pageWithoutBackgroundGetsTheBrowserDefault() {
        #expect(PageColors(preferences: light, canvasBackground: nil).canvas == BrowserColor(cssName: "white"))
        #expect(PageColors(preferences: dark, canvasBackground: nil).canvas == BrowserColor(cssName: "black"))
    }

    @Test func pageBackgroundReplacesTheDefault() {
        #expect(PageColors(preferences: light, canvasBackground: page).canvas == page)
        #expect(PageColors(preferences: dark, canvasBackground: page).canvas == page)
    }

    // CSS Color Adjustment 1 §3.1: forced colors mode adjusts background colors to the
    // user's palette.
    @Test func forcedColorsIgnoreThePageBackground() {
        #expect(PageColors(preferences: forced, canvasBackground: page).canvas == BrowserColor(cssName: ForcedColor.canvas))
    }

    @Test func halfTransparentBackgroundIsBlendedOverTheDefault() {
        let halfBlack: BrowserColor = BrowserColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let blended: BrowserColor = PageColors(preferences: light, canvasBackground: halfBlack).canvas
        #expect(blended == BrowserColor(red: 0.5, green: 0.5, blue: 0.5))
    }
}
