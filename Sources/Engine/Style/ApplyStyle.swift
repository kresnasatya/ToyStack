// MARK: - Inherited CSS Properties
let inheritedPropertyDefaults: [String: String] = [
    "font-family": "serif",
    "font-size": "16px",
    "font-style": "normal",
    "font-weight": "normal",
    "color": "black",
    "white-space": "normal",
    "direction": "ltr"
]

// MARK: - applyStyle
@MainActor
func applyStyle(node: any DOMNode, cascade: StyleCascade) {
    applyStyle(node: node, cascade: cascade, force: false)
}

@MainActor
private func applyStyle(node: any DOMNode, cascade: StyleCascade, force: Bool) {
    guard force || node.style.isDirty || node.style.hasDirtyDescendant else {
        profiler.count("style.skipped")
        return
    }
    profiler.count("style.visited")
    if node.style.hasDirtyDescendant {
        profiler.count("style.dirtyDescendants")
    }
    defer { node.style.clearDirtyDescendants() }

    let direct: Bool = cascade.scope.map({ $0.matches(node) }) ?? true
    let applies: Bool = force || direct
    if applies {
        cascade.record(node)
        applyNodeStyle(node: node, cascade: cascade)
    }

    let pushedElement: Element? = node as? Element
    let pushedKeys: [SelectorKey]? = pushedElement.map({ element in
        profiler.measure("style.apply.push", { cascade.ancestorKeys.push(element) })
    })
    defer {
        if let pushedKeys {
            profiler.measure("style.apply.pop", { cascade.ancestorKeys.pop(pushedKeys) })
        }
    }

    let inheritsChange: Bool = applies ? cascade.inheritedChanged(node) : false
    for child in node.children {
        applyStyle(node: child, cascade: cascade, force: inheritsChange)
    }
}

@MainActor
private func applyNodeStyle(
    node: any DOMNode,
    cascade: StyleCascade
) {

    let parentStyle: StyleFields? = node.parent?.style
    var newStyle: [String: String] = [:]
    profiler.measure("style.apply.reset") {
        newStyle.reserveCapacity(inheritedPropertyDefaults.count)
        for (property, defaultValue) in inheritedPropertyDefaults {
            newStyle[property] = parentStyle?[property] ?? defaultValue
        }
    }

    if let element = node as? Element {
        profiler.count("style.elements")
        if let direction = TextDirectionResolver.resolve(element) {
            newStyle["direction"] = direction.rawValue
        }

        let candidates: [Int] = profiler.measure("style.apply.flags", {
            cascade.index.candidateIndices(for: element, ancestorKeys: cascade.ancestorKeys)
        })
        profiler.count("style.candidates", by: candidates.count)
        profiler.count("style.universalCandidates", by: cascade.index.universalRuleCount)

        var descendantCandidates: Int = 0
        var matchesTrue: Int = 0
        var descendantTrue: Int = 0
        var bodyWrites: Int = 0
        profiler.measure("style.apply.test", {
            for candidate in candidates {
                let (mediaQuery, selector, body) = cascade.index.orderedRules[candidate]
                let isDescendant: Bool = isDescendantRule(selector)
                if isDescendant { descendantCandidates += 1 }
                guard cascade.media.matches(mediaQuery), selector.matches(node) else { continue }
                matchesTrue += 1
                if isDescendant { descendantTrue += 1 }
                for (property, value) in body {
                    newStyle[property] = value
                    bodyWrites += 1
                }
            }
        })
        profiler.count("style.descendantCandidates", by: descendantCandidates)
        profiler.count("style.descendantTrue", by: descendantTrue)
        profiler.count("style.matchesTrue", by: matchesTrue)
        profiler.count("style.bodyWrites", by: bodyWrites)
    }

    profiler.measure("style.apply.inline", {
        if let element = node as? Element,
            let inlineStyle = element.attributes["style"]
        {
            for (property, value) in CSSParser(inlineStyle).body() {
                newStyle[property] = value
            }
        }
    })

    profiler.measure("style.apply.post", {
        if cascade.media.preferences.usesForcedColors { applyForcedColors(to: &newStyle, node: node) }

        if newStyle["overflow"] == nil {
            let scrolls: Bool = newStyle["overflow-y"] == "scroll" || newStyle["overflow-x"] == "scroll"
            let hides: Bool = newStyle["overflow-y"] == "hidden" || newStyle["overflow-x"] == "hidden"
            if scrolls {
                newStyle["overflow"] = "scroll"
            } else if hides {
                newStyle["overflow"] = "hidden"
            }
        }

        if let fontSize = newStyle["font-size"], fontSize.hasSuffix("%") {
            let parentFontSize: String = node.parent?.style["font-size"] ?? inheritedPropertyDefaults["font-size"]!
            let percentage: Double = Double(fontSize.dropLast()) ?? 100.0
            let parentPx: Double = Double(parentFontSize.dropLast(2)) ?? 16.0
            newStyle["font-size"] = "\(percentage / 100.0 * parentPx)px"
        }

        node.style.apply(newStyle)
    })
}
