import Combine
import SwiftUI

@MainActor
public class Browser: ObservableObject {
    @Published public var tabs: [Core.Tab] = []
    @Published public var activeTab: Core.Tab? {
        didSet {
            tabObserver = activeTab?.$renderVersion
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    public let chrome: Chrome
    private var tabObserver: AnyCancellable?

    public init() {
        chrome = Chrome()
        chrome.browser = self
    }

    public func newTab(_ url: WebURL) async {
        let tab = Core.Tab(tabHeight: HEIGHT - chrome.bottom)
        await tab.load(url)
        activeTab = tab
        tabs.append(tab)
    }
}

// BrowserURL -> WebURL
// Rename module Core into Engine
