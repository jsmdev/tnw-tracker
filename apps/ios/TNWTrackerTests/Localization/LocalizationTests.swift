import Foundation
import Testing

@Suite("Localization")
struct LocalizationTests {
    @Test func enLocaleResolvesBundleStrings() {
        // Smoke: verifica que el bundle del app tiene región de desarrollo configurada.
        // El catalog se llena en batches siguientes; cuando lo haga, Bundle.main
        // expondrá en.lproj/Localizable.strings compilado desde el xcstrings.
        let bundle = Bundle.main
        let developmentRegion = bundle.infoDictionary?["CFBundleDevelopmentRegion"] as? String
        #expect(developmentRegion == "en", "CFBundleDevelopmentRegion missing or not 'en' in main bundle")
    }
}
