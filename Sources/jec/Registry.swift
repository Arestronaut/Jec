import Foundation
import Synchronization

/// Internal mutable state held inside `Mutex<Registry>` on `Container`.
///
/// `.scoped` lifetime instances live in `Container.$activeScope`'s storage (a TaskLocal),
/// not here — so different Tasks never contend on scope cache reads.
struct Registry: Sendable {
    var registrations: [RegistrationKey: Registration] = [:]
    var singletons: [RegistrationKey: any Sendable] = [:]
    var weakCache: [RegistrationKey: WeakBox] = [:]
}

/// TaskLocal-backed storage for `.scoped` instances. Boxed in a final class so the
/// dictionary can be mutated atomically by replacing the reference in the TaskLocal.
final class ScopeStorage: Sendable {
    let id: ScopeID
    private let cache: Mutex<[RegistrationKey: any Sendable]>

    init(id: ScopeID) {
        self.id = id
        self.cache = Mutex([:])
    }

    func get(_ key: RegistrationKey) -> (any Sendable)? {
        cache.withLock { $0[key] }
    }

    /// Compare-and-set: commit `candidate` only if the slot is empty, otherwise return the
    /// existing value. Used by `Container.store` to single-flight `.scoped` resolves under
    /// contention so concurrent child Tasks converge on a single instance per scope.
    func commit(_ key: RegistrationKey, _ candidate: any Sendable) -> any Sendable {
        cache.withLock { dict in
            if let existing = dict[key] { return existing }
            dict[key] = candidate
            return candidate
        }
    }

    /// Drop the cached value for `key`. Called by `Container.register`/`unregister` so a
    /// fresh registration on the current Task isn't shadowed by a stale scope cache entry.
    func remove(_ key: RegistrationKey) {
        cache.withLock { $0[key] = nil }
    }
}
