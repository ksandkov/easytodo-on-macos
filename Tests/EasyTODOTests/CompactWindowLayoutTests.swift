import Foundation
import XCTest
@testable import EasyTODO

final class CompactWindowLayoutTests: XCTestCase {
    func testCollapsePreservesWidthAndTopEdge() {
        var layout = CompactWindowLayout()
        let result = layout.toggle(frame: CGRect(x: 100, y: 200, width: 360, height: 500), headerHeight: 70)

        XCTAssertTrue(layout.isCollapsed)
        XCTAssertEqual(result, CGRect(x: 100, y: 630, width: 360, height: 70))
    }

    func testExpandRestoresSizeAtTheCurrentTopEdgeAfterDragging() {
        var layout = CompactWindowLayout()
        _ = layout.toggle(frame: CGRect(x: 100, y: 200, width: 360, height: 500), headerHeight: 70)
        let result = layout.toggle(frame: CGRect(x: 400, y: 730, width: 360, height: 70), headerHeight: 70)

        XCTAssertFalse(layout.isCollapsed)
        XCTAssertEqual(result, CGRect(x: 400, y: 300, width: 360, height: 500))
    }

    func testRepeatedTogglesDoNotDrift() {
        var layout = CompactWindowLayout()
        let original = CGRect(x: 100, y: 200, width: 340, height: 480)
        var frame = original
        for _ in 0..<20 {
            frame = layout.toggle(frame: frame, headerHeight: 76)
        }

        XCTAssertEqual(frame, original)
        XCTAssertFalse(layout.isCollapsed)
    }

    func testExpandUsesTheMostRecentExpandedSize() {
        var layout = CompactWindowLayout()
        var frame = layout.toggle(frame: CGRect(x: 100, y: 200, width: 340, height: 480), headerHeight: 70)
        frame = layout.toggle(frame: frame, headerHeight: 70)
        frame.size = CGSize(width: 500, height: 700)
        frame = layout.toggle(frame: frame, headerHeight: 70)
        frame = layout.toggle(frame: frame, headerHeight: 70)

        XCTAssertEqual(frame.size, CGSize(width: 500, height: 700))
    }
}
