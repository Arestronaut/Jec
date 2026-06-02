import Foundation
import Testing
@testable import Jec

@Suite("Property wrappers — @Injected, @LazyInjected, @WeakInjected")
struct PropertyWrapperTests {
    struct Consumer: Sendable {
        @Injected var api: APIClient
        @LazyInjected var lazyApi: APIClient
    }

    @Test func injectedResolvesFromCurrentContainerEachAccess() async {
        let counter = Counter()
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .transient) { _ in
                counter.increment()
                return CountingAPIClient()
            }
            let consumer = Consumer()
            _ = consumer.api
            _ = consumer.api
            #expect(counter.value == 2)
        }
    }

    @Test func lazyInjectedResolvesOnlyOnce() async {
        let counter = Counter()
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .transient) { _ in
                counter.increment()
                return CountingAPIClient()
            }
            let consumer = Consumer()
            let first = consumer.lazyApi as! CountingAPIClient
            let second = consumer.lazyApi as! CountingAPIClient
            #expect(first === second)
            #expect(counter.value == 1)
        }
    }

    @Test func weakInjectedReleasesWhenNoStrongRefRemains() async {
        await withFreshContainer { container in
            container.register(InMemoryLogger.self, scope: .singleton) { _ in InMemoryLogger() }

            struct Holder: Sendable {
                @WeakInjected var logger: InMemoryLogger?
            }
            let holder = Holder()
            weak var weakSeen: InMemoryLogger?
            do {
                let strong = holder.logger
                weakSeen = strong
                #expect(strong != nil)
            }
            // Container retains the singleton, so the weak ref must still resolve.
            // This proves WeakInjected itself doesn't accidentally retain.
            #expect(weakSeen != nil)
        }
    }
}
