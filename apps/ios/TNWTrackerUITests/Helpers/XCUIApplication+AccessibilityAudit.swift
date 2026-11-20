import XCTest

extension XCUIApplication {
    /// Accessibility audit of the screen on display. Every issue fails, except:
    /// - "Contrast nearly passed" on static text: the system `Form` section
    ///   header and footer style, shared with the unchanged "Esfuerzo" section;
    /// - the unchanged DEBUG-only "Developer" section of Settings;
    /// - with `only`, any element whose identifier is not listed.
    func auditAccessibility(screen: String, only: Set<String>? = nil) throws {
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
            let ignored = systemFormText || preExisting.contains(label) || outOfScope
            if ignored {
                print("Accessibility audit (\(screen)) ignored: \(issue.compactDescription) on \"\(label)\"")
            }
            return ignored
        }
    }
}
