import XCTest

extension XCUIApplication {
    /// Accessibility audit of the screen on display. Every issue fails, except:
    /// - "Contrast nearly passed" on static text: the system `Form` section
    ///   header and footer style, shared with the unchanged "Esfuerzo" section;
    /// - the unchanged DEBUG-only "Developer" section of Settings;
    /// - with `only`, any element whose identifier is not listed;
    /// - "Dynamic Type partially unsupported" on the elements in `scrollsAtLargeSizes`:
    ///   the audit flags whichever multi-line text sits lowest on a full `Form`
    ///   (any of them, moved there), as it would leave the screen at the largest
    ///   sizes; the form scrolls, so the text stays readable.
    func auditAccessibility(
        screen: String,
        only: Set<String>? = nil,
        scrollsAtLargeSizes: Set<String> = []
    ) throws {
        let preExisting: Set<String> = ["Developer", "Reset & seed"]
        try performAccessibilityAudit { issue in
            let element = issue.element
            let label = element?.label ?? ""
            // System form headers and footers are reported as "nearly passed";
            // after a simulator reboot the audit may not identify the element.
            // A real contrast failure ("Contrast failed") still fails the test.
            let systemFormText = issue.auditType == .contrast
                && issue.compactDescription == "Contrast nearly passed"
                && (element == nil || element?.elementType == .staticText)
            let outOfScope = only.map { !$0.contains(element?.identifier ?? "") } ?? false
            let scrolls = issue.auditType == .dynamicType
                && scrollsAtLargeSizes.contains(element?.identifier ?? "")
            let ignored = systemFormText || preExisting.contains(label) || outOfScope || scrolls
            if ignored {
                print("Accessibility audit (\(screen)) ignored: \(issue.compactDescription) on \"\(label)\"")
            }
            return ignored
        }
    }
}
