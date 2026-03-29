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
    public var windowSize: CGSize = CGSize(width: WIDTH, height: HEIGHT)
    private var tabObserver: AnyCancellable?
    private var animationTimer: Timer?
    public var accessibilityIsOn: Bool = false

    public init() {
        chrome = Chrome()
        chrome.tabManager = self
    }

    public func newTab(_ url: WebURL) async {
        let tab = Engine.Tab(
            tabHeight: windowSize.height - chrome.bottom,
            tabWidth: windowSize.width
        )
        await tab.load(url)
        activeTab = tab
        tabs.append(tab)
        startAnimationTimer()
    }

    public func resize(to size: CGSize) {
        windowSize = size
        chrome.resize(width: size.width)
        activeTab?.resize(width: size.width, height: size.height - chrome.bottom)
    }

    public func startAnimationTimer() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0, repeats: true
        ) {
            [weak self] _ in
            Task { @MainActor in
                self?.animationTick()
            }
        }
    }

    public func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func animationTick() {
        activeTab?.runAnimationFrame()
    }
}

// Explicitly declares Browser as a TabManager implementor.
// All required members (tabs, activeTab, newTab) are already defined in the class.
extension Browser: TabManager {}
