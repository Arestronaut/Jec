#if canImport(SwiftUI)
import SwiftUI
import Jec

/// SwiftUI-aware dependency injection that reads from `@Environment(\.jecContainer)`
/// rather than the `Container.current` TaskLocal.
///
/// Use this inside SwiftUI views; use the plain `@Injected` property wrapper elsewhere.
/// The two coexist on the same dependency — they just consult different sources for
/// the active container.
///
/// ```swift
/// struct UserBadge: View {
///     @EnvironmentInjected var api: APIClient
///     let userID: String
///     var body: some View {
///         AsyncImage(url: api.avatarURL(for: userID))
///     }
/// }
/// ```
///
/// Pass `name:` to resolve a named registration:
///
/// ```swift
/// @EnvironmentInjected(name: "primary") var db: Database
/// ```
@propertyWrapper
public struct EnvironmentInjected<T: Sendable>: DynamicProperty {
    @Environment(\.jecContainer) private var container
    private let typeBox: TypeBox<T>
    private let name: String?

    public init(_ type: T.Type = T.self, name: String? = nil) {
        self.typeBox = TypeBox(type)
        self.name = name
    }

    public var wrappedValue: T {
        container.resolve(typeBox.type, name: name)
    }
}

/// Wraps a metatype so the property wrapper stays `Sendable` without `@unchecked`.
struct TypeBox<T>: @unchecked Sendable {
    let type: T.Type
    init(_ type: T.Type) { self.type = type }
}
#endif
