import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import jec
@testable import jecMacros

nonisolated(unsafe) private let macros: [String: Macro.Type] = [
    "Inject": InjectMacro.self,
]

@Suite("Macros — @Inject expansion")
struct MacroTests {
    @Test func expandsToContainerResolveAccessor() {
        assertMacroExpansion(
            """
            struct ViewModel {
                @Inject var api: APIClient
            }
            """,
            expandedSource: """
            struct ViewModel {
                var api: APIClient {
                    get { jec.Container.current.resolve((APIClient).self, name: nil) }
                }
            }
            """,
            macros: macros
        )
    }

    @Test func expandsWithNamedArgument() {
        assertMacroExpansion(
            """
            struct ViewModel {
                @Inject(name: "primary") var api: APIClient
            }
            """,
            expandedSource: """
            struct ViewModel {
                var api: APIClient {
                    get { jec.Container.current.resolve((APIClient).self, name: "primary") }
                }
            }
            """,
            macros: macros
        )
    }

    @Test func diagnosesMissingTypeAnnotation() {
        assertMacroExpansion(
            """
            struct ViewModel {
                @Inject var api = LiveAPIClient()
            }
            """,
            expandedSource: """
            struct ViewModel {
                var api = LiveAPIClient()
            }
            """,
            diagnostics: [
                .init(message: "@Inject requires an explicit type annotation, e.g. `@Inject var api: APIClient`.", line: 2, column: 5)
            ],
            macros: macros
        )
    }
}

// Real-world expansion smoke test (not via macro test harness — we just compile-and-run).
@Suite("Macros — @Inject runtime smoke")
struct MacroRuntimeTests {
    struct ViewModel: Sendable {
        @Inject var api: APIClient
    }

    @Test func macroExpandedAccessorResolvesViaContainer() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient(endpoint: "https://macro") }
            let vm = ViewModel()
            #expect(vm.api.endpoint == "https://macro")
        }
    }
}
