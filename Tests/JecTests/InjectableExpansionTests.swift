#if os(macOS)
import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import Jec
@testable import JecMacros

nonisolated(unsafe) private let injectableMacros: [String: Macro.Type] = [
    "Injectable": InjectableMacro.self,
]

@Suite("@Injectable — macro expansion")
struct InjectableExpansionTests {
    @Test func expandsForLabeledInit() {
        assertMacroExpansion(
            """
            @Injectable
            final class UserService: Sendable {
                let api: APIClient
                let db: Database
                init(api: APIClient, db: Database) {
                    self.api = api
                    self.db = db
                }
            }
            """,
            expandedSource: """
            final class UserService: Sendable {
                let api: APIClient
                let db: Database
                init(api: APIClient, db: Database) {
                    self.api = api
                    self.db = db
                }
            }

            extension UserService: Jec.Injectable {
                public static func resolve(from resolver: any Jec.Resolver) -> UserService {
                    UserService(api: resolver.resolve(), db: resolver.resolve())
                }
            }
            """,
            macros: injectableMacros
        )
    }

    @Test func expandsForUnlabeledInit() {
        assertMacroExpansion(
            """
            @Injectable
            struct GreetingService: Sendable {
                let database: Database
                init(_ database: Database) {
                    self.database = database
                }
            }
            """,
            expandedSource: """
            struct GreetingService: Sendable {
                let database: Database
                init(_ database: Database) {
                    self.database = database
                }
            }

            extension GreetingService: Jec.Injectable {
                public static func resolve(from resolver: any Jec.Resolver) -> GreetingService {
                    GreetingService(resolver.resolve())
                }
            }
            """,
            macros: injectableMacros
        )
    }

    /// Throwing initializers can't be wrapped — `Injectable.resolve(from:)` is non-throwing.
    @Test func diagnosesThrowingInitializer() {
        assertMacroExpansion(
            """
            @Injectable
            struct Bad: Sendable {
                init() throws { }
            }
            """,
            expandedSource: """
            struct Bad: Sendable {
                init() throws { }
            }
            """,
            diagnostics: [
                .init(
                    message: "@Injectable cannot wrap a throwing initializer. `Injectable.resolve(from:)` is non-throwing; conform to `Injectable` manually if the init must throw.",
                    line: 1, column: 1
                )
            ],
            macros: injectableMacros
        )
    }

    /// Failable initializers (`init?`) return `Self?`, incompatible with `resolve(from:) -> Self`.
    @Test func diagnosesFailableInitializer() {
        assertMacroExpansion(
            """
            @Injectable
            struct Bad: Sendable {
                init?() { return nil }
            }
            """,
            expandedSource: """
            struct Bad: Sendable {
                init?() { return nil }
            }
            """,
            diagnostics: [
                .init(
                    message: "@Injectable cannot wrap a failable initializer (`init?`). `Injectable.resolve(from:)` must return a concrete instance; conform to `Injectable` manually to encode the failure path.",
                    line: 1, column: 1
                )
            ],
            macros: injectableMacros
        )
    }
}
#endif
