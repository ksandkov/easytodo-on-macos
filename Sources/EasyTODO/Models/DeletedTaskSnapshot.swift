import Foundation
import SwiftData

@MainActor
struct DeletedTaskSnapshot {
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
    let scheduledDate: Date
    let priority: TaskPriority
    let repeatRule: TaskRepeatRule
    let recurrenceGroupID: String?
    let categoryID: UUID?

    init(task: TodoTask, calendar: Calendar, categoryStore: TaskCategoryStore) {
        title = task.title
        isCompleted = task.isCompleted
        sortOrder = task.sortOrder
        createdAt = task.createdAt
        scheduledDate = task.scheduledDay(in: calendar)
        priority = task.priority
        repeatRule = task.repeatRule
        recurrenceGroupID = task.recurrenceGroupID
        categoryID = categoryStore.categoryID(for: task)
    }

    static func delete(_ task: TodoTask, in context: ModelContext, calendar: Calendar = .current,
                       categoryStore: TaskCategoryStore? = nil) throws -> DeletedTaskSnapshot {
        let store = categoryStore ?? .shared
        let snapshot = DeletedTaskSnapshot(task: task, calendar: calendar, categoryStore: store)
        let taskID = task.persistentModelID
        context.delete(task)
        try context.save()
        store.removeAssignment(for: taskID)
        return snapshot
    }

    @discardableResult
    func restore(in context: ModelContext, categoryStore: TaskCategoryStore? = nil) throws -> TodoTask {
        let task = TodoTask(title: title, isCompleted: isCompleted, sortOrder: sortOrder, createdAt: createdAt,
                            scheduledDate: scheduledDate, priority: priority, repeatRule: repeatRule,
                            recurrenceGroupID: recurrenceGroupID)
        context.insert(task)
        try context.save()
        (categoryStore ?? .shared).assign(categoryID, to: task)
        return task
    }
}
