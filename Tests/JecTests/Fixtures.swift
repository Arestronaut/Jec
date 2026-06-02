import Foundation
import Synchronization
@testable import Jec

// Shared fixtures used across the suites.

protocol APIClient: Sendable {
    var endpoint: String { get }
}

struct LiveAPIClient: APIClient {
    let endpoint: String
    init(endpoint: String = "https://api.example.com") { self.endpoint = endpoint }
}

final class CountingAPIClient: APIClient, @unchecked Sendable {
    let endpoint: String
    init(endpoint: String = "counted") {
        self.endpoint = endpoint
    }
}

protocol Logger: AnyObject, Sendable {
    func log(_ message: String)
}

final class InMemoryLogger: Logger, @unchecked Sendable {
    private let storage = Counter()
    func log(_ message: String) { storage.increment() }
    var loggedCount: Int { storage.value }
}

/// Atomic counter built on `Synchronization.Mutex` — matches the locking primitive used
/// throughout `Jec` itself, so tests model the same concurrency idioms users will write.
final class Counter: Sendable {
    private let state: Mutex<Int>
    init() { self.state = Mutex(0) }

    func increment() { state.withLock { $0 += 1 } }
    var value: Int { state.withLock { $0 } }
    func reset() { state.withLock { $0 = 0 } }
}

/// Convenience for tests: run inside a fresh, isolated container.
@discardableResult
func withFreshContainer<R: Sendable>(
    _ body: (Container) async throws -> R
) async rethrows -> R {
    let container = Container()
    return try await Container.$current.withValue(container) {
        try await body(container)
    }
}
