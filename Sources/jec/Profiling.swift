import Foundation

/// Single event emitted to ``Container/onResolve(_:)`` observers when a resolve completes.
public struct ResolutionEvent: Sendable {
    /// Fully-qualified type name of the resolved value, suitable for logs.
    public let typeName: String
    /// Optional disambiguating name on the registration, or `nil` if the registration is unnamed.
    public let name: String?
    /// Scope the registration was declared with.
    public let scope: Scope
    /// Where the resolved value came from on this call.
    public let source: Source
    /// `true` if the resolve was satisfied via ``Container/resolveAsync(_:name:)``.
    public let asyncResolution: Bool

    public enum Source: Sendable, Hashable {
        /// Returned from the singleton cache (factory had already run).
        case cacheSingleton
        /// Returned from the active `.scoped` storage on the current Task.
        case cacheScoped
        /// Returned from the weak cache (`.cached` scope) without rebuilding.
        case cacheWeak
        /// Freshly produced by the registered factory.
        case factory
    }
}

/// Opaque handle returned by ``Container/onResolve(_:)``. Pass to
/// ``Container/removeObserver(_:)`` to detach the observer.
public struct ObserverToken: Hashable, Sendable {
    let id: UUID
}

public extension Container {
    /// Register an observer that fires after every successful resolve on this container.
    ///
    /// Observers run synchronously inside the resolving call, so keep work minimal —
    /// log lines, signposts, counters. Heavy work should hop to a background queue
    /// inside the observer.
    ///
    /// Observers are cleared by ``reset()`` along with registrations and caches.
    ///
    /// - Returns: A token you can pass to ``removeObserver(_:)`` to detach.
    func onResolve(_ observer: @escaping @Sendable (ResolutionEvent) -> Void) -> ObserverToken {
        let token = ObserverToken(id: UUID())
        observersLock.withLock { $0[token.id] = observer }
        return token
    }

    /// Remove an observer previously registered via ``onResolve(_:)``.
    func removeObserver(_ token: ObserverToken) {
        _ = observersLock.withLock { $0.removeValue(forKey: token.id) }
    }

    /// Snapshot the current observer set and invoke each with `event`.
    /// Called from inside `tryResolve` / `resolveAsync` after the result is produced.
    internal func fire(_ event: ResolutionEvent) {
        let snapshot = observersLock.withLock { Array($0.values) }
        for observer in snapshot { observer(event) }
    }
}
