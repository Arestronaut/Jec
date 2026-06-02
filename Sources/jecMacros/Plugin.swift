import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct JecMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        InjectMacro.self,
        InjectableMacro.self,
        ProvidesMacro.self,
        ModuleMacro.self,
    ]
}
