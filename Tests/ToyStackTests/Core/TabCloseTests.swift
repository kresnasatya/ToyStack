import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct TabCloseTests {

    @Test func closingTheActiveTabShowsTheTabToItsRight() throws {
        let browser: Browser = Self.browser(tabCount: 3)
        let first: BrowserTab = browser.tabs[0]
        let middle: BrowserTab = browser.tabs[1]
        let last: BrowserTab = browser.tabs[2]
        browser.selectTab(middle)

        browser.closeTab(middle)

        #expect(browser.tabs.count == 2)
        #expect(browser.tabs.first === first)
        #expect(browser.activeTab === last)
    }

    @Test func closingTheRightmostActiveTabShowsTheTabToItsLeft() throws {
        let browser: Browser = Self.browser(tabCount: 3)
        let middle: BrowserTab = browser.tabs[1]
        let last: BrowserTab = browser.tabs[2]
        #expect(browser.activeTab === last)

        browser.closeTab(last)

        #expect(browser.tabs.count == 2)
        #expect(browser.activeTab === middle)
    }

    @Test func closingABackgroundTabKeepsTheCurrentTab() throws {
        let browser: Browser = Self.browser(tabCount: 3)
        let first: BrowserTab = browser.tabs[0]
        let last: BrowserTab = browser.tabs[2]

        browser.closeTab(first)

        #expect(browser.tabs.count == 2)
        #expect(!browser.tabs.contains(where: { $0 === first }))
        #expect(browser.activeTab === last)
    }

    @Test func closingTheLastTabLeavesNothingOnScreen() throws {
        let browser: Browser = Self.browser(tabCount: 1)
        let only: BrowserTab = try #require(browser.activeTab)
        var presented: PresentedFrame? = nil
        browser.onPresent = { (frame: PresentedFrame) in presented = frame }

        browser.closeTab(only)

        #expect(browser.tabs.isEmpty)
        #expect(browser.activeTab == nil)
        #expect(browser.cursor == .auto)
        #expect(presented?.content.image == nil)
    }

    @Test func closingATabTwiceClosesOnlyThatTab() throws {
        let browser: Browser = Self.browser(tabCount: 3)
        let first: BrowserTab = browser.tabs[0]
        let last: BrowserTab = browser.tabs[2]
        browser.closeTab(first)

        browser.closeTab(first)

        #expect(browser.tabs.count == 2)
        #expect(browser.activeTab === last)
    }

    @Test func aClosedTabIsFreed() async throws {
        let browser: Browser = Self.browser(tabCount: 2)
        weak var closed: BrowserTab? = browser.tabs[1]
        #expect(await Self.pump({ closed?.isLoaded == true }))

        browser.closeTab(try #require(closed))

        #expect(await Self.pump({ closed == nil }))
    }

    // MARK: - Helpers

    private static func browser(tabCount: Int) -> Browser {
        let browser: Browser = Browser()
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        for _ in 0..<tabCount {
            browser.newTab(WebURL("about:blank"))
        }
        browser.pauseAnimationTimer()
        return browser
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}
