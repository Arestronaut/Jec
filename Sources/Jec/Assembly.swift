import Foundation

/// A reusable bundle of registrations.
///
/// Conform a type to `Assembly` and call `container.install { MyAssembly() }` to apply it.
/// `assemble(in:)` runs synchronously and uses the standard `Container.register` API, so
/// last-writer-wins semantics, scopes, and Sendable requirements behave identically to
/// direct registration.
///
/// ```swift
/// struct NetworkAssembly: Assembly {
///     let baseURL: URL
///     func assemble(in container: Container) {
///         container.register(URLSession.self, scope: .singleton) { _ in .shared }
///         container.register(APIClient.self, scope: .singleton) { r in
///             LiveAPIClient(session: r.resolve(), baseURL: baseURL)
///         }
///     }
/// }
/// ```
public protocol Assembly: Sendable {
    func assemble(in container: Container)
}

/// Result builder for `Container.install` so call sites can read declaratively.
///
/// Supports plain lists, `if`/`else`, optional bindings, and `for` loops. Each statement
/// in the block normalises to `[any Assembly]` via `buildExpression`, so bare assemblies
/// and conditional/loop branches compose uniformly.
@resultBuilder
public enum AssemblyBuilder {
    public static func buildExpression(_ assembly: any Assembly) -> [any Assembly] {
        [assembly]
    }

    public static func buildExpression(_ assemblies: [any Assembly]) -> [any Assembly] {
        assemblies
    }

    public static func buildBlock(_ components: [any Assembly]...) -> [any Assembly] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ assemblies: [any Assembly]?) -> [any Assembly] {
        assemblies ?? []
    }

    public static func buildEither(first assemblies: [any Assembly]) -> [any Assembly] {
        assemblies
    }

    public static func buildEither(second assemblies: [any Assembly]) -> [any Assembly] {
        assemblies
    }

    public static func buildArray(_ arrays: [[any Assembly]]) -> [any Assembly] {
        arrays.flatMap(\.self)
    }
}

public extension Container {
    /// Install one or more assemblies into this container.
    ///
    /// Assemblies run in declared order. Later registrations overwrite earlier ones
    /// for the same `(type, name)` key, the same as calling `register` twice directly.
    func install(@AssemblyBuilder _ build: () -> [any Assembly]) {
        for assembly in build() {
            assembly.assemble(in: self)
        }
    }

    /// Fluent variant of ``install(_:)`` that returns `self` for chained setup.
    ///
    /// ```swift
    /// let container = Container().installing {
    ///     NetworkAssembly(baseURL: apiURL)
    ///     PersistenceAssembly()
    /// }
    /// ```
    @discardableResult
    func installing(@AssemblyBuilder _ build: () -> [any Assembly]) -> Self {
        install(build)
        return self
    }
}
