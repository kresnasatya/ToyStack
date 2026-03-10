import Combine
import SwiftUI

@MainActor
public class BrowserApp: ObservableObject {
    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTab: BrowserTab? {
        didSet {
            tabObserver = activeTab?.$renderVersion
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    public let chrome: BrowserChrome
    private var tabObserver: AnyCancellable?

    public init() {
        chrome = BrowserChrome()
        chrome.browser = self
    }

    public func newTab(_ url: WebURL) async {
        let tab = BrowserTab(tabHeight: HEIGHT - chrome.bottom)
        await tab.load(url)
        activeTab = tab
        tabs.append(tab)
    }
}
