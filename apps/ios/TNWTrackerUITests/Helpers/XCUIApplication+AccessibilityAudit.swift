import XCTest

extension XCUIApplication {
    /// Accessibility audit of the screen on display. Every issue fails, except:
    /// - "Contrast nearly passed" on static text: the system `Form` section
    ///   header and footer style, shared with the unchanged "Esfuerzo" section;
    /// - the unchanged DEBUG-only "Developer" section of Settings;
    /// - with `only`, any element whose identifier is not listed.
    /// An audit that runs out of time on a slow CI runner reports no issue, so it
    /// runs once more; a second timeout, or any real issue, still fails the test.
    func auditAccessibility(screen: String, only: Set<String>? = nil) throws {
        do {
            try runAudit(screen: screen, only: only)
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit"
            && error.code == -56 {
            print("Accessibility audit (\(screen)) ran out of time; running it once more.")
            try runAudit(screen: screen, only: only)
        }
    }

    private func runAudit(screen: String, only: Set<String>?) throws {
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
            let kind = element.map { "\($0.elementType.rawValue) '\($0.identifier)'" } ?? "unknown element"
            print("Accessibility audit (\(screen)) \(ignored ? "ignored" : "FAILED"): "
                + "\(issue.compactDescription) on \"\(label)\" (\(kind))")
            return ignored
        }
    }
}
