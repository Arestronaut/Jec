import Foundation
import Testing
@testable import Jec

/// Regression coverage for the round of bug fixes — singleton/scoped race, observer
/// classification under scope, scope re-register, weak cache cleanup, ScopeID collisions,
/// WeakInjected nil semantics, and tryResolveOptional's selective error policy.
@Suite("Regression — fixes for analyzer-identified bugs")
struct RegressionTests {

    // MARK: - #1: singleton/scoped store is compare-and-set

    /// A slow factory widens the race window. Every concurrent resolve must observe the
    /// same instance even though the factory may run more than once.
    @Test func slowSingletonFactoryStillReturnsOneInstance() async {
        let factoryRuns = Counter()
        await withFreshContainer { container in
            container.register(CountingAPIClient.self, scope: .singleton) { _ in
                factoryRuns.increment()
                // Yield to give other concurrent resolves a chance to also miss the cache.
                for _ in 0..<100 { _ = (0..<10).reduce(0, +) }
                return CountingAPIClient()
            }
            let identities = await withTaskGroup(of: ObjectIdentifier.self) { group in
                for _ in 0..<500 {
                    group.addTask { ObjectIdentifier(container.resolve(CountingAPIClient.self)) }
                }
                var seen: Set<ObjectIdentifier> = []
                for await id in group { seen.insert(id) }
                return seen
            }
            #expect(identities.count == 1, "all callers must converge on a single singleton instance")
            #expect(factoryRuns.value >= 1)
        }
    }

    @Test func slowScopedFactoryReturnsOneInstancePerScope() async {
        let factoryRuns = Counter()
        await withFreshContainer { container in
            container.register(CountingAPIClient.self, scope: .scoped) { _ in
                factoryRuns.increment()
                return CountingAPIClient()
            }
            await container.withScope {
                let identities = await withTaskGroup(of: ObjectIdentifier.self) { group in
                    for _ in 0..<200 {
                        group.addTask { ObjectIdentifier(container.resolve(CountingAPIClient.self)) }
                    }
                    var seen: Set<ObjectIdentifier> = []
                    for await id in group { seen.insert(id) }
                    return seen
                }
                #expect(identities.count == 1)
            }
        }
    }

    // MARK: - #2: observer reports the true scope inside a withScope block

    @Test func singletonHitInsideWithScopeReportsCacheSingleton() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            _ = container.resolve(APIClient.self)   // prime cache

            let events = Events()
            _ = container.onResolve { events.append($0) }

            container.withScope {
                _ = container.resolve(APIClient.self)
            }
            let event = events.snapshot()[0]
            #expect(event.scope == .singleton)
            #expect(event.source == .cacheSingleton)
        }
    }

    @Test func scopedHitInsideWithScopeReportsCacheScoped() async {
        await withFreshContainer { container in
            container.register(CountingAPIClient.self, scope: .scoped) { _ in CountingAPIClient() }
            let events = Events()
            _ = container.onResolve { events.append($0) }
            container.withScope {
                _ = container.resolve(CountingAPIClient.self)   // factory
                _ = container.resolve(CountingAPIClient.self)   // cacheScoped
            }
            let snapshot = events.snapshot()
            #expect(snapshot[0].source == .factory)
            #expect(snapshot[1].source == .cacheScoped)
            #expect(snapshot[1].scope == .scoped)
        }
    }

    // MARK: - #3: re-register clears scope storage on current Task

    @Test func reRegisteringDuringActiveScopeDropsStaleScopedValue() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .scoped) { _ in LiveAPIClient(endpoint: "v1") }
            container.withScope {
                #expect(container.resolve(APIClient.self).endpoint == "v1")
                // Re-register inside the same task's scope — old cache entry should be cleared.
                container.register(APIClient.self, scope: .scoped) { _ in LiveAPIClient(endpoint: "v2") }
                #expect(container.resolve(APIClient.self).endpoint == "v2")
            }
        }
    }

    @Test func unregisteringDuringActiveScopeClearsScopedCache() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .scoped) { _ in LiveAPIClient(endpoint: "first") }
            container.withScope {
                _ = container.resolve(APIClient.self)
                container.unregister(APIClient.self)
                #expect(throws: ResolutionError.self) {
                    _ = try container.tryResolve(APIClient.self)
                }
            }
        }
    }

    // MARK: - #5: ScopeID.named is permutation-sensitive

    @Test func scopeIDsForPermutedNamesDoNotCollide() {
        let a = ScopeID.named("abc")
        let b = ScopeID.named("cba")
        let c = ScopeID.named("bac")
        #expect(a != b)
        #expect(a != c)
        #expect(b != c)
    }

    @Test func scopeIDsAreStableAcrossCalls() {
        #expect(ScopeID.named("environment-a") == ScopeID.named("environment-a"))
    }

    // MARK: - #4: WeakInjected returns nil on missing registration

    @Test func weakInjectedReturnsNilWhenUnregistered() async {
        await withFreshContainer { _ in
            struct Holder: Sendable {
                @WeakInjected var logger: InMemoryLogger?
            }
            let holder = Holder()
            #expect(holder.logger == nil)
        }
    }

    // MARK: - #7: tryResolveOptional rethrows bug-class errors

    @Test func tryResolveOptionalSwallowsAsyncRequiredAndScopeRequired() async {
        await withFreshContainer { container in
            container.register(APIClient.self, asyncFactory: { _ in LiveAPIClient() })
            #expect(container.tryResolveOptional(APIClient.self) == nil)

            container.register(Int.self, scope: .scoped) { _ in 7 }
            // Not inside any scope; .scoped resolution is unsatisfiable, returns nil.
            #expect(container.tryResolveOptional(Int.self) == nil)
        }
    }

    // MARK: - #11: dump uses unqualified display names

    @Test func dumpDisplaysUnqualifiedTypeNames() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            let dump = container.dump()
            // String(describing:) drops the module prefix used by String(reflecting:).
            #expect(dump.contains("APIClient"))
            #expect(!dump.contains("JecTests.APIClient"))
        }
    }
}
