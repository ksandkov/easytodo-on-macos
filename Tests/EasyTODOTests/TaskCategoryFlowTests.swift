import XCTest
import SwiftData
@testable import EasyTODO

final class TaskCategoryFlowTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "EasyTODOTests.CategoryFlow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    @MainActor
    func testCreationSavesSelectedCategoryAndRejectsStaleSelectionsAndBlankTitles() throws {
        let store = TaskCategoryStore(defaults: defaults())
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let id = try XCTUnwrap(store.categories.first?.id)
        let task = try XCTUnwrap(TaskCreation.addTask(title: "Categorized", in: context, categoryID: id, categoryStore: store))
        XCTAssertEqual(store.categoryID(for: task), id)
        task.title = "Renamed"
        task.isCompleted = true
        TaskScheduling.move(task, to: Date().addingTimeInterval(86_400), among: [task])
        try context.save()
        XCTAssertEqual(store.categoryID(for: task), id)
        XCTAssertNil(try TaskCreation.addTask(title: "   ", in: context, categoryID: id, categoryStore: store))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 1)
        store.remove(id: id)
        let stale = try XCTUnwrap(TaskCreation.addTask(title: "Stale selection", in: context, categoryID: id, categoryStore: store))
        XCTAssertNil(store.categoryID(for: stale))
    }

    @MainActor
    func testRepeatedOccurrencesInheritCategoryWithoutChangingExistingOccurrences() throws {
        let store = TaskCategoryStore(defaults: defaults())
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let id = try XCTUnwrap(store.categories.first?.id)
        let task = try XCTUnwrap(TaskCreation.addTask(title: "Repeat", in: context, categoryID: id, categoryStore: store))
        try TaskRepeatScheduler.setRepeatRule(.daily, for: task, tasks: [task], in: context, categoryStore: store)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        XCTAssertEqual(tasks.count, TaskRepeatScheduler.dailyHorizonDays + 1)
        XCTAssertTrue(tasks.allSatisfy { store.categoryID(for: $0) == id })
        store.assign(nil, to: task)
        let occurrence = try XCTUnwrap(tasks.first { $0 !== task })
        XCTAssertEqual(store.categoryID(for: occurrence), id)
    }

    @MainActor
    func testDeletionUndoRestoresCategoryUnlessCategoryWasDeleted() throws {
        let store = TaskCategoryStore(defaults: defaults())
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let id = try XCTUnwrap(store.categories.first?.id)
        let task = try XCTUnwrap(TaskCreation.addTask(title: "Undo", in: context, categoryID: id, categoryStore: store))
        let snapshot = try DeletedTaskSnapshot.delete(task, in: context, categoryStore: store)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoTask>()), 0)
        let restored = try snapshot.restore(in: context, categoryStore: store)
        XCTAssertEqual(store.categoryID(for: restored), id)
        XCTAssertEqual(restored.title, "Undo")
        let second = try DeletedTaskSnapshot.delete(restored, in: context, categoryStore: store)
        store.remove(id: id)
        let uncategorized = try second.restore(in: context, categoryStore: store)
        XCTAssertNil(store.categoryID(for: uncategorized))
        XCTAssertEqual(uncategorized.title, "Undo")
    }

    @MainActor
    func testAssigningCategoriesDoesNotReorderTasksOrAlterLegacyPriorities() throws {
        let store = TaskCategoryStore(defaults: defaults())
        let container = try PersistenceController.modelContainer(inMemory: true)
        let first = TodoTask(title: "First", sortOrder: 0, priority: .importantUrgent)
        let second = TodoTask(title: "Second", sortOrder: 1, priority: .notUrgentNotImportant)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let before = TaskListOrdering.ordered([first, second]).map(\.title)
        store.assign(store.categories.last?.id, to: first)
        store.assign(store.categories.first?.id, to: second)
        XCTAssertEqual(TaskListOrdering.ordered([first, second]).map(\.title), before)
        XCTAssertEqual(first.priority, .importantUrgent)
        XCTAssertEqual(second.priority, .notUrgentNotImportant)
    }
}
