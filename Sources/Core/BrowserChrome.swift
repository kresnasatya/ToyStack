import CoreGraphics

@MainActor
public class BrowserChrome {
    weak var browser: BrowserApp?

    private let font: BrowserFont
    private let fontHeight: CGFloat
    private let padding: CGFloat = 5

    public let bottom: CGFloat  // total chrome height - tab reads this

    private let tabbarTop: CGFloat
    private let tabbarBottom: CGFloat
    private let urlbarTop: CGFloat
    private let urlbarBottom: CGFloat

    private let newtabRect: Rect
    private let backRect: Rect
    private let addressRect: Rect

    private var focus: String?  // "address bar" or nil
    private var addressBar: String = ""

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

        addressRect = Rect(
            left: backRect.right + padding, top: urlbarTop + padding, right: WIDTH - padding,
            bottom: urlbarBottom - padding)
    }

    private func tabRect(_ i: Int) -> Rect {
        let tabsStart = newtabRect.right + padding
        let tabWidth = font.measure("Tab X") + 2 * padding
        return Rect(
            left: tabsStart + tabWidth * CGFloat(i), top: tabbarTop,
            right: tabsStart + tabWidth * CGFloat(i + 1), bottom: tabbarBottom)
    }

    public func paint() -> [any PaintCommand] {
        var cmds: [any PaintCommand] = []

        // White background + bottom border
        cmds.append(
            DrawRect(rect: Rect(left: 0, top: 0, right: WIDTH, bottom: bottom), color: "white"))
        cmds.append(
            DrawLine(x1: 0, y1: bottom, x2: WIDTH, y2: bottom, color: "black", thickness: 1))

        // New tab button
        cmds.append(DrawOutline(rect: newtabRect, color: "black", thickness: 1))
        cmds.append(
            DrawText(
                x1: newtabRect.left + padding, y1: newtabRect.top, text: "+", font: font,
                color: "black"))

        // Tab buttons
        let tabs: [BrowserTab] = browser?.tabs ?? []
        for (i, tab) in tabs.enumerated() {
            let bounds = tabRect(i)
            cmds.append(
                DrawLine(
                    x1: bounds.left, y1: 0, x2: bounds.left, y2: bounds.bottom, color: "black",
                    thickness: 1))
            cmds.append(
                DrawLine(
                    x1: bounds.right, y1: 0, x2: bounds.right, y2: bounds.bottom, color: "black",
                    thickness: 1))
            cmds.append(
                DrawText(
                    x1: bounds.left + padding, y1: bounds.top + padding, text: "Tab \(i)",
                    font: font, color: "black"))
            if tab === browser?.activeTab {
                cmds.append(
                    DrawLine(
                        x1: 0, y1: bounds.bottom, x2: bounds.left, y2: bounds.bottom,
                        color: "black", thickness: 1))
                cmds.append(
                    DrawLine(
                        x1: bounds.right, y1: bounds.bottom, x2: WIDTH, y2: bounds.bottom,
                        color: "black", thickness: 1))
            }
        }

        // Back button
        cmds.append(DrawOutline(rect: backRect, color: "black", thickness: 1))
        cmds.append(
            DrawText(
                x1: backRect.left + padding, y1: backRect.top, text: "<", font: font, color: "black"
            ))

        // Address bar
        cmds.append(DrawOutline(rect: addressRect, color: "black", thickness: 1))
        if focus == "address bar" {
            cmds.append(
                DrawText(
                    x1: addressRect.left + padding, y1: addressRect.top, text: addressBar,
                    font: font, color: "black"))
            let w = font.measure(addressBar)
            cmds.append(
                DrawLine(
                    x1: addressRect.left + padding + w, y1: addressRect.top,
                    x2: addressRect.left + padding + w, y2: addressRect.bottom, color: "red",
                    thickness: 1))
        } else if let url = browser?.activeTab?.url {
            cmds.append(
                DrawText(
                    x1: addressRect.left + padding, y1: addressRect.top, text: url.toString(),
                    font: font, color: "black"))
        }

        return cmds
    }

    func click(x: CGFloat, y: CGFloat) async {
        focus = nil
        if newtabRect.containsPoint(x, y) {
            await browser?.newTab(BrowserURL("https://browser.engineering"))
        } else if backRect.containsPoint(x, y) {
            await browser?.activeTab?.goBack()
        } else if addressRect.containsPoint(x, y) {
            focus = "address bar"
            addressBar = ""
        } else {
            let tabs: [BrowserTab] = browser?.tabs ?? []
            for (i, tab) in tabs.enumerated() {
                if tabRect(i).containsPoint(x, y) {
                    browser?.activeTab = tab
                    break
                }
            }
        }
    }

    public func keypress(_ char: String) -> Bool {
        if focus == "address bar" {
            addressBar += char
            return true
        }
        return false
    }

    public func enter() async {
        if focus == "address bar" {
            await browser?.activeTab?.load(BrowserURL(addressBar))
            focus = nil
        }
    }

    func blur() {
        focus = nil
    }
}
