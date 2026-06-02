import SwiftSyntax
import SwiftSyntaxMacros

public enum InjectMacroError: Error, CustomStringConvertible {
    case notAVariable
    case requiresTypeAnnotation
    case multipleBindings

    public var description: String {
        switch self {
        case .notAVariable:
            "@Inject can only be applied to stored properties."
        case .requiresTypeAnnotation:
            "@Inject requires an explicit type annotation, e.g. `@Inject var api: APIClient`."
        case .multipleBindings:
            "@Inject cannot be applied to a declaration with multiple bindings."
        }
    }
}

public struct InjectMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            throw InjectMacroError.notAVariable
        }
        guard variable.bindings.count == 1, let binding = variable.bindings.first else {
            throw InjectMacroError.multipleBindings
        }
        guard let typeAnnotation = binding.typeAnnotation else {
            throw InjectMacroError.requiresTypeAnnotation
        }

        let typeDescription = typeAnnotation.type.trimmedDescription
        let nameExpression = extractNameArgument(from: node) ?? "nil"

        let accessor: AccessorDeclSyntax = """
        get { Jec.Container.current.resolve((\(raw: typeDescription)).self, name: \(raw: nameExpression)) }
        """
        return [accessor]
    }

    private static func extractNameArgument(from node: AttributeSyntax) -> String? {
        guard case let .argumentList(arguments) = node.arguments else { return nil }
        for argument in arguments where argument.label?.text == "name" {
            return argument.expression.trimmedDescription
        }
        return nil
    }
}
