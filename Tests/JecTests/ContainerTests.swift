import Foundation
import Testing
@testable import Jec

@Suite("Container — register / resolve / scopes")
struct ContainerTests {
    @Test func transientReturnsNewInstanceEachTime() async {
        let counter = Counter()
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .transient) { _ in
                counter.increment()
                return CountingAPIClient()
            }
            _ = container.resolve(APIClient.self)
            _ = container.resolve(APIClient.self)
            _ = container.resolve(APIClient.self)
            #expect(counter.value == 3)
        }
    }

    @Test func singletonReusesTheSameInstance() async {
        let counter = Counter()
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in
                counter.increment()
                return CountingAPIClient()
            }
            let a = container.resolve(APIClient.self) as! CountingAPIClient
            let b = container.resolve(APIClient.self) as! CountingAPIClient
            #expect(a === b)
            #expect(counter.value == 1)
        }
    }

    @Test func cachedHoldsWeakly() async {
        await withFreshContainer { container in
            container.register(Logger.self, scope: .cached) { _ in InMemoryLogger() }

            weak var weakRef: Logger?
            do {
                let strong = container.resolve(Logger.self)
                weakRef = strong
                let second = container.resolve(Logger.self)
                #expect(strong === second)
            }
            // Strong reference dropped — weak cache should release.
            #expect(weakRef == nil)

            // A subsequent resolve rebuilds. (Not checking identity because Logger is a protocol.)
            _ = container.resolve(Logger.self)
        }
    }

    @Test func namedRegistrationsAreDisambiguated() async {
        await withFreshContainer { container in
            container.register(APIClient.self, name: "primary", scope: .singleton) { _ in
                LiveAPIClient(endpoint: "https://primary")
            }
            container.register(APIClient.self, name: "fallback", scope: .singleton) { _ in
                LiveAPIClient(endpoint: "https://fallback")
            }
            let primary = container.resolve(APIClient.self, name: "primary")
            let fallback = container.resolve(APIClient.self, name: "fallback")
            #expect(primary.endpoint == "https://primary")
            #expect(fallback.endpoint == "https://fallback")
        }
    }

    @Test func unregisteredResolutionThrows() async {
        await withFreshContainer { container in
            #expect(throws: ResolutionError.self) {
                _ = try container.tryResolve(APIClient.self)
            }
        }
    }

    @Test func asyncOnlyRegistrationRejectsSyncResolve() async throws {
        try await withFreshContainer { container in
            container.register(APIClient.self, scope: .transient, asyncFactory: { _ in
                await Task.yield()
                return LiveAPIClient()
            })
            #expect(throws: ResolutionError.self) {
                _ = try container.tryResolve(APIClient.self)
            }
            let resolved: APIClient = try await container.resolveAsync(APIClient.self)
            #expect(resolved.endpoint == "https://api.example.com")
        }
    }

    @Test func resetClearsRegistrationsAndCaches() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            _ = container.resolve(APIClient.self)
            container.reset()
            #expect(throws: ResolutionError.self) {
                _ = try container.tryResolve(APIClient.self)
            }
        }
    }

    @Test func factoryReceivesResolverForSubDependencies() async {
        await withFreshContainer { container in
            container.register(String.self, scope: .singleton) { _ in "https://injected" }
            container.register(APIClient.self, scope: .singleton) { resolver in
                LiveAPIClient(endpoint: resolver.resolve(String.self))
            }
            let api = container.resolve(APIClient.self)
            #expect(api.endpoint == "https://injected")
        }
    }
}
