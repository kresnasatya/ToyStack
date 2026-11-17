import Engine
import SwiftUI

struct ChromeView<Page: View>: View {
    let browser: Browser
    let bookmarks: Bookmarks
    let addressFocus: AddressFocus
    let page: Page

    init(browser: Browser, bookmarks: Bookmarks, addressFocus: AddressFocus, @ViewBuilder page: () -> Page) {
        self.browser = browser
        self.bookmarks = bookmarks
        self.addressFocus = addressFocus
        self.page = page()
    }

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(browser: browser)
            Divider()
            DidYouMeanBar(browser: browser)
            page
        }
        .toolbar {
            BrowserToolbar(browser: browser, bookmarks: bookmarks, addressFocus: addressFocus)
        }
    }
}
