import Engine
import SwiftUI

struct TabStrip: View {
    @ObservedObject var browser: Browser

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(browser.tabs.indices, id: \.self) { (index: Int) in
                        tabButton(browser.tabs[index])
                    }
                }
            }
            Button(action: { browser.newTab(WebURL("about:blank")) }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tabButton(_ tab: BrowserTab) -> some View {
        let isActive: Bool = tab === browser.activeTab
        return Button(action: { browser.selectTab(tab) }) {
            Text(label(for: tab))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 80, maxWidth: 200)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .help(label(for: tab))
    }

    private func label(for tab: BrowserTab) -> String {
        let title: String = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "New Tab" : title
    }
}
