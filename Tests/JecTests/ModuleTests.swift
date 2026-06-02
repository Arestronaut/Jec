import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import Jec
@testable import JecMacros

nonisolated(unsafe) private let moduleMacros: [String: Macro.Type] = [
    "Module": ModuleMacro.self,
    "Provides": ProvidesMacro.self,
]

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

@Suite("@Module — macro expansion")
struct ModuleExpansionTests {
    @Test func expandsToAssemblyConformanceAndRegistrations() {
        assertMacroExpansion(
            """
            @Module
            struct DemoModule {
                @Provides(.singleton)
                func session() -> URLSession { .shared }

                @Provides(.singleton)
                func api(_ session: URLSession) -> APIClient {
                    LiveAPIClient(session: session)
                }
            }
            """,
            expandedSource: """
            struct DemoModule {
                func session() -> URLSession { .shared }
                func api(_ session: URLSession) -> APIClient {
                    LiveAPIClient(session: session)
                }
            }

            extension DemoModule: Jec.Assembly {
                public func assemble(in container: Jec.Container) {
                    container.register(URLSession.self, scope: .singleton) { resolver in self.session() }
                    container.register(APIClient.self, scope: .singleton) { resolver in self.api(resolver.resolve()) }
                }
            }
            """,
            macros: moduleMacros
        )
    }

    @Test func emptyModuleStillSatisfiesAssembly() {
        assertMacroExpansion(
            """
            @Module
            struct Empty {}
            """,
            expandedSource: """
            struct Empty {}

            extension Empty: Jec.Assembly {
                public func assemble(in container: Jec.Container) {
                    // no @Provides methods declared
                }
            }
            """,
            macros: moduleMacros
        )
    }
}

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
