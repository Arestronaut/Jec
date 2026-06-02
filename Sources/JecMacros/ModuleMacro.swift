import SwiftSyntax
import SwiftSyntaxMacros

public enum ModuleMacroError: Error, CustomStringConvertible {
    case providesMethodMustReturnAType(method: String)
    case providesMethodIsThrowing(method: String)

    public var description: String {
        switch self {
        case let .providesMethodMustReturnAType(method):
            "@Provides method '\(method)' must declare a return type."
        case let .providesMethodIsThrowing(method):
            "@Provides method '\(method)' must not throw. Factory closures cannot propagate errors."
        }
    }
}

public struct ModuleMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let typeName = type.trimmedDescription

        let providesMethods = declaration.memberBlock.members
            .compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter(hasProvidesAttribute)

        let registrationLines = try providesMethods.map { method in
            try registrationLine(for: method)
        }

        let body: String
        if registrationLines.isEmpty {
            body = "// no @Provides methods declared"
        } else {
            body = registrationLines.joined(separator: "\n        ")
        }

        let ext: DeclSyntax = """
        extension \(raw: typeName): Jec.Assembly {
            public func assemble(in container: Jec.Container) {
                \(raw: body)
            }
        }
        """
        guard let extDecl = ext.as(ExtensionDeclSyntax.self) else { return [] }
        return [extDecl]
    }

    // MARK: - Helpers

    private static func hasProvidesAttribute(_ method: FunctionDeclSyntax) -> Bool {
        method.attributes.contains { attr in
            providesAttribute(attr) != nil
        }
    }

    private static func providesAttribute(_ attr: AttributeListSyntax.Element) -> AttributeSyntax? {
        guard case let .attribute(attribute) = attr else { return nil }
        let name = attribute.attributeName.trimmedDescription
        return (name == "Provides" || name.hasSuffix(".Provides")) ? attribute : nil
    }

    private static func registrationLine(for method: FunctionDeclSyntax) throws -> String {
        let methodName = method.name.text
        guard let returnType = method.signature.returnClause?.type.trimmedDescription else {
            throw ModuleMacroError.providesMethodMustReturnAType(method: methodName)
        }
        if method.signature.effectSpecifiers?.throwsClause != nil {
            throw ModuleMacroError.providesMethodIsThrowing(method: methodName)
        }
        let isAsync = method.signature.effectSpecifiers?.asyncSpecifier != nil

        let providesAttr = method.attributes.compactMap(providesAttribute).first!
        let (scope, name) = extractProvidesArguments(providesAttr)

        let argList = method.signature.parameterClause.parameters.map(callArgument).joined(separator: ", ")
        let invocation = "self.\(methodName)(\(argList))"
        let nameArg = name.map { ", name: \($0)" } ?? ""

        if isAsync {
            return "container.register(\(returnType).self\(nameArg), scope: \(scope), asyncFactory: { resolver in await \(invocation) })"
        } else {
            return "container.register(\(returnType).self\(nameArg), scope: \(scope)) { resolver in \(invocation) }"
        }
    }

    private static func callArgument(for param: FunctionParameterSyntax) -> String {
        let firstName = param.firstName.text
        return firstName == "_" ? "resolver.resolve()" : "\(firstName): resolver.resolve()"
    }

    /// Extract `(scope, name)` from `@Provides(.singleton, name: "primary")`.
    /// Returns `(".transient", nil)` if `@Provides` is invoked with no arguments.
    private static func extractProvidesArguments(_ attr: AttributeSyntax) -> (scope: String, name: String?) {
        var scope = ".transient"
        var name: String? = nil
        guard case let .argumentList(args) = attr.arguments else { return (scope, name) }
        for (index, arg) in args.enumerated() {
            if arg.label?.text == "name" {
                name = arg.expression.trimmedDescription
            } else if index == 0 {
                scope = arg.expression.trimmedDescription
            }
        }
        return (scope, name)
    }
}
