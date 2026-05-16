import Foundation
import Testing

@Suite("Design System Accessibility")
struct DesignSystemAccessibilityTests {
    // REQ-DS-05: No hardcoded .frame(height:) in DesignSystem Components.
    // Components must grow with Dynamic Type — only .frame(minHeight:) for tap targets is allowed.
    @Test func componentsHaveNoHardcodedFrameHeights() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DesignSystem (tests)
            .deletingLastPathComponent() // TNWTrackerTests
            .deletingLastPathComponent() // apps/ios
            .appendingPathComponent("TNWTracker/DesignSystem/Components")

        guard fm.fileExists(atPath: base.path) else {
            Issue.record("DesignSystem/Components directory not found at \(base.path)")
            return
        }

        let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: nil)
        var violations: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            // .frame(height: <number>) is forbidden — must use minHeight for tap targets
            for (index, line) in lines.enumerated() where line.contains(".frame(height:") {
                violations.append(
                    "\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }

        #expect(
            violations.isEmpty,
            """
            Hardcoded .frame(height:) found in DesignSystem components — \
            use .frame(minHeight: 44) for tap targets instead:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    // REQ-DS-04: No foregroundColor(_:) in DesignSystem — use foregroundStyle(_:).
    @Test func componentsUseForegroundStyleNotColor() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TNWTracker/DesignSystem")

        guard fm.fileExists(atPath: base.path) else {
            Issue.record("DesignSystem directory not found at \(base.path)")
            return
        }

        let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: nil)
        var violations: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("foregroundColor(") {
                violations.append(
                    "\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }

        #expect(
            violations.isEmpty,
            "foregroundColor(_:) is deprecated — use foregroundStyle(_:):\n\(violations.joined(separator: "\n"))"
        )
    }

    // REQ-DS-05: No hardcoded point sizes in Typography — only semantic font styles allowed.
    @Test func typographyUsesNoHardcodedPointSizes() throws {
        let fm = FileManager.default
        let typographyURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TNWTracker/DesignSystem/Tokens/Typography.swift")

        guard fm.fileExists(atPath: typographyURL.path) else {
            Issue.record("Typography.swift not found — Batch 3.2 not yet applied")
            return
        }

        let content = try String(contentsOf: typographyURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var violations: [String] = []

        for (index, line) in lines.enumerated() {
            // .system(size: <N>) with a literal number is forbidden in Typography
            // Exception: timerLarge uses .system(size: 64) intentionally
            if line.contains(".system(size:"), !line.contains("timerLarge"), !line.contains("//") {
                violations.append("Typography.swift:\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        #expect(
            violations.isEmpty,
            """
            Hardcoded .system(size:) in Typography — \
            use semantic font styles (.title, .body, etc.):
            \(violations.joined(separator: "\n"))
            """
        )
    }

    // REQ-DS-04: No AnyView in DesignSystem (type erasure harms performance and Dynamic Type).
    @Test func designSystemHasNoAnyView() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TNWTracker/DesignSystem")

        guard fm.fileExists(atPath: base.path) else {
            Issue.record("DesignSystem directory not found")
            return
        }

        let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: nil)
        var violations: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() where line.contains("AnyView") {
                violations.append(
                    "\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
                )
            }
        }

        #expect(
            violations.isEmpty,
            "AnyView found in DesignSystem — use @ViewBuilder or generics:\n\(violations.joined(separator: "\n"))"
        )
    }
}
