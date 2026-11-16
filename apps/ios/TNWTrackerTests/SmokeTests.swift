import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test func smoke() {
        #expect(true)
    }
}
