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

// MARK: - CSS Cascade (style function)
func applyStyle(
    node: any DOMNode,
    rules: RuleIndex,
    media: MediaFeatures,
    ancestors: AncestorScope
) {

    profiler.count("style.nodes")
    let parentStyle: [String: String]? = node.parent?.style
    profiler.measure("style.apply.reset") {
        var newStyle: [String: String] = [:]
        newStyle.reserveCapacity(inheritedPropertyDefaults.count)
        for (property, defaultValue) in inheritedPropertyDefaults {
            newStyle[property] = parentStyle?[property] ?? defaultValue
        }
        node.style = newStyle
    }

    if let element = node as? Element {
        profiler.count("style.elements")
        if let direction = TextDirectionResolver.resolve(element) {
            node.style["direction"] = direction.rawValue
        }
        let flags: [Bool] = profiler.measure("style.apply.flags", {
            rules.candidateFlags(for: element, ancestors: ancestors)
        })

        var candidates: [Int] = []
        profiler.measure("style.apply.scan", {
            candidates.reserveCapacity(8)
            for index in 0..<rules.rules.count where flags[index] {
                candidates.append(index)
            }
        })

        profiler.count("style.candidates", by: candidates.count)
        profiler.count("style.universalCandidates", by: rules.universalCount)

        var descendantCandidates: Int = 0
        var matchesTrue: Int = 0
        var descendantTrue: Int = 0
        var bodyWrites: Int = 0
        profiler.measure("style.apply.test", {
            for index in candidates {
                let (mediaQuery, selector, body) = rules.rules[index]
                let isDescendant: Bool = isDescendantRule(selector)
                if isDescendant { descendantCandidates += 1 }
                guard media.matches(mediaQuery), selector.matches(node) else { continue }
                matchesTrue += 1
                if isDescendant { descendantTrue += 1 }
                for (property, value) in body {
                    node.style[property] = value
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
                node.style[property] = value
            }
        }
    })

    profiler.measure("style.apply.post", {
        if media.preferences.usesForcedColors { applyForcedColors(node: node) }

        if node.style["overflow"] == nil {
            if node.style["overflow-y"] == "scroll" || node.style["overflow-x"] == "scroll" {
                node.style["overflow"] = "scroll"
            }
        }

        if let fontSize = node.style["font-size"], fontSize.hasSuffix("%") {
            let parentFontSize: String = node.parent?.style["font-size"] ?? inheritedPropertyDefaults["font-size"]!
            let percentage: Double = Double(fontSize.dropLast()) ?? 100.0
            let parentPx: Double = Double(parentFontSize.dropLast(2)) ?? 16.0
            node.style["font-size"] = "\(percentage / 100.0 * parentPx)px"
        }
    })

    let pushedElement: Element? = node as? Element
    let pushedKeys: [SelectorBucketKey]? = pushedElement.map { element in
        profiler.measure("style.apply.push", { ancestors.push(element) })
    }

    defer {
        if let pushedKeys {
            profiler.measure("style.apply.pop", { ancestors.pop(pushedKeys) })
        }
    }

    for child in node.children {
        applyStyle(node: child, rules: rules, media: media, ancestors: ancestors)
    }
}

func setInlineStyleProperty(_ elt: Element, property: String, value: String) {
    var props: [String : String] = CSSParser(elt.attributes["style"] ?? "").body()
    props[property.lowercased()] = value
    elt.attributes["style"] = props.map({
        "\($0.key): \($0.value)"
    })
    .joined(separator: "; ")
}
