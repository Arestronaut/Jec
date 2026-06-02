import SwiftSyntax
import SwiftSyntaxMacros

/// `@Provides` is a syntactic marker for ``ModuleMacro`` to discover. It produces
/// no code on its own — the enclosing `@Module` macro reads `@Provides` annotations
/// from its sibling methods to synthesise registrations.
///
/// The macro is declared as a `PeerMacro` because Swift requires attributes to be
/// either macros or built-in. Producing an empty peer list is the lightest-weight
/// way to make `@Provides(.singleton)` a legal attribute.
public struct ProvidesMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
