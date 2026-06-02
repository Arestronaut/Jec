import Foundation

/// Type used by factory closures to resolve sub-dependencies without holding a reference to a ``Container``.
///
/// Inside a registration's `factory: (any Resolver) -> T` closure, call `resolver.resolve(...)` to
/// obtain values for the type's collaborators. The resolver passed in is the same container the
/// factory is registered against, exposed through this narrower protocol to avoid leaking
/// registration APIs into factory bodies.
public protocol Resolver: Sendable {
    /// Synchronously resolve `T`. Traps on missing or async-only registrations.
    /// Use ``tryResolve(_:name:)-9b3i7`` to recover from errors instead.
    func resolve<T: Sendable>(_ type: T.Type, name: String?) -> T

    /// Synchronously resolve `T`, throwing ``ResolutionError`` on failure.
    func tryResolve<T: Sendable>(_ type: T.Type, name: String?) throws -> T

    /// Resolve `T` if a sync registration exists, otherwise return `nil`.
    /// Never throws — designed for "use it if present" call sites.
    func tryResolveOptional<T: Sendable>(_ type: T.Type, name: String?) -> T?

    /// Asynchronously resolve `T`. Works for both sync and async registrations.
    func resolveAsync<T: Sendable>(_ type: T.Type, name: String?) async throws -> T
}

public extension Resolver {
    /// Shorthand for ``resolve(_:name:)-7w4lk`` with `name: nil`.
    func resolve<T: Sendable>(_ type: T.Type = T.self) -> T {
        resolve(type, name: nil)
    }

    /// Shorthand for ``tryResolve(_:name:)-9b3i7`` with `name: nil`.
    func tryResolve<T: Sendable>(_ type: T.Type = T.self) throws -> T {
        try tryResolve(type, name: nil)
    }

    /// Shorthand for ``tryResolveOptional(_:name:)`` with `name: nil`.
    func tryResolveOptional<T: Sendable>(_ type: T.Type = T.self) -> T? {
        tryResolveOptional(type, name: nil)
    }

    /// Shorthand for ``resolveAsync(_:name:)-3prbu`` with `name: nil`.
    func resolveAsync<T: Sendable>(_ type: T.Type = T.self) async throws -> T {
        try await resolveAsync(type, name: nil)
    }
}
