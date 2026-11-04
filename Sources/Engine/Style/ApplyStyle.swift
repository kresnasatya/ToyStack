import CoreGraphics

// MARK: - applyStyle
@MainActor
func applyStyle(
    node: DOMRef,
    cascade: StyleCascade,
    snapshot provided: StyleSnapshot? = nil
) {
    let snapshot: StyleSnapshot = provided ?? profiler.measure("style.snapshot.apply", {
        StyleSnapshotBuilder.build(root: node)
    })
    profiler.measure("style.traverse", {
        applyStyle(node: node, cascade: cascade, snapshot: snapshot, force: false)
    })
}

@MainActor
private func applyStyle(
    node: DOMRef,
    cascade: StyleCascade,
    snapshot: StyleSnapshot,
    force: Bool
) {
    guard force || node.style.isDirty || node.style.hasDirtyDescendant else {
        profiler.count("style.skipped")
        return
    }
    profiler.count("style.visited")
    if node.style.hasDirtyDescendant {
        profiler.count("style.dirtyDescendants")
    }
    defer { node.style.clearDirtyDescendants() }

    let index: Int = snapshot.index(of: node.id) ?? 0
    let direct: Bool = cascade.scope.map({ $0.matches(node) }) ?? true
    let applies: Bool = force || direct || node.style.isDirty
    if applies {
        if force {
            profiler.count("style.apply.force")
        } else if direct {
            profiler.count("style.apply.direct")
        } else {
            profiler.count("style.apply.dirtyNode")
        }
        let forceOnly: Bool = force && !direct && !node.style.isDirty
        if forceOnly {
            let old: ComputedStyle = node.style.computed
            let changed: Set<StyleProperty>? = profiler.measure("style.reapplyInherited", {
                node.style.reapplyInherited(parent: node.parent?.style.computed)
            })
            if let changed {
                profiler.count("style.apply.inheritedOnly")
                if !changed.isEmpty {
                    cascade.record(node, old: old)
                }
            } else {
                cascade.record(node)
                profiler.measure("style.apply.node", {
                    applyNodeStyle(node: node, cascade: cascade, snapshot: snapshot, index: index)
                })
            }
        } else {
            cascade.record(node)
            profiler.measure("style.apply.node", {
                applyNodeStyle(node: node, cascade: cascade, snapshot: snapshot, index: index)
            })
        }
    }

    let pushedKeys: [SelectorKey]? = node.element.map({ _ in
        profiler.measure("style.apply.push", { cascade.ancestorKeys.push(snapshot, index) })
    })
    defer {
        if let pushedKeys {
            profiler.measure("style.apply.pop", { cascade.ancestorKeys.pop(pushedKeys) })
        }
    }

    let inheritsChange: Bool = applies
        ? profiler.measure("style.inheritedChanged", {
            cascade.inheritedChanged(node)
        })
        : false
    for child in node.children {
        applyStyle(node: child, cascade: cascade, snapshot: snapshot, force: inheritsChange)
    }
}

@MainActor
private let inheritedTextKeys: Set<String> = Set(StyleProperty.inherited.map(\.cssName))

@MainActor
private func applyNodeStyle(
    node: DOMRef,
    cascade: StyleCascade,
    snapshot: StyleSnapshot,
    index: Int
) {

    var newStyle: [String: String] = [:]

    if node.element != nil {
        profiler.count("style.elements")
        if let direction = TextDirectionResolver.resolve(snapshot, index) {
            newStyle["direction"] = direction.rawValue
        }

        let candidates: [Int] = profiler.measure("style.apply.flags", {
            cascade.index.candidateIndices(
                for: snapshot,
                index: index,
                ancestorKeys: cascade.ancestorKeys
            )
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
                guard cascade.media.matches(mediaQuery), selector.matches(snapshot, index) else { continue }
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
        if let element = node.element,
            let inlineStyle = element.attributes["style"]
        {
            for (property, value) in CSSParser(inlineStyle).body() {
                newStyle[property] = value
            }
        }
    })

    profiler.measure("style.apply.post", {
        if cascade.media.preferences.usesForcedColors {
            applyForcedColors(to: &newStyle, tag: node.element?.tag)
        }

        if newStyle["overflow"] == nil {
            let scrolls: Bool = newStyle["overflow-y"] == "scroll" || newStyle["overflow-x"] == "scroll"
            let hides: Bool = newStyle["overflow-y"] == "hidden" || newStyle["overflow-x"] == "hidden"
            if scrolls {
                newStyle["overflow"] = "scroll"
            } else if hides {
                newStyle["overflow"] = "hidden"
            }
        }

        let textDeclarations: [String: String] = newStyle.filter({
            inheritedTextKeys.contains($0.key)
        })

        if let fontSize = newStyle["font-size"], fontSize.hasSuffix("%") {
            let percentage: Double = Double(fontSize.dropLast()) ?? 100.0
            let parentPx: CGFloat = node.parent?.style.computed.text.font.size ?? 16
            newStyle["font-size"] = "\(percentage / 100.0 * Double(parentPx))px"
        }

        node.style.apply(
            newStyle,
            parent: node.parent?.style.computed,
            textDeclarations: textDeclarations
        )
    })
}
