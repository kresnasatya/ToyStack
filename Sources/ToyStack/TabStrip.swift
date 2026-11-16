import Engine
import SwiftUI

struct TabStrip: View {
    @ObservedObject var browser: Browser

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(browser.tabs) { (tab: BrowserTab) in
                        tabButton(tab)
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
        return HStack(spacing: 2) {
            Button(action: { browser.selectTab(tab) }) {
                Text(label(for: tab))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 80, maxWidth: 200)
                    .padding(.leading, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(label(for: tab))

            Button(action: { browser.closeTab(tab) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Close Tab")
        }
        .foregroundStyle(isActive ? .primary : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
    }

    private func label(for tab: BrowserTab) -> String {
        let title: String = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "New Tab" : title
    }
}
