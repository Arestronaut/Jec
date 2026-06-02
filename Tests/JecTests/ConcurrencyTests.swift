import Foundation
import Testing
@testable import Jec

@Suite("Concurrency — parallel resolution, MainActor, child-task scope propagation")
struct ConcurrencyTests {
    @Test func parallelResolveConvergesOnSingleSingleton() async {
        let counter = Counter()
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in
                counter.increment()
                return CountingAPIClient()
            }

            let identities = await withTaskGroup(of: ObjectIdentifier.self) { group in
                for _ in 0..<1000 {
                    group.addTask {
                        let resolved = container.resolve(APIClient.self) as AnyObject
                        return ObjectIdentifier(resolved)
                    }
                }
                var seen: Set<ObjectIdentifier> = []
                for await id in group { seen.insert(id) }
                return seen
            }
            // The contract is "single instance per container", not "factory runs once".
            // Under contention the factory may run more than once — the compare-and-set
            // in `store` guarantees only the first stored value escapes and every caller
            // observes the same instance.
            #expect(identities.count == 1)
            #expect(counter.value >= 1)
        }
    }

    @MainActor
    final class MainActorViewModel: Sendable {
        let endpoint: String
        init(endpoint: String) { self.endpoint = endpoint }
    }

    @Test func mainActorBoundTypeResolvesViaAsyncFactory() async throws {
        try await withFreshContainer { container in
            container.register(MainActorViewModel.self, scope: .singleton, asyncFactory: { _ in
                await MainActor.run { MainActorViewModel(endpoint: "main") }
            })
            let vm: MainActorViewModel = try await container.resolveAsync(MainActorViewModel.self)
            await MainActor.run {
                #expect(vm.endpoint == "main")
            }
        }
    }

    @Test func containerCurrentTaskLocalOverrideIsRespectedInChildTasks() async {
        let testContainer = Container()
        testContainer.register(APIClient.self, scope: .singleton) { _ in
            LiveAPIClient(endpoint: "https://test-override")
        }
        await Container.$current.withValue(testContainer) {
            // From a child Task, @Injected and Container.current must resolve from testContainer.
            let endpoint = await Task {
                Container.current.resolve(APIClient.self).endpoint
            }.value
            #expect(endpoint == "https://test-override")
        }
    }
}
