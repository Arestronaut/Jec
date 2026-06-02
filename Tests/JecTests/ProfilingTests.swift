import Foundation
import Synchronization
import Testing
@testable import Jec

@Suite("Profiling — Container.onResolve hooks")
struct ProfilingTests {
    @Test func observerFiresOnResolve() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient(endpoint: "https://obs") }

            let events = Events()
            let token = container.onResolve { event in events.append(event) }
            defer { container.removeObserver(token) }

            _ = container.resolve(APIClient.self)
            #expect(events.snapshot().count == 1)
            #expect(events.snapshot()[0].source == .factory)
            #expect(events.snapshot()[0].scope == .singleton)
        }
    }

    @Test func observerDistinguishesCacheHitsFromFactory() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient(endpoint: "x") }

            let events = Events()
            _ = container.onResolve { event in events.append(event) }

            _ = container.resolve(APIClient.self)   // factory
            _ = container.resolve(APIClient.self)   // singleton cache
            _ = container.resolve(APIClient.self)   // singleton cache

            let snapshot = events.snapshot()
            #expect(snapshot.count == 3)
            #expect(snapshot[0].source == .factory)
            #expect(snapshot[1].source == .cacheSingleton)
            #expect(snapshot[2].source == .cacheSingleton)
        }
    }

    @Test func removingObserverStopsEvents() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            let events = Events()
            let token = container.onResolve { event in events.append(event) }
            _ = container.resolve(APIClient.self)
            container.removeObserver(token)
            _ = container.resolve(APIClient.self)
            #expect(events.snapshot().count == 1)
        }
    }

    @Test func resetClearsObservers() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            let events = Events()
            _ = container.onResolve { event in events.append(event) }
            container.reset()
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            _ = container.resolve(APIClient.self)
            #expect(events.snapshot().isEmpty)
        }
    }

    @Test func eventCarriesTypeAndName() async {
        await withFreshContainer { container in
            container.register(APIClient.self, name: "primary", scope: .singleton) { _ in
                LiveAPIClient(endpoint: "p")
            }
            let events = Events()
            _ = container.onResolve { event in events.append(event) }
            _ = container.resolve(APIClient.self, name: "primary")
            let event = events.snapshot()[0]
            #expect(event.typeName.contains("APIClient"))
            #expect(event.name == "primary")
        }
    }
}

/// Mutex-backed Sendable collector for events captured in observers.
final class Events: Sendable {
    private let storage = Mutex<[ResolutionEvent]>([])
    func append(_ event: ResolutionEvent) { storage.withLock { $0.append(event) } }
    func snapshot() -> [ResolutionEvent] { storage.withLock { $0 } }
}
