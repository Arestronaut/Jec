#if os(macOS)
import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import Jec
@testable import JecMacros

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
                    get { Jec.Container.current.resolve((APIClient).self, name: nil) }
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
                    get { Jec.Container.current.resolve((APIClient).self, name: "primary") }
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
#endif
