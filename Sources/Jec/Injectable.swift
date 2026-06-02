import Foundation

/// Marks a type that the container can construct without a hand-written factory closure.
///
/// Conformance is normally synthesised by the ``Injectable()`` macro from the type's
/// single initializer. With the conformance in place you can register the type using
/// the parameterless ``Container/register(_:name:scope:)-injectable`` overload:
///
/// ```swift
/// @Injectable
/// final class UserService: Sendable {
///     let api: APIClient
///     let db: Database
///     init(api: APIClient, db: Database) {
///         self.api = api
///         self.db = db
///     }
/// }
///
/// container.register(UserService.self, scope: .singleton)
/// ```
///
/// Manual conformance is allowed — implement `resolve(from:)` yourself if you need
/// behaviour beyond what the macro generates (e.g. a multi-init type with explicit
/// disambiguation logic).
public protocol Injectable: Sendable {
    /// Build an instance of `Self` by resolving each dependency from `resolver`.
    static func resolve(from resolver: any Resolver) -> Self
}

public extension Container {
    /// Register an ``Injectable`` type without writing a factory closure.
    ///
    /// Equivalent to:
    /// ```swift
    /// container.register(T.self, name: name, scope: scope) { resolver in
    ///     T.resolve(from: resolver)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - type: The concrete type to register. Defaults to `T.self`.
    ///   - name: Optional disambiguating name for resolving multiple registrations of the same type.
    ///   - scope: ``Scope`` for the registration. Defaults to `.transient`.
    func register<T: Injectable>(
        _ type: T.Type = T.self,
        name: String? = nil,
        scope: Scope = .transient
    ) {
        register(type, name: name, scope: scope) { resolver in
            T.resolve(from: resolver)
        }
    }

    /// Register an ``Injectable`` concrete type under a protocol (or other type) it conforms to.
    ///
    /// Combines protocol-keyed registration with ``Injectable``'s factory synthesis:
    ///
    /// ```swift
    /// container.register(APIClient.self, implementedBy: LiveAPIClient.self, scope: .singleton)
    /// ```
    ///
    /// Equivalent to:
    /// ```swift
    /// container.register(APIClient.self, scope: .singleton) { resolver in
    ///     LiveAPIClient.resolve(from: resolver)
    /// }
    /// ```
    ///
    /// Swift's type system cannot express "T conforms to generic protocol P" as a compile-time
    /// constraint. The metatype check `T.self is P.Type` is unreliable for value types and
    /// non-class protocols, so this overload validates at the first resolve via a runtime
    /// cast — mis-wiring traps with a clear message.
    func register<P: Sendable, T: Injectable>(
        _ protocolType: P.Type,
        implementedBy implType: T.Type,
        name: String? = nil,
        scope: Scope = .transient
    ) {
        register(protocolType, name: name, scope: scope) { resolver in
            let instance = T.resolve(from: resolver)
            guard let asProtocol = instance as? P else {
                preconditionFailure(
                    "register(_:implementedBy:): \(T.self) does not conform to \(P.self). " +
                    "Make sure the conformance is in scope at the call site."
                )
            }
            return asProtocol
        }
    }
}

/// Synthesise an ``Injectable`` conformance from the type's single initializer.
///
/// The macro inspects the attached type's initializer parameter list and emits an
/// extension that conforms to ``Injectable`` and provides `resolve(from:)` by calling
/// the init with `resolver.resolve()` for each parameter:
///
/// ```swift
/// @Injectable
/// final class UserService: Sendable {
///     let api: APIClient
///     let db: Database
///     init(api: APIClient, db: Database) { … }
/// }
///
/// // Expands to:
/// extension UserService: Jec.Injectable {
///     public static func resolve(from resolver: any Jec.Resolver) -> UserService {
///         UserService(api: resolver.resolve(), db: resolver.resolve())
///     }
/// }
/// ```
///
/// Requirements:
/// - The type must declare exactly one initializer.
/// - Every initializer parameter type must be registered (or resolvable as a Sendable type).
/// - The type itself must be `Sendable` (the ``Injectable`` protocol requires it).
///
/// For multi-init types or types with non-resolvable init parameters, conform to
/// ``Injectable`` manually instead.
@attached(extension, conformances: Injectable, names: named(resolve))
public macro Injectable() = #externalMacro(module: "JecMacros", type: "InjectableMacro")
