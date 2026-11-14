import Foundation

struct TaskTitleEditing {
    private(set) var sessionID: UUID?
    var draft = ""

    mutating func begin(title: String) {
        draft = title
        sessionID = UUID()
    }

    mutating func commit(sessionID: UUID) -> String? {
        guard self.sessionID == sessionID else { return nil }
        self.sessionID = nil
        return draft
    }

    mutating func cancel(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        self.sessionID = nil
        draft = ""
    }
}
