import Foundation
import Testing
@testable import Jec

@Suite("tryResolveOptional + Container.installing")
struct OptionalAndInstallingTests {
    @Test func optionalReturnsValueWhenRegistered() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient(endpoint: "https://opt") }
            let value = container.tryResolveOptional(APIClient.self)
            #expect(value?.endpoint == "https://opt")
        }
    }

    @Test func optionalReturnsNilWhenMissing() async {
        await withFreshContainer { container in
            let value: APIClient? = container.tryResolveOptional(APIClient.self)
            #expect(value == nil)
        }
    }

    @Test func optionalReturnsNilForAsyncOnlyRegistration() async {
        await withFreshContainer { container in
            container.register(APIClient.self, asyncFactory: { _ in LiveAPIClient() })
            let value: APIClient? = container.tryResolveOptional(APIClient.self)
            #expect(value == nil)
        }
    }

    @Test func installingReturnsSelfAndAppliesAssemblies() async {
        struct EndpointAssembly: Assembly {
            let endpoint: String
            func assemble(in container: Container) {
                container.register(APIClient.self, scope: .singleton) { _ in
                    LiveAPIClient(endpoint: endpoint)
                }
            }
        }
        await Container.$current.withValue(Container()) {
            let container = Container().installing {
                EndpointAssembly(endpoint: "https://chained")
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://chained")
        }
    }

    @Test func installingChainsMultipleAssemblies() async {
        struct A: Assembly {
            func assemble(in container: Container) {
                container.register(String.self) { _ in "from-A" }
            }
        }
        struct B: Assembly {
            func assemble(in container: Container) {
                container.register(Int.self) { _ in 42 }
            }
        }
        await Container.$current.withValue(Container()) {
            let container = Container().installing { A(); B() }
            #expect(container.resolve(String.self) == "from-A")
            #expect(container.resolve(Int.self) == 42)
        }
    }
}
