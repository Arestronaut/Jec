import Foundation
import Testing
@testable import jec

@Suite("Scope — .scoped lifetime via TaskLocal")
struct ScopeTests {
    @Test func scopedInstancesReusedWithinABlock() async throws {
        let counter = Counter()
        try await withFreshContainer { container in
            container.register(APIClient.self, scope: .scoped) { _ in
                counter.increment()
                return CountingAPIClient()
            }
            try await container.withScope {
                let a = container.resolve(APIClient.self) as! CountingAPIClient
                let b = container.resolve(APIClient.self) as! CountingAPIClient
                #expect(a === b)
            }
            #expect(counter.value == 1)
        }
    }

    @Test func scopedResolutionOutsideScopeThrows() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .scoped) { _ in LiveAPIClient() }
            #expect(throws: ResolutionError.self) {
                _ = try container.tryResolve(APIClient.self)
            }
        }
    }

    @Test func nestedScopesGetIndependentBuckets() async throws {
        let counter = Counter()
        try await withFreshContainer { container in
            container.register(APIClient.self, scope: .scoped) { _ in
                counter.increment()
                return CountingAPIClient()
            }
            try await container.withScope(.named("outer")) {
                let outer = container.resolve(APIClient.self) as! CountingAPIClient
                try await container.withScope(.named("inner")) {
                    let inner = container.resolve(APIClient.self) as! CountingAPIClient
                    #expect(inner !== outer)
                }
                // Back in the outer scope — same instance as before.
                let outerAgain = container.resolve(APIClient.self) as! CountingAPIClient
                #expect(outerAgain === outer)
            }
            #expect(counter.value == 2)
        }
    }

    @Test func scopePropagatesToChildTasks() async throws {
        try await withFreshContainer { container in
            container.register(APIClient.self, scope: .scoped) { _ in CountingAPIClient() }

            try await container.withScope {
                let primary = container.resolve(APIClient.self) as! CountingAPIClient
                let viaChildTask = await Task {
                    container.resolve(APIClient.self) as! CountingAPIClient
                }.value
                #expect(primary === viaChildTask)
            }
        }
    }
}
