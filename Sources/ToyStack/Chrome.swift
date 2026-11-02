import Engine
import CoreGraphics

@MainActor
public protocol TabManager: AnyObject {
    var tabs: [BrowserTab] { get }
    var activeTab: BrowserTab? { get }
    func newTab(_ url: WebURL)
    func selectTab(_ tab: BrowserTab)
    var prefersDark: Bool { get }
    var forcedColors: Bool { get }
}

@MainActor
public class Chrome {
    weak var tabManager: (any TabManager)?
    var bookmarks: Bookmarks?
    private let font: BrowserFont
    private let fontHeight: CGFloat
    private let padding: CGFloat = 5

    public let bottom: CGFloat

    private let tabbarTop: CGFloat
    private let tabbarBottom: CGFloat
    private let urlbarTop: CGFloat
    private let urlbarBottom: CGFloat

    private let newtabRect: Rect
    private let backRect: Rect
    private let forwardRect: Rect
    private var addressRect: Rect {
        Rect(
            left: bookmarkRect.right + padding,
            top: urlbarTop + padding,
            right: currentWidth - padding,
            bottom: urlbarBottom - padding
        )
    }
    private let bookmarkRect: Rect

    private var focus: String?
    public var hasFocus: Bool { focus != nil }
    private var addressBar: String = ""
    private var cursorIndex: Int = 0
    private var isAllSelected: Bool = false

    private var currentWidth: CGFloat = WIDTH

    init() {
        font = getFont(size: 20, weight: "normal", style: "normal")
        fontHeight = font.linespace

        tabbarTop = 0
        tabbarBottom = fontHeight + 2 * padding

        let plusWidth = font.measure("+") + 2 * padding
        newtabRect = Rect(
            left: padding, top: padding, right: padding + plusWidth, bottom: padding + fontHeight)

        urlbarTop = tabbarBottom
        urlbarBottom = urlbarTop + fontHeight + 2 * padding
        bottom = urlbarBottom

        let backWidth = font.measure("<") + 2 * padding
        backRect = Rect(
            left: padding, top: urlbarTop + padding, right: padding + backWidth,
            bottom: urlbarBottom - padding)
        let forwardWidth = font.measure(">") + 2 * padding
        forwardRect = Rect(
            left: backRect.right + padding, top: urlbarTop + padding,
            right: backRect.right + padding + forwardWidth, bottom: urlbarBottom - padding)

        let bookmarkWidth = font.measure("*") + 2 * padding
        bookmarkRect = Rect(
            left: forwardRect.right + padding, top: urlbarTop + padding,
            right: forwardRect.right + padding + bookmarkWidth,
            bottom: urlbarBottom - padding)
    }

    private func tabRect(_ i: Int) -> Rect {
        let tabsStart = newtabRect.right + padding
        let tabWidth = font.measure("Tab X") + 2 * padding
        return Rect(
            left: tabsStart + tabWidth * CGFloat(i), top: tabbarTop,
            right: tabsStart + tabWidth * CGFloat(i + 1), bottom: tabbarBottom)
    }

    func resize(width: CGFloat) {
        currentWidth = width
    }

    public func paint() -> [DisplayOp] {
        var cmds: [DisplayOp] = []

        let forced = tabManager?.forcedColors ?? false
        let darkMode = tabManager?.prefersDark ?? false
        let color = forced ? ForcedColor.canvasText : (darkMode ? "white" : "black")
        let bgColor = forced ? ForcedColor.canvas : (darkMode ? "black" : "white")

        cmds.append(
            .rect(rect: Rect(left: 0, top: 0, right: currentWidth, bottom: bottom), color: BrowserColor(cssName: bgColor)))
        cmds.append(
            .line(from: Point(x: 0, y: bottom), to: Point(x: currentWidth, y: bottom), color: BrowserColor(cssName: color), width: 1)
        )

        cmds.append(.outline(rect: newtabRect, color: BrowserColor(cssName: color), width: 1))
        cmds.append(
            .text(
                text: "+",
                font: font,
                color: BrowserColor(cssName: color),
                rect: Rect(
                    left: newtabRect.left + padding,
                    top: newtabRect.top,
                    right: newtabRect.left + padding + font.measure("+"),
                    bottom: newtabRect.top + font.linespace
                )
            )
        )

        let tabs: [BrowserTab] = tabManager?.tabs ?? []
        for (i, tab) in tabs.enumerated() {
            let bounds = tabRect(i)
            cmds.append(
                .line(
                    from: Point(x: bounds.left, y: 0),
                    to: Point(x: bounds.left, y: bounds.bottom),
                    color: BrowserColor(cssName: color),
                    width: 1
                )
            )
            cmds.append(
                .line(
                    from: Point(x: bounds.right, y: 0),
                    to: Point(x: bounds.right, y: bounds.bottom),
                    color: BrowserColor(cssName: color),
                    width: 1
                )
            )
            cmds.append(
                .text(
                    text: "Tab \(i)",
                    font: font,
                    color: BrowserColor(cssName: color),
                    rect: Rect(
                        left: bounds.left + padding,
                        top: bounds.top + padding,
                        right: bounds.left + padding + font.measure("Tab \(i)"),
                        bottom: bounds.top + padding + font.linespace
                    )
                )
            )
            if tab === tabManager?.activeTab {
                cmds.append(
                    .line(
                        from: Point(x: 0, y: bounds.bottom),
                        to: Point(x: bounds.left, y: bounds.bottom),
                        color: BrowserColor(cssName: color),
                        width: 1
                    )
                )
                cmds.append(
                    .line(
                        from: Point(x: bounds.right, y: bounds.bottom),
                        to: Point(x: currentWidth, y: bounds.bottom),
                        color: BrowserColor(cssName: color),
                        width: 1
                    )
                )
            }
        }

        let backColor = tabManager?.activeTab?.canGoBack == true ? color : "gray"
        cmds.append(.outline(rect: backRect, color: BrowserColor(cssName: backColor), width: 1))
        cmds.append(
            .text(
                text: "<",
                font: font,
                color: BrowserColor(cssName: backColor),
                rect: Rect(
                    left: backRect.left + padding,
                    top: backRect.top,
                    right: backRect.left + padding + font.measure("<"),
                    bottom: backRect.top + font.linespace
                )
            )
        )

        let fwdColor = tabManager?.activeTab?.canGoForward == true ? color : "gray"
        cmds.append(.outline(rect: forwardRect, color: BrowserColor(cssName: fwdColor), width: 1))
        cmds.append(
            .text(
                text: ">",
                font: font,
                color: BrowserColor(cssName: fwdColor),
                rect: Rect(
                    left: forwardRect.left + padding,
                    top: forwardRect.top,
                    right: forwardRect.left + padding + font.measure(">"),
                    bottom: forwardRect.top + font.linespace
                )
            )
        )

        let currentURLStr = tabManager?.activeTab?.url?.toString() ?? ""
        let isBookmarked = bookmarks?.contains(currentURLStr) ?? false
        if isBookmarked {
            cmds.append(.rect(rect: bookmarkRect, color: BrowserColor(cssName: "yellow")))
        }
        cmds.append(.outline(rect: bookmarkRect, color: BrowserColor(cssName: color), width: 1))
        cmds.append(
            .text(
                text: "*",
                font: font,
                color: BrowserColor(cssName: color),
                rect: Rect(
                    left: bookmarkRect.left + padding,
                    top: bookmarkRect.top,
                    right: bookmarkRect.left + padding + font.measure("*"),
                    bottom: bookmarkRect.top + font.linespace
                )
            )
        )

        cmds.append(.outline(rect: addressRect, color: BrowserColor(cssName: color), width: 1))
        if focus == "address bar" {
            if isAllSelected {
                let textWidth = font.measure(addressBar)
                let selRect = Rect(
                    left: addressRect.left + padding, top: addressRect.top,
                    right: addressRect.left + padding + textWidth, bottom: addressRect.bottom)
                cmds.append(.rect(rect: selRect, color: BrowserColor(cssName: "lightblue")))
                cmds.append(
                    .text(
                        text: addressBar,
                        font: font,
                        color: BrowserColor(cssName: color),
                        rect: Rect(
                            left: addressRect.left + padding,
                            top: addressRect.top,
                            right: addressRect.left + padding + font.measure(addressBar),
                            bottom: addressRect.top + font.linespace
                        )
                    )
                )
            } else {
                cmds.append(
                    .text(
                        text: addressBar,
                        font: font,
                        color: BrowserColor(cssName: color),
                        rect: Rect(
                            left: addressRect.left + padding,
                            top: addressRect.top,
                            right: addressRect.left + padding + font.measure(addressBar),
                            bottom: addressRect.top + font.linespace
                        )
                    )
                )
                let textBeforeCursor = String(addressBar.prefix(cursorIndex))
                let w = font.measure(textBeforeCursor)
                cmds.append(
                    .line(
                        from: Point(x: addressRect.left + padding + w, y: addressRect.top),
                        to: Point(x: addressRect.left + padding + w, y: addressRect.bottom),
                        color: BrowserColor(cssName: "red"),
                        width: 1
                    )
                )
            }

        } else if let url = tabManager?.activeTab?.url {
            let isSecure = tabManager?.activeTab?.isSecure ?? false
            let displayText = isSecure ? "\u{1F512} \(url.toString())" : url.toString()
            cmds.append(
                .text(
                    text: displayText,
                    font: font,
                    color: BrowserColor(cssName: color),
                    rect: Rect(
                        left: addressRect.left + padding,
                        top: addressRect.top,
                        right: addressRect.left + padding + font.measure(displayText),
                        bottom: addressRect.top + font.linespace
                    )
                )
            )
        }

        return cmds
    }

    public func click(x: CGFloat, y: CGFloat) {
        focus = nil
        if newtabRect.containsPoint(x, y) {
            tabManager?.newTab(WebURL("about:blank"))
        } else if backRect.containsPoint(x, y) {
            tabManager?.activeTab?.goBack()
        } else if forwardRect.containsPoint(x, y) {
            tabManager?.activeTab?.goForward()
        } else if bookmarkRect.containsPoint(x, y) {
            if let urlStr = tabManager?.activeTab?.url?.toString() {
                bookmarks?.toggle(urlStr)
            }
        } else if addressRect.containsPoint(x, y) {
            focusAddressBar()
        } else {
            let tabs: [BrowserTab] = tabManager?.tabs ?? []
            for (i, tab) in tabs.enumerated() {
                if tabRect(i).containsPoint(x, y) {
                    tabManager?.selectTab(tab)
                    break
                }
            }
        }
    }

    public func keypress(_ char: String) -> Bool {
        if focus == "address bar" {
            if isAllSelected {
                addressBar = char
                cursorIndex = 1
                isAllSelected = false
            } else {
                let idx = addressBar.index(addressBar.startIndex, offsetBy: cursorIndex)
                addressBar.insert(contentsOf: char, at: idx)
                cursorIndex += 1
            }
            return true
        }
        return false
    }

    public func backspace() -> Bool {
        if focus == "address bar" {
            if isAllSelected {
                addressBar = ""
                cursorIndex = 0
                isAllSelected = false
            } else if cursorIndex > 0 {
                let end = addressBar.index(addressBar.startIndex, offsetBy: cursorIndex)
                let start = addressBar.index(before: end)
                addressBar.remove(at: start)
                cursorIndex -= 1
            }
            return true
        }
        return false
    }

    public func cursorLeft() -> Bool {
        if focus == "address bar" {
            if isAllSelected {
                isAllSelected = false
                cursorIndex = 0
            } else {
                cursorIndex = max(0, cursorIndex - 1)
            }
            return true
        }
        return false
    }

    public func cursorRight() -> Bool {
        if focus == "address bar" {
            if isAllSelected {
                isAllSelected = false
                cursorIndex = addressBar.count
            } else {
                cursorIndex = min(addressBar.count, cursorIndex + 1)
            }
            return true
        }
        return false
    }

    @discardableResult
    public func enter() -> Bool {
        if focus == "address bar" {
            let input = addressBar
            focus = nil
            isAllSelected = false
            let rawInput = isURL(input) ? input : nil
            let url: WebURL
            if let raw = rawInput {
                if raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("file://")
                    || raw.hasPrefix("about:")
                {
                    url = WebURL(raw)
                } else {
                    url = WebURL("https://\(raw)")
                }
            } else {
                url = searchURL(for: input)
            }
            tabManager?.activeTab?.load(url)
            focus = nil
            return true
        }
        return false
    }

    public func blur() {
        focus = nil
        isAllSelected = false
    }

    public func focusAddressBar() {
        focus = "address bar"
        addressBar = tabManager?.activeTab?.url?.toString() ?? ""
        cursorIndex = addressBar.count
        isAllSelected = true
    }

    private func isURL(_ input: String) -> Bool {
        input.hasPrefix("http://") || input.hasPrefix("https://") || input.hasPrefix("file://")
            || input.hasPrefix("about:")
            || (input.contains(".") && !input.contains(" "))
    }

    private func searchURL(for query: String) -> WebURL {
        let escaped = query.replacingOccurrences(of: " ", with: "+")
        return WebURL("https://google.com/search?q=\(escaped)")
    }
}
