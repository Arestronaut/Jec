import Foundation

/// Failure modes that can occur while resolving a dependency.
///
/// Each case carries enough context to identify the offending key (type name + optional
/// disambiguating name) and, where relevant, the **resolution chain** — the sequence of
/// types whose factories were on the stack when the failure surfaced. The chain makes it
/// possible to diagnose missing or cyclic dependencies that are deep inside a graph.
public enum ResolutionError: Error, CustomStringConvertible, Sendable {
    /// No registration matches the requested `(type, name)` key.
    case unregistered(type: String, name: String?, chain: [String])
    /// The registration is async-only and was resolved with a synchronous API.
    /// Switch to `resolveAsync` (or `await container.resolveAsync(...)`) to recover.
    case asyncRequired(type: String, name: String?, chain: [String])
    /// The registration uses ``Scope/scoped`` but resolve was called outside a
    /// `Container.withScope { ... }` block on the current Task.
    case scopeRequired(type: String, name: String?, chain: [String])
    /// Resolving `type` would recurse into itself via the factory chain shown.
    /// Indicates a circular dependency in your registration graph.
    case cycle(chain: [String])
    /// Internal mismatch between the cached value's type and the resolve site's type.
    /// Indicates a programming error in the container itself; should not happen in normal use.
    case typeMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case let .unregistered(type, name, chain):
            "No registration for \(type)\(Self.nameSuffix(name)) in the resolver.\(Self.chainSuffix(chain))"
        case let .asyncRequired(type, name, chain):
            "Registration for \(type)\(Self.nameSuffix(name)) is async; use `await container.resolveAsync(...)` instead.\(Self.chainSuffix(chain))"
        case let .scopeRequired(type, name, chain):
            "Registration for \(type)\(Self.nameSuffix(name)) uses `.scoped`; resolve inside `container.withScope { ... }`.\(Self.chainSuffix(chain))"
        case let .cycle(chain):
            "Circular dependency detected: \(chain.joined(separator: " → "))"
        case let .typeMismatch(expected, actual):
            "Resolved value type mismatch — expected \(expected), got \(actual)."
        }
    }

    private static func nameSuffix(_ name: String?) -> String {
        name.map { " (name: \"\($0)\")" } ?? ""
    }

    private static func chainSuffix(_ chain: [String]) -> String {
        chain.isEmpty ? "" : " Resolved via: \(chain.joined(separator: " → "))"
    }
}
