import Foundation
import SwiftData
import SwiftUI

@MainActor
final class TaskCategoryStore: ObservableObject {
    static let shared = TaskCategoryStore(defaults: .standard)
    private static let storageKey = "taskCategoryCatalogV1"

    private struct Snapshot: Codable {
        var categories: [TaskCategory]
        var assignments: [PersistentIdentifier: UUID] = [:]
        var defaultNamesVersion: Int? = 1
    }

    @Published private var snapshot: Snapshot
    private let defaults: UserDefaults

    var categories: [TaskCategory] { snapshot.categories }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            snapshot = (try? JSONDecoder().decode(Snapshot.self, from: data)) ?? Snapshot(categories: [])
            if snapshot.defaultNamesVersion == nil {
                if snapshot.categories.map(\.name) == ["Работа", "Важное", "Дом"],
                   snapshot.categories.map(\.colorHex) == ["398BBA", "DB4437", "388A5C"] {
                    for (index, name) in ["Work", "Important", "Home"].enumerated() {
                        snapshot.categories[index].name = name
                    }
                }
                snapshot.defaultNamesVersion = 1
                persist(snapshot)
            }
        } else {
            snapshot = Snapshot(categories: [
                TaskCategory(id: UUID(), name: "Work", colorHex: "398BBA"),
                TaskCategory(id: UUID(), name: "Important", colorHex: "DB4437"),
                TaskCategory(id: UUID(), name: "Home", colorHex: "388A5C")
            ])
            persist(snapshot)
        }
    }

    @discardableResult
    func add(name: String, colorHex: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let hex = TaskCategory.normalizedColorHex(colorHex) else { return nil }
        let category = TaskCategory(id: UUID(), name: name, colorHex: hex)
        var next = snapshot
        next.categories.append(category)
        update(next)
        return category.id
    }

    func rename(id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = snapshot.categories.firstIndex(where: { $0.id == id }) else { return }
        guard snapshot.categories[index].name != name else { return }
        var next = snapshot
        next.categories[index].name = name
        update(next)
    }

    func recolor(id: UUID, colorHex: String) {
        guard let hex = TaskCategory.normalizedColorHex(colorHex),
              let index = snapshot.categories.firstIndex(where: { $0.id == id }) else { return }
        guard snapshot.categories[index].colorHex != hex else { return }
        var next = snapshot
        next.categories[index].colorHex = hex
        update(next)
    }

    func remove(id: UUID) {
        var next = snapshot
        next.categories.removeAll { $0.id == id }
        next.assignments = next.assignments.filter { $0.value != id }
        update(next)
    }

    func validCategoryID(_ id: UUID?) -> UUID? {
        guard let id, categories.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    func categoryID(for task: TodoTask) -> UUID? {
        validCategoryID(snapshot.assignments[task.persistentModelID])
    }

    func color(for task: TodoTask) -> Color {
        guard let id = categoryID(for: task) else { return .gray }
        return categories.first { $0.id == id }?.color ?? .gray
    }

    func assign(_ categoryID: UUID?, to task: TodoTask) {
        guard task.persistentModelID.storeIdentifier != nil else { return }
        var next = snapshot
        next.assignments[task.persistentModelID] = validCategoryID(categoryID)
        guard next.assignments != snapshot.assignments else { return }
        update(next)
    }

    func removeAssignment(for taskID: PersistentIdentifier) {
        guard snapshot.assignments[taskID] != nil else { return }
        var next = snapshot
        next.assignments.removeValue(forKey: taskID)
        update(next)
    }

    private func update(_ next: Snapshot) {
        persist(next)
        snapshot = next
    }

    private func persist(_ value: Snapshot) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: Self.storageKey)
        } catch {
            NSLog("EasyTODO failed to encode task categories: \(error)")
        }
    }
}
