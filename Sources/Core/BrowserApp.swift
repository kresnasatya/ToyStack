import Combine
import SwiftUI

@MainActor
class BrowserApp: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTab: BrowserTab? {
        didSet {
            tabObserver = activeTab?.$renderVersion
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    let chrome: BrowserChrome
    private var tabObserver: AnyCancellable?

    init() {
        chrome = BrowserChrome()
        chrome.browser = self
    }

    func newTab(_ url: BrowserURL) async {
        let tab = BrowserTab(tabHeight: HEIGHT - chrome.bottom)
        await tab.load(url)
        activeTab = tab
        tabs.append(tab)
    }
}
