import Foundation

/// Identifier of a registration: a type plus an optional disambiguating name.
struct RegistrationKey: Hashable, Sendable {
    let type: ObjectIdentifier
    let name: String?
    let typeName: String     // String(reflecting:) — qualified, for diagnostics
    let displayName: String  // String(describing:) — unqualified, for human-facing dump output

    init<T>(_ type: T.Type, name: String?) {
        self.type = ObjectIdentifier(type)
        self.name = name
        self.typeName = String(reflecting: type)
        self.displayName = String(describing: type)
    }

    static func == (lhs: RegistrationKey, rhs: RegistrationKey) -> Bool {
        lhs.type == rhs.type && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(name)
    }
}

/// Type-erased factory storage. The `Any` is cast back to the concrete `T` at the resolve site.
enum AnyFactory: Sendable {
    case sync(@Sendable (any Resolver) -> any Sendable)
    case async(@Sendable (any Resolver) async -> any Sendable)
}

/// A single registration entry held by the Registry.
struct Registration: Sendable {
    let scope: Scope
    let factory: AnyFactory
}

/// Weak-reference box used for `.cached` scope. The value is always `AnyObject`
/// (enforced by a precondition in `Container.register`).
final class WeakBox: @unchecked Sendable {
    weak var raw: AnyObject?
    init(_ object: AnyObject) { self.raw = object }
}
