#if os(macOS)
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
#endif
