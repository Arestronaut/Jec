import Foundation

/// Marks a method on a `@Module`-annotated type as a provider of a dependency.
///
/// `@Provides` is a syntactic marker — it produces no code on its own. The enclosing
/// ``Module()`` macro scans for `@Provides` methods and synthesises the assembly's
/// `assemble(in:)` body to register each one.
///
/// ```swift
/// @Module struct NetworkAssembly {
///     let baseURL: URL
///
///     @Provides(.singleton)
///     func session() -> URLSession { .shared }
///
///     @Provides(.singleton)
///     func api(_ session: URLSession) -> APIClient {
///         LiveAPIClient(session: session, baseURL: baseURL)
///     }
/// }
/// ```
///
/// The method's return type becomes the registered key; each parameter is resolved from
/// the container at call time. Pass `name:` to register under a disambiguating name.
@attached(peer)
public macro Provides(
    _ scope: Scope = .transient,
    name: String? = nil
) = #externalMacro(module: "JecMacros", type: "ProvidesMacro")

/// Generate an ``Assembly`` conformance from a struct or class whose methods
/// are marked with ``Provides(_:name:)``.
///
/// The macro expands an extension that adds `Assembly` conformance and synthesises
/// `assemble(in:)` by enumerating every sibling method marked `@Provides`. Each
/// such method becomes a registration:
///
/// - The method's return type is the registered key.
/// - Each method parameter is resolved from the container via `resolver.resolve()`.
/// - The `scope` from the `@Provides` attribute carries through to the registration.
/// - Methods marked `async` use `asyncFactory:`; sync methods use a regular factory.
///
/// ```swift
/// @Module struct NetworkAssembly {
///     let baseURL: URL
///
///     @Provides(.singleton)
///     func session() -> URLSession { .shared }
///
///     @Provides(.singleton)
///     func api(_ session: URLSession) -> APIClient {
///         LiveAPIClient(session: session, baseURL: baseURL)
///     }
/// }
///
/// // Expands to:
/// extension NetworkAssembly: Jec.Assembly {
///     func assemble(in container: Jec.Container) {
///         container.register(URLSession.self, scope: .singleton) { _ in
///             self.session()
///         }
///         container.register(APIClient.self, scope: .singleton) { resolver in
///             self.api(resolver.resolve())
///         }
///     }
/// }
/// ```
///
/// Constraints:
/// - The annotated type must be `Sendable` (required by ``Assembly``).
/// - `@Provides` methods must not throw. Their return type must be `Sendable`.
/// - Parameter types must be registered (or otherwise resolvable as `Sendable`).
@attached(extension, conformances: Assembly, names: named(assemble))
public macro Module() = #externalMacro(module: "JecMacros", type: "ModuleMacro")
