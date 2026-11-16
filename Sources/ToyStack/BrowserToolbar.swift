import Engine
import SwiftUI

struct BrowserToolbar: ToolbarContent {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    let addressFocus: AddressFocus

    private var currentAddress: String? { browser.activeTab?.url?.toString() }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: { browser.activeTab?.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .help("Back")
            .disabled(!(browser.activeTab?.canGoBack ?? false))

            Button(action: { browser.activeTab?.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .help("Forward")
            .disabled(!(browser.activeTab?.canGoForward ?? false))

            Button(action: { browser.activeTab?.reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload This Page")
            .disabled(browser.activeTab == nil)
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                if browser.activeTab?.isSecure ?? false {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                AddressBar(address: currentAddress ?? "", browser: browser, focus: addressFocus)
            }
            .frame(minWidth: 240, idealWidth: 560, maxWidth: 800)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: toggleBookmark) {
                Image(systemName: isBookmarked ? "star.fill" : "star")
            }
            .help(isBookmarked ? "Remove Bookmark" : "Add Bookmark")
            .disabled(currentAddress == nil)
        }
    }

    private var isBookmarked: Bool {
        guard let address: String = currentAddress else { return false }
        return bookmarks.contains(address)
    }

    private func toggleBookmark() {
        guard let address: String = currentAddress else { return }
        bookmarks.toggle(address)
    }
}
