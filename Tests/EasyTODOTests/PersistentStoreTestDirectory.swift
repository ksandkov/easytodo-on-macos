import Foundation
import Darwin

func makePersistentStoreTestDirectory() throws -> URL {
    let root = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    let directory = URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent("EasyTODOTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // SwiftData keeps store observers alive beyond container scope. Clean up after the test process stops using them.
    atexit_b {
        try? FileManager.default.removeItem(at: directory)
    }
    return directory
}
