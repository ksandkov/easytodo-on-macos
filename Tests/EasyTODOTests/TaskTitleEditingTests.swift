import XCTest
@testable import EasyTODO

final class TaskTitleEditingTests: XCTestCase {
    func testBeginningAnEditDoesNotCommitTheTitle() {
        var editor = TaskTitleEditing()
        editor.begin(title: "Original")

        XCTAssertNotNil(editor.sessionID)
        XCTAssertEqual(editor.draft, "Original")
        editor.draft = "Changed"
        XCTAssertNotNil(editor.sessionID)
    }

    func testCommitReturnsTheDraftOnlyOnce() throws {
        var editor = TaskTitleEditing()
        editor.begin(title: "Original")
        let session = try XCTUnwrap(editor.sessionID)
        editor.draft = "Новая задача ✅"

        XCTAssertEqual(editor.commit(sessionID: session), "Новая задача ✅")
        XCTAssertNil(editor.commit(sessionID: session))
        XCTAssertNil(editor.sessionID)
    }

    func testCancelDiscardsTheDraftWithoutCommitting() throws {
        var editor = TaskTitleEditing()
        editor.begin(title: "Original")
        let session = try XCTUnwrap(editor.sessionID)
        editor.draft = "Discard me"
        editor.cancel(sessionID: session)

        XCTAssertNil(editor.sessionID)
        XCTAssertNil(editor.commit(sessionID: session))
    }

    func testStaleFocusEventsCannotCommitOrCancelANewerEdit() throws {
        var editor = TaskTitleEditing()
        editor.begin(title: "First")
        let firstSession = try XCTUnwrap(editor.sessionID)
        editor.cancel(sessionID: firstSession)
        editor.begin(title: "Second")
        let secondSession = try XCTUnwrap(editor.sessionID)
        editor.draft = "Keep editing"

        XCTAssertNil(editor.commit(sessionID: firstSession))
        editor.cancel(sessionID: firstSession)
        XCTAssertEqual(editor.sessionID, secondSession)
        XCTAssertEqual(editor.commit(sessionID: secondSession), "Keep editing")
    }
}
