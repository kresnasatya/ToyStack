import Combine
import SwiftUI

@MainActor
public class Browser: ObservableObject {
    @Published public var tabs: [Engine.Tab] = []
    @Published public var activeTab: Engine.Tab? {
        didSet {
            tabObserver = activeTab?.$renderVersion
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    public let chrome: Chrome
    private var tabObserver: AnyCancellable?

    public init() {
        chrome = Chrome()
        chrome.tabManager = self
    }

    public func newTab(_ url: WebURL) async {
        let tab = Engine.Tab(tabHeight: HEIGHT - chrome.bottom)
        await tab.load(url)
        activeTab = tab
        tabs.append(tab)
    }
}

// Explicitly declares Browser as a TabManager implementor.
// All required members (tabs, activeTab, newTab) are already defined in the class.
extension Browser: TabManager {}
