import Engine
import SwiftUI

/// Chrome's "Did you mean to go to http://intranet/?" bar, shown when a
/// single searched word turns out to name a machine on the network.
struct DidYouMeanBar: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if let tab: BrowserTab = browser.activeTab, let url: WebURL = tab.didYouMean {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Did you mean to go to")
                    Button(url.toString(), action: { tab.load(url) })
                        .buttonStyle(.link)
                    Text("?")
                    Spacer()
                    Button(action: { tab.dismissDidYouMean() }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}
