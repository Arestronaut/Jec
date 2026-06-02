import SwiftSyntax
import SwiftSyntaxMacros

public enum InjectableMacroError: Error, CustomStringConvertible {
    case noInitializer
    case multipleInitializers
    case throwingInitializer
    case failableInitializer

    public var description: String {
        switch self {
        case .noInitializer:
            "@Injectable requires the type to declare exactly one initializer."
        case .multipleInitializers:
            "@Injectable requires exactly one initializer. Conform to `Injectable` manually if you need to handle multiple inits."
        case .throwingInitializer:
            "@Injectable cannot wrap a throwing initializer. `Injectable.resolve(from:)` is non-throwing; conform to `Injectable` manually if the init must throw."
        case .failableInitializer:
            "@Injectable cannot wrap a failable initializer (`init?`). `Injectable.resolve(from:)` must return a concrete instance; conform to `Injectable` manually to encode the failure path."
        }
    }
}

public struct InjectableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let typeName = type.trimmedDescription

        let inits = declaration.memberBlock.members.compactMap {
            $0.decl.as(InitializerDeclSyntax.self)
        }
        guard !inits.isEmpty else {
            throw InjectableMacroError.noInitializer
        }
        guard inits.count == 1 else {
            throw InjectableMacroError.multipleInitializers
        }
        if inits[0].signature.effectSpecifiers?.throwsClause != nil {
            throw InjectableMacroError.throwingInitializer
        }
        if inits[0].optionalMark != nil {
            throw InjectableMacroError.failableInitializer
        }

        let arguments = inits[0].signature.parameterClause.parameters
            .map(callArgument(for:))
            .joined(separator: ", ")

        let ext: DeclSyntax = """
        extension \(raw: typeName): Jec.Injectable {
            public static func resolve(from resolver: any Jec.Resolver) -> \(raw: typeName) {
                \(raw: typeName)(\(raw: arguments))
            }
        }
        """

        guard let extensionDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
        return [extensionDecl]
    }

    /// Build a single argument string for the synthesised initializer call.
    /// Honours the external label (or `_`) so `init(_ x: T)` produces `resolver.resolve()`
    /// and `init(api: T)` produces `api: resolver.resolve()`.
    private static func callArgument(for parameter: FunctionParameterSyntax) -> String {
        let firstName = parameter.firstName.text
        if firstName == "_" {
            return "resolver.resolve()"
        }
        return "\(firstName): resolver.resolve()"
    }
}
