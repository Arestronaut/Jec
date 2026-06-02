/// Inline accessor macro that resolves the annotated property from `Container.current`
/// on every access. The expansion uses the enclosing type's isolation automatically,
/// so it composes with `@MainActor` types and actors without the property-wrapper
/// isolation issues described in SE-0401.
///
/// ```
/// struct ViewModel {
///     @Inject var api: APIClient
/// }
/// // Expands to:
/// struct ViewModel {
///     var api: APIClient {
///         get { Container.current.resolve(APIClient.self, name: nil) }
///     }
/// }
/// ```
///
/// Pass `name:` to resolve a named registration:
///
/// ```
/// @Inject(name: "primary") var api: APIClient
/// ```
@attached(accessor)
public macro Inject(name: String? = nil) = #externalMacro(module: "jecMacros", type: "InjectMacro")
