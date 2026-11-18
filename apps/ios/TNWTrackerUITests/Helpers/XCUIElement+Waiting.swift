import XCTest

extension XCUIElement {
    /// Waits until a tap can reach the element: it exists, is on screen and is
    /// not covered or still moving in (a push, a menu, a sheet).
    func waitUntilHittable(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: self)
        let result = XCTWaiter().wait(for: [hittable], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(self) did not become hittable within \(timeout)s.", file: file, line: line)
    }
}
