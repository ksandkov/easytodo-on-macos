import XCTest
import SwiftData
@testable import EasyTODO

final class TaskCategoryStoreTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let name = "EasyTODOTests.Categories.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor
    func testCatalogSeedsOnceAndAllowsMoreThanFourCategories() throws {
        let defaults = isolatedDefaults()
        let store = TaskCategoryStore(defaults: defaults)
        XCTAssertEqual(store.categories.map(\.name), ["Work", "Important", "Home"])
        for index in 0..<40 {
            XCTAssertNotNil(store.add(name: "Category \(index)", colorHex: "123ABC"))
        }
        XCTAssertEqual(store.categories.count, 43)
        XCTAssertEqual(TaskCategoryStore(defaults: defaults).categories, store.categories)
        for category in store.categories { store.remove(id: category.id) }
        XCTAssertTrue(TaskCategoryStore(defaults: defaults).categories.isEmpty)
    }

    private struct LegacyCatalog: Codable {
        var categories = [
            TaskCategory(id: UUID(), name: "Работа", colorHex: "398BBA"),
            TaskCategory(id: UUID(), name: "Важное", colorHex: "DB4437"),
            TaskCategory(id: UUID(), name: "Дом", colorHex: "388A5C")
        ]
        var assignments: [PersistentIdentifier: UUID] = [:]
    }

    @MainActor
    func testUntouchedLegacyDefaultsBecomeEnglishWithoutLosingAssignments() throws {
        let defaults = isolatedDefaults()
        let container = try PersistenceController.modelContainer(inMemory: true)
        let task = TodoTask(title: "Keep assignment")
        container.mainContext.insert(task)
        try container.mainContext.save()
        var legacy = LegacyCatalog()
        legacy.assignments[task.persistentModelID] = legacy.categories[0].id
        defaults.set(try JSONEncoder().encode(legacy), forKey: "taskCategoryCatalogV1")
        let store = TaskCategoryStore(defaults: defaults)
        XCTAssertEqual(store.categories.map(\.name), ["Work", "Important", "Home"])
        XCTAssertEqual(store.categories.map(\.id), legacy.categories.map(\.id))
        XCTAssertEqual(store.categoryID(for: task), legacy.categories[0].id)
        XCTAssertEqual(TaskCategoryStore(defaults: defaults).categories, store.categories)
    }

    @MainActor
    func testCustomizedLegacyCatalogsAreNotTranslated() throws {
        var renamed = LegacyCatalog()
        renamed.categories[0].name = "Моя работа"
        var recolored = LegacyCatalog()
        recolored.categories[0].colorHex = "112233"
        var extended = LegacyCatalog()
        extended.categories.append(TaskCategory(id: UUID(), name: "Personal", colorHex: "123456"))
        var empty = LegacyCatalog()
        empty.categories = []
        for legacy in [renamed, recolored, extended, empty] {
            let defaults = isolatedDefaults()
            defaults.set(try JSONEncoder().encode(legacy), forKey: "taskCategoryCatalogV1")
            XCTAssertEqual(TaskCategoryStore(defaults: defaults).categories, legacy.categories)
            XCTAssertEqual(TaskCategoryStore(defaults: defaults).categories, legacy.categories)
        }
    }

    @MainActor
    func testUserCanRenameEnglishDefaultsToRussianWithoutRetriggeringMigration() throws {
        let defaults = isolatedDefaults()
        let store = TaskCategoryStore(defaults: defaults)
        for (category, name) in zip(store.categories, ["Работа", "Важное", "Дом"]) {
            store.rename(id: category.id, name: name)
        }
        XCTAssertEqual(TaskCategoryStore(defaults: defaults).categories.map(\.name), ["Работа", "Важное", "Дом"])
    }

    @MainActor
    func testNamesAndColorsAreValidatedAndEditsKeepIdentity() throws {
        let store = TaskCategoryStore(defaults: isolatedDefaults())
        XCTAssertNil(store.add(name: "  \n", colorHex: "123ABC"))
        XCTAssertNil(store.add(name: "Invalid", colorHex: "nothex"))
        let id = try XCTUnwrap(store.add(name: " Home Office ", colorHex: "#aabbcc"))
        store.rename(id: id, name: "  New Name  ")
        store.rename(id: id, name: "   ")
        store.recolor(id: id, colorHex: "00FF00")
        store.recolor(id: id, colorHex: "broken")
        let category = try XCTUnwrap(store.categories.first { $0.id == id })
        XCTAssertEqual(category.name, "New Name")
        XCTAssertEqual(category.colorHex, "00FF00")
    }

    @MainActor
    func testAssignmentSurvivesReloadAndDeletionKeepsTaskAndPriority() throws {
        let defaults = isolatedDefaults()
        let store = TaskCategoryStore(defaults: defaults)
        let container = try PersistenceController.modelContainer(inMemory: true)
        let task = TodoTask(title: "Keep this task", priority: .importantUrgent)
        container.mainContext.insert(task)
        try container.mainContext.save()
        let id = try XCTUnwrap(store.categories.first?.id)
        store.assign(id, to: task)
        store.rename(id: id, name: "Renamed")
        store.recolor(id: id, colorHex: "112233")
        XCTAssertEqual(TaskCategoryStore(defaults: defaults).categoryID(for: task), id)
        XCTAssertEqual(task.priority, .importantUrgent)
        store.remove(id: id)
        XCTAssertNil(store.categoryID(for: task))
        XCTAssertNil(store.validCategoryID(id))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TodoTask>()), 1)
        XCTAssertEqual(task.title, "Keep this task")
        XCTAssertEqual(task.priority, .importantUrgent)
    }

    @MainActor
    func testTemporaryTaskIdentifiersAreNotAssigned() throws {
        let store = TaskCategoryStore(defaults: isolatedDefaults())
        let task = TodoTask(title: "Not saved")
        store.assign(store.categories.first?.id, to: task)
        XCTAssertNil(store.categoryID(for: task))
    }

    @MainActor
    func testAssignmentSurvivesAnOnDiskStoreReopen() throws {
        let directory = try makePersistentStoreTestDirectory()
        let defaults = isolatedDefaults()
        let store = TaskCategoryStore(defaults: defaults)
        let id = try XCTUnwrap(store.categories.first?.id)
        let url = directory.appendingPathComponent("tasks.store")
        try autoreleasepool {
            let container = try ModelContainer(for: TodoTask.self, configurations: ModelConfiguration(url: url))
            let task = TodoTask(title: "Durable category", priority: .urgentNotImportant)
            container.mainContext.insert(task)
            try container.mainContext.save()
            store.assign(id, to: task)
            XCTAssertEqual(store.categoryID(for: task), id)
        }
        try autoreleasepool {
            let reopened = try ModelContainer(for: TodoTask.self, configurations: ModelConfiguration(url: url))
            let task = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
            XCTAssertEqual(TaskCategoryStore(defaults: defaults).categoryID(for: task), id)
            XCTAssertEqual(task.priority, .urgentNotImportant)
        }
    }
}
