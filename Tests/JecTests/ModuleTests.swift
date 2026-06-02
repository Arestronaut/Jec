import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Jec

// MARK: - Runtime fixtures

@Module
private struct DemoModule {
    let endpoint: String

    @Provides(.singleton)
    func session() -> URLSession { .shared }

    @Provides(.singleton)
    func api(_ session: URLSession) -> APIClient {
        LiveAPIClient(endpoint: endpoint)
    }
}

@Module
private struct NamedModule {
    @Provides(.singleton, name: "primary")
    func primary() -> APIClient { LiveAPIClient(endpoint: "https://primary") }

    @Provides(.singleton, name: "fallback")
    func fallback() -> APIClient { LiveAPIClient(endpoint: "https://fallback") }
}

@Module
private struct EmptyModule {}

@Suite("@Module — runtime install + resolve")
struct ModuleRuntimeTests {
    @Test func installModuleAndResolveByType() async {
        await withFreshContainer { container in
            container.install { DemoModule(endpoint: "https://module") }
            let api = container.resolve(APIClient.self)
            #expect(api.endpoint == "https://module")
            let session = container.resolve(URLSession.self)
            #expect(session === URLSession.shared)
        }
    }

    @Test func namedRegistrationsViaProvides() async {
        await withFreshContainer { container in
            container.install { NamedModule() }
            #expect(container.resolve(APIClient.self, name: "primary").endpoint == "https://primary")
            #expect(container.resolve(APIClient.self, name: "fallback").endpoint == "https://fallback")
        }
    }

    @Test func emptyModuleInstallsCleanly() async {
        await withFreshContainer { container in
            container.install { EmptyModule() }
            // No registrations expected; the install completes without error.
            #expect(container.dump() == "Container is empty.")
        }
    }

    @Test func assemblyConformanceIsSynthesised() {
        let _: any Assembly = DemoModule(endpoint: "")
        let _: any Assembly = NamedModule()
        let _: any Assembly = EmptyModule()
    }
}
