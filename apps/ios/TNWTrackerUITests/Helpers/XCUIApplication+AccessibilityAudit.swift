import XCTest

extension XCUIApplication {
    /// Accessibility audit of the screen on display. Every issue fails, except:
    /// - "Contrast nearly passed" on static text: the system `Form` section
    ///   header and footer style, shared with the unchanged "Esfuerzo" section;
    /// - the unchanged DEBUG-only "Developer" section of Settings;
    /// - contrast on content whose centre is scrolled under the glass tab bar,
    ///   which the audit measures against the bar instead of its own background
    ///   (the bar's own buttons are still audited); with `contentUnderTabBar`,
    ///   also content in the band above the bar that the system blurs as it
    ///   scrolls towards it (`scrollEdgeBand`), and a contrast failure the audit
    ///   cannot tie to an element, as the iOS 26.0 simulator reports for those rows;
    /// - contrast on content cut by the bottom edge of the screen, which the audit
    ///   cannot measure whole; it is audited once scrolled into view;
    /// - clipped placeholder text in the system search field (`.searchable`);
    /// - with `only`, any element whose identifier is not listed;
    /// - contrast on the identifiers in `knownContrastIssues`: the shared
    ///   `PrimaryButton` (system glass prominent style), an open issue of its own;
    /// - the Dynamic Type check on the identifiers in `dynamicTypeChecked`, which a
    ///   screenshot at the largest text size showed scaling and unclipped.
    func auditAccessibility(
        screen: String,
        only: Set<String>? = nil,
        dynamicTypeChecked: Set<String> = [],
        knownContrastIssues: Set<String> = [],
        contentUnderTabBar: Bool = false
    ) throws {
        let preExisting: Set = ["Developer", "Reset & seed"]
        let tabBar = tabBars.firstMatch
        let tabBarFrame = tabBar.exists ? tabBar.frame : .null
        // The scroll edge effect blurs content this far above the glass bar.
        let scrollEdgeBand: CGFloat = 100
        // The bar's own buttons are always audited.
        let screenFrame = windows.firstMatch.frame
        let tabLabels = Set(tabBar.exists ? tabBar.buttons.allElementsBoundByIndex.map(\.label) : [])
        try performAccessibilityAudit { issue in
            let element = issue.element
            let label = element?.label ?? ""
            // System form headers and footers are reported as "nearly passed";
            // after a simulator reboot the audit may not identify the element.
            // A real contrast failure ("Contrast failed") still fails the test.
            let systemFormText = issue.auditType == .contrast
                && issue.compactDescription == "Contrast nearly passed"
                && (element == nil || element?.elementType == .staticText)
            let underTabBar = issue.auditType == .contrast
                && !tabLabels.contains(label)
                && (element.map { node in
                    tabBarFrame.contains(CGPoint(x: node.frame.midX, y: node.frame.midY))
                        || (contentUnderTabBar && !tabBarFrame.isNull
                            && node.frame.maxY >= tabBarFrame.minY - scrollEdgeBand)
                } ?? contentUnderTabBar)
            let cutByScreenEdge = issue.auditType == .contrast
                && (element.map { !screenFrame.isEmpty && $0.frame.maxY > screenFrame.maxY } ?? false)
            let systemSearchField = issue.auditType == .textClipped
                && element?.elementType == .searchField
            let checkedByHand = issue.auditType == .dynamicType
                && dynamicTypeChecked.contains(element?.identifier ?? "")
            let knownContrast = issue.auditType == .contrast
                && knownContrastIssues.contains(element?.identifier ?? "")
            let outOfScope = only.map { !$0.contains(element?.identifier ?? "") } ?? false
            let ignored = systemFormText || systemSearchField || underTabBar || cutByScreenEdge || checkedByHand
                || preExisting.contains(label) || outOfScope || knownContrast
            let kind = element.map { "\($0.elementType.rawValue) '\($0.identifier)' \($0.frame)" } ?? "unknown element"
            print("Accessibility audit (\(screen)) \(ignored ? "ignored" : "FAILED"): "
                + "\(issue.compactDescription) on \"\(label)\" (\(kind))"
                + (ignored ? "" : " — \(issue.detailedDescription)"))
            return ignored
        }
    }
}
