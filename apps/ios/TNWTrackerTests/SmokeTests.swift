import Testing

@Suite("Smoke")
struct SmokeTests {
    @Test func smoke() {
        #expect(Bool(false), "temporary probe for #131: CI must fail")
    }
}
