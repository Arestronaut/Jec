import Foundation
import Synchronization

/// A dependency injection container.
///
/// `Container` is `Sendable`, holds all mutable state inside a `Synchronization.Mutex`, and
/// is safe to use from any isolation domain. Factory closures run **outside** the mutex —
/// the registration is copied out, the lock is released, then the closure executes — so
/// a factory that calls `resolve` for a sibling dependency will not deadlock.
public final class Container: Sendable {
    /// Process-wide default container. Override per-Task via `Container.$current`.
    public static let `default` = Container()

    /// Currently active container for this Task. Override with
    /// `Container.$current.withValue(myContainer) { ... }` in tests or previews.
    @TaskLocal public static var current: Container = .default

    /// Currently active `.scoped` storage for this Task, set by `withScope`.
    @TaskLocal static var activeScope: ScopeStorage?

    /// Stack of registration keys whose factories are currently running on this Task.
    /// Used for diagnostic chains in ``ResolutionError`` and for detecting cycles.
    @TaskLocal static var resolutionStack: [RegistrationKey] = []

    private let state: Mutex<Registry>
    /// Resolution observers registered via ``onResolve(_:)``. Lives in its own mutex so
    /// snapshotting it inside a resolve doesn't contend with registry reads/writes.
    let observersLock: Mutex<[UUID: @Sendable (ResolutionEvent) -> Void]>

    public init() {
        self.state = Mutex(Registry())
        self.observersLock = Mutex([:])
    }

    // MARK: - Registration

    /// Register a synchronous factory.
    ///
    /// `.cached` scope requires the produced value to be a reference type — value-type
    /// registrations under `.cached` will behave like `.transient` because each resolve
    /// produces a fresh boxed value that is immediately released.
    public func register<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil,
        scope: Scope = .transient,
        factory: @escaping @Sendable (any Resolver) -> T
    ) {
        let key = RegistrationKey(type, name: name)
        state.withLock {
            $0.registrations[key] = Registration(
                scope: scope,
                factory: .sync { resolver in factory(resolver) as any Sendable }
            )
            $0.singletons.removeValue(forKey: key)
            $0.weakCache.removeValue(forKey: key)
        }
        // Drop a stale `.scoped` cache entry on the current Task. Other Tasks' active
        // scopes still hold the previous value until they close — TaskLocals are per-Task
        // and unreachable from here.
        Container.activeScope?.remove(key)
    }

    /// Register an asynchronous factory. Required for `@MainActor`-isolated or async-initialised dependencies.
    public func register<T: Sendable>(
        _ type: T.Type = T.self,
        name: String? = nil,
        scope: Scope = .transient,
        asyncFactory: @escaping @Sendable (any Resolver) async -> T
    ) {
        let key = RegistrationKey(type, name: name)
        state.withLock {
            $0.registrations[key] = Registration(
                scope: scope,
                factory: .async { resolver in await asyncFactory(resolver) as any Sendable }
            )
            $0.singletons.removeValue(forKey: key)
            $0.weakCache.removeValue(forKey: key)
        }
        Container.activeScope?.remove(key)
    }

    /// Remove the registration (and any cached instance) for `T`.
    public func unregister<T>(_ type: T.Type = T.self, name: String? = nil) {
        let key = RegistrationKey(type, name: name)
        state.withLock {
            $0.registrations.removeValue(forKey: key)
            $0.singletons.removeValue(forKey: key)
            $0.weakCache.removeValue(forKey: key)
        }
        Container.activeScope?.remove(key)
    }

    /// Return a human-readable listing of every registration on this container —
    /// useful in REPL sessions and breakpoints.
    ///
    /// Each line includes the type name, optional disambiguating name, scope, and
    /// whether the factory is async. Entries are sorted for stable output.
    public func dump() -> String {
        struct Entry {
            let displayName: String
            let name: String?
            let scope: Scope
            let isAsync: Bool
        }
        let entries: [Entry] = state.withLock { registry in
            registry.registrations.map { key, registration in
                let isAsync: Bool
                if case .async = registration.factory { isAsync = true } else { isAsync = false }
                return Entry(displayName: key.displayName, name: key.name, scope: registration.scope, isAsync: isAsync)
            }
        }
        guard !entries.isEmpty else { return "Container is empty." }
        let sorted = entries.sorted { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return (lhs.name ?? "") < (rhs.name ?? "")
        }
        var output = "Container — \(sorted.count) registration(s):\n"
        for entry in sorted {
            let nameSuffix = entry.name.map { " [\($0)]" } ?? ""
            let asyncSuffix = entry.isAsync ? " (async)" : ""
            output += "  - \(entry.displayName)\(nameSuffix) — \(entry.scope)\(asyncSuffix)\n"
        }
        return output
    }

    /// Drop every registration, cached instance, and observer.
    public func reset() {
        state.withLock {
            $0.registrations.removeAll()
            $0.singletons.removeAll()
            $0.weakCache.removeAll()
        }
        observersLock.withLock { $0.removeAll() }
    }

    // MARK: - Resolution

    /// Synchronously resolve `T`. Traps on missing or async-only registration — use `tryResolve` to recover.
    public func resolve<T: Sendable>(_ type: T.Type = T.self, name: String? = nil) -> T {
        do {
            return try tryResolve(type, name: name)
        } catch {
            preconditionFailure("\(error)")
        }
    }

    /// Synchronously resolve `T` if a registration exists and can satisfy a sync call,
    /// otherwise return `nil`.
    ///
    /// Returns `nil` for the "key not satisfiable here" failures — ``ResolutionError/unregistered(type:name:chain:)``,
    /// ``ResolutionError/asyncRequired(type:name:chain:)``, and
    /// ``ResolutionError/scopeRequired(type:name:chain:)``. Programming-bug errors
    /// (``ResolutionError/cycle(chain:)``, ``ResolutionError/typeMismatch(expected:actual:)``)
    /// still trap, because silently returning `nil` for them would hide real bugs.
    public func tryResolveOptional<T: Sendable>(_ type: T.Type = T.self, name: String? = nil) -> T? {
        do {
            return try tryResolve(type, name: name)
        } catch ResolutionError.unregistered, ResolutionError.asyncRequired, ResolutionError.scopeRequired {
            return nil
        } catch {
            preconditionFailure("\(error)")
        }
    }

    /// Synchronously resolve `T`, throwing on missing or async-only registration.
    public func tryResolve<T: Sendable>(_ type: T.Type = T.self, name: String? = nil) throws -> T {
        let key = RegistrationKey(type, name: name)
        try checkForCycle(key: key)
        let plan = try prepare(key: key)
        switch plan {
        case let .cachedSingleton(value):
            let resolved = try cast(value, to: type, key: key)
            fireEvent(key: key, scope: .singleton, source: .cacheSingleton, async: false)
            return resolved
        case let .cachedScoped(value):
            let resolved = try cast(value, to: type, key: key)
            fireEvent(key: key, scope: .scoped, source: .cacheScoped, async: false)
            return resolved
        case let .cachedObject(object):
            let resolved = try cast(object, to: type, key: key)
            fireEvent(key: key, scope: .cached, source: .cacheWeak, async: false)
            return resolved
        case let .build(registration):
            guard case let .sync(factory) = registration.factory else {
                throw ResolutionError.asyncRequired(type: key.typeName, name: name, chain: currentChain())
            }
            let produced = Self.$resolutionStack.withValue(Self.resolutionStack + [key]) {
                factory(self)
            }
            let resolved: T = try storeAndCast(produced, key: key, scope: registration.scope, as: type)
            fireEvent(key: key, scope: registration.scope, source: .factory, async: false)
            return resolved
        }
    }

    /// Async resolve. Works for both sync and async registrations. Named `resolveAsync` (not
    /// an overload of `resolve`) so callers in async contexts don't accidentally pick this path
    /// just because they happen to be inside `await`.
    public func resolveAsync<T: Sendable>(_ type: T.Type = T.self, name: String? = nil) async throws -> T {
        let key = RegistrationKey(type, name: name)
        try checkForCycle(key: key)
        let plan = try prepare(key: key)
        switch plan {
        case let .cachedSingleton(value):
            let resolved = try cast(value, to: type, key: key)
            fireEvent(key: key, scope: .singleton, source: .cacheSingleton, async: true)
            return resolved
        case let .cachedScoped(value):
            let resolved = try cast(value, to: type, key: key)
            fireEvent(key: key, scope: .scoped, source: .cacheScoped, async: true)
            return resolved
        case let .cachedObject(object):
            let resolved = try cast(object, to: type, key: key)
            fireEvent(key: key, scope: .cached, source: .cacheWeak, async: true)
            return resolved
        case let .build(registration):
            let produced: any Sendable
            switch registration.factory {
            case let .sync(factory):
                produced = Self.$resolutionStack.withValue(Self.resolutionStack + [key]) {
                    factory(self)
                }
            case let .async(factory):
                produced = await Self.$resolutionStack.withValue(Self.resolutionStack + [key]) {
                    await factory(self)
                }
            }
            let resolved: T = try storeAndCast(produced, key: key, scope: registration.scope, as: type)
            fireEvent(key: key, scope: registration.scope, source: .factory, async: true)
            return resolved
        }
    }

    /// Dispatch `produced` to the right caching path for `scope`, then cast the winning
    /// value to `T`. `.cached` installs a weak box for the just-produced instance (no
    /// single-flight — see `storeCached`); everything else routes through `storeSendable`,
    /// which compare-and-sets so concurrent first-resolves converge on one instance.
    private func storeAndCast<T>(
        _ produced: any Sendable,
        key: RegistrationKey,
        scope: Scope,
        as type: T.Type
    ) throws -> T {
        if case .cached = scope {
            storeCached(produced as AnyObject, key: key)
            return try cast(produced, to: type, key: key)
        }
        let winner = storeSendable(produced, key: key, scope: scope)
        return try cast(winner, to: type, key: key)
    }

    // MARK: - Observer helpers

    private func fireEvent(key: RegistrationKey, scope: Scope, source: ResolutionEvent.Source, async: Bool) {
        let isEmpty = observersLock.withLock { $0.isEmpty }
        guard !isEmpty else { return }
        fire(ResolutionEvent(
            typeName: key.typeName,
            name: key.name,
            scope: scope,
            source: source,
            asyncResolution: async
        ))
    }

    // MARK: - Diagnostic helpers

    private func checkForCycle(key: RegistrationKey) throws {
        if Self.resolutionStack.contains(key) {
            let chain = Self.resolutionStack.map(\.typeName) + [key.typeName]
            throw ResolutionError.cycle(chain: chain)
        }
    }

    private func currentChain() -> [String] {
        Self.resolutionStack.map(\.typeName)
    }

    // MARK: - Scoped lifetime

    /// Open a `.scoped` lifetime block on the current Task. Instances registered with
    /// scope `.scoped` are reused inside `perform`; nested calls create independent buckets.
    public func withScope<R>(
        _ id: ScopeID = .anonymous(),
        perform: () async throws -> R
    ) async rethrows -> R {
        let storage = ScopeStorage(id: id)
        return try await Container.$activeScope.withValue(storage) {
            try await perform()
        }
    }

    /// Synchronous variant of `withScope` for non-async call sites.
    public func withScope<R>(
        _ id: ScopeID = .anonymous(),
        perform: () throws -> R
    ) rethrows -> R {
        let storage = ScopeStorage(id: id)
        return try Container.$activeScope.withValue(storage) {
            try perform()
        }
    }

    // MARK: - Internal

    private enum ResolutionPlan {
        case cachedSingleton(any Sendable)   // `.singleton` cache hit
        case cachedScoped(any Sendable)      // `.scoped` cache hit (TaskLocal storage)
        case cachedObject(AnyObject)         // `.cached` weak cache hit
        case build(Registration)
    }

    /// Look up the registration and any cached value, releasing the mutex before the factory runs.
    private func prepare(key: RegistrationKey) throws -> ResolutionPlan {
        // Try the TaskLocal scope cache first — that path doesn't even touch the registry mutex
        // for hits, which keeps `.scoped` resolves cheap under contention.
        if let scope = Container.activeScope, let cached = scope.get(key) {
            return .cachedScoped(cached)
        }

        let chain = currentChain()
        return try state.withLock { state in
            guard let registration = state.registrations[key] else {
                throw ResolutionError.unregistered(type: key.typeName, name: key.name, chain: chain)
            }

            switch registration.scope {
            case .singleton:
                if let existing = state.singletons[key] {
                    return .cachedSingleton(existing)
                }
            case .cached:
                if let box = state.weakCache[key] {
                    if let live = box.raw {
                        return .cachedObject(live)
                    }
                    // Box is alive but its target was deallocated — evict so it doesn't
                    // accumulate when the key is rarely re-resolved.
                    state.weakCache.removeValue(forKey: key)
                }
            case .scoped:
                guard Container.activeScope != nil else {
                    throw ResolutionError.scopeRequired(type: key.typeName, name: key.name, chain: chain)
                }
                // Miss already verified above; fall through to build.
            case .transient:
                break
            }
            return .build(registration)
        }
    }

    /// Place a freshly-produced instance into the appropriate cache for its scope and return
    /// the value that callers should observe.
    ///
    /// For caching scopes (`.singleton`, `.scoped`, `.cached`), `store` is a compare-and-set:
    /// if another Task populated the cache between this caller's `prepare` and `store`, the
    /// just-produced value is dropped and the previously-cached one is returned instead. This
    /// single-flights concurrent first-resolves so every caller sees the same instance even
    /// when the factory ran more than once. (The factory itself is *not* deduplicated — it
    /// can still run multiple times under contention, which is why factories should be
    /// idempotent and side-effect-free.)
    ///
    /// Split into Sendable / AnyObject overloads because `Sendable` is a marker protocol
    /// and cannot appear in a runtime cast — the `.cached` path needs to return `AnyObject`
    /// so the cached live reference can be handed back without a Sendable cast.
    private func storeSendable(_ value: any Sendable, key: RegistrationKey, scope: Scope) -> any Sendable {
        switch scope {
        case .singleton:
            return state.withLock { state in
                if let existing = state.singletons[key] { return existing }
                state.singletons[key] = value
                return value
            }
        case .scoped:
            guard let scope = Container.activeScope else { return value }
            return scope.commit(key, value)
        case .transient:
            return value
        case .cached:
            // Caller dispatches `.cached` to `storeCached`; this branch is unreachable.
            preconditionFailure("storeSendable should not be invoked for .cached scope.")
        }
    }

    /// Install a fresh weak box for the `.cached` key. Unlike the singleton/scoped paths,
    /// this is *not* a compare-and-set: under concurrent first-resolves two callers may
    /// briefly observe distinct instances and the second `WeakBox` overwrites the first.
    /// This matches the weak-cache contract — `.cached` already promises only "shared while
    /// at least one consumer holds it" — and avoids a Sendable-marker-protocol round-trip
    /// that the language can't currently express across a `Mutex.withLock` boundary.
    private func storeCached(_ value: AnyObject, key: RegistrationKey) {
        state.withLock { state in
            state.weakCache[key] = WeakBox(value)
        }
    }

    private func cast<T>(_ value: any Sendable, to _: T.Type, key: RegistrationKey) throws -> T {
        guard let typed = value as? T else {
            throw ResolutionError.typeMismatch(
                expected: key.typeName,
                actual: String(reflecting: Swift.type(of: value))
            )
        }
        return typed
    }

    private func cast<T>(_ object: AnyObject, to _: T.Type, key: RegistrationKey) throws -> T {
        guard let typed = object as? T else {
            throw ResolutionError.typeMismatch(
                expected: key.typeName,
                actual: String(reflecting: Swift.type(of: object))
            )
        }
        return typed
    }
}

// `Container` satisfies the `Resolver` protocol via its public `resolve`/`tryResolve` methods
// (defaulted arguments still match the protocol requirements).
extension Container: Resolver {}
