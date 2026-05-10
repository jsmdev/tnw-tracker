import Foundation
import Testing

@Suite("Localization")
struct LocalizationTests {
    // MARK: - Existing smoke test

    @Test func enLocaleResolvesBundleStrings() {
        // Smoke: verifica que el bundle del app tiene región de desarrollo configurada.
        let bundle = Bundle.main
        let developmentRegion = bundle.infoDictionary?["CFBundleDevelopmentRegion"] as? String
        #expect(developmentRegion == "en", "CFBundleDevelopmentRegion missing or not 'en' in main bundle")
    }

    // MARK: - Task 12.1: Cross-locale validation (ADR-6, REQ-LOC-10)

    /// Verifies a curated set of representative keys resolve in es-ES and differ from EN.
    /// One key from each feature: home, session-list, active-workout (controls.end), summary, rest-timer.
    /// Uses Bundle.localizedString with .lproj bundles — avoids mutating Locale.current (process-wide).
    /// Test host is the app bundle via BUNDLE_LOADER (project.yml), so Bundle.main has xcstrings resources.
    @Test(arguments: [
        "home.title",
        "session-list.title",
        "summary.title",
        "active-workout.controls.end",
        "rest-timer.skip-button",
    ])
    func existingKeysResolveInBothLocales(key: String) {
        let bundle = Bundle.main

        let enResolved = resolveString(key: key, languageCode: "en", bundle: bundle)
        let esResolved = resolveString(key: key, languageCode: "es-ES", bundle: bundle)

        #expect(!enResolved.isEmpty, "EN resolved empty for key: \(key)")
        #expect(enResolved != key, "EN returned the key verbatim — key not found: \(key)")

        #expect(!esResolved.isEmpty, "es-ES resolved empty for key: \(key)")
        #expect(esResolved != key, "es-ES returned key verbatim — key not found: \(key)")

        #expect(
            esResolved != enResolved,
            "es-ES == EN for key '\(key)' — Spanish translation missing. Got: '\(esResolved)'"
        )
    }

    /// FormatStyle: Spanish decimal separator is comma (e.g., 1.234,5 or 1234,5).
    /// REQ-LOC-07: numeric values must use FormatStyle (locale-aware).
    @Test func formatStyleNumberLocaleES_uses_decimal_comma() {
        let formatted = 1234.5.formatted(.number.locale(Locale(identifier: "es-ES")))
        // Spanish uses comma as decimal separator: "1.234,5" or "1234,5"
        #expect(formatted.contains(","), "Expected comma as decimal separator in es-ES, got: \(formatted)")
        // The integer part should contain "1234" or "1.234" (with thousands separator)
        let containsDigits = formatted.contains("1234") || formatted.contains("1.234")
        #expect(containsDigits, "Expected 1234 digits in formatted number, got: \(formatted)")
    }

    /// FormatStyle Duration with es-ES locale produces a non-empty string with expected hour/minute values.
    /// REQ-LOC-07: temporal values must use Duration.TimeFormatStyle, not manual string interpolation.
    @Test func formatStyleDurationLocaleES_works() {
        let duration = Duration.seconds(75 * 60) // 1 hour 15 minutes
        let formatted = duration.formatted(
            .time(pattern: .hourMinuteSecond)
                .locale(Locale(identifier: "es-ES"))
        )
        #expect(!formatted.isEmpty, "Duration formatted string is empty for es-ES")
        #expect(formatted.contains("1"), "Expected '1' (hour) in duration format, got: \(formatted)")
        #expect(formatted.contains("15"), "Expected '15' (minutes) in duration format, got: \(formatted)")
    }

    /// FormatStyle Date with es-ES locale produces day before month abbreviation.
    /// Verifies no hardcoded locale assumptions in date formatting.
    /// es-ES format for day+month+year: "15 mar 2026" (DD MonthAbbrev YYYY) — day first.
    @Test func formatStyleDateLocaleES_uses_DD_MM_YYYY_order() {
        // Fixed date: March 15, 2026 → es-ES: "15 mar 2026"
        // Day "15" appears before month abbreviation "mar", which appears before year "2026".
        var components = DateComponents()
        components.year = 2026
        components.month = 3 // March
        components.day = 15
        let calendar = Calendar(identifier: .gregorian)
        guard let testDate = calendar.date(from: components) else {
            Issue.record("Failed to create test date from components")
            return
        }

        let formatted = testDate.formatted(
            .dateTime
                .locale(Locale(identifier: "es-ES"))
                .day()
                .month()
                .year()
        )

        // In es-ES, the formatted string should start with the day digit(s).
        // e.g. "15 mar 2026" — day "15" precedes month "mar".
        #expect(!formatted.isEmpty, "Formatted date is empty for es-ES")
        #expect(
            formatted.hasPrefix("15") || formatted.contains("15"),
            "Expected day '15' in es-ES formatted date, got: \(formatted)"
        )

        // Verify day appears before month abbreviation "mar" (march in Spanish)
        guard let dayRange = formatted.range(of: "15"),
              let monthRange = formatted.range(of: "mar", options: .caseInsensitive)
        else {
            Issue.record("Day '15' or month 'mar' not found in formatted date: \(formatted)")
            return
        }
        #expect(
            dayRange.lowerBound < monthRange.lowerBound,
            "Expected day (15) before month (mar) in es-ES format, got: \(formatted)"
        )
    }

    // MARK: - Private helpers

    /// Resolves a localization key in a specific language by loading the .lproj sub-bundle.
    /// Does NOT mutate Locale.current (safe for parallel Swift Testing runs).
    private func resolveString(key: String, languageCode: String, bundle: Bundle) -> String {
        // Try exact language identifier (e.g. "es-ES"), then base code (e.g. "es")
        let candidates = [languageCode, String(languageCode.prefix(2))]
        for lang in candidates {
            if let lprojPath = bundle.path(forResource: lang, ofType: "lproj"),
               let lprojBundle = Bundle(path: lprojPath)
            {
                let resolved = lprojBundle.localizedString(forKey: key, value: nil, table: nil)
                if resolved != key { return resolved }
            }
        }
        return ""
    }
}
