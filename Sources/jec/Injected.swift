import Foundation
import Synchronization

/// Resolves `T` from `Container.current` on every access.
///
/// `Container.current` is a `@TaskLocal`, so tests can swap the container with
/// `Container.$current.withValue(testContainer) { ... }`.
@propertyWrapper
public struct Injected<T: Sendable>: Sendable {
    private let name: String?
    private let typeBox: TypeBox<T>

    public init(_ type: T.Type = T.self, name: String? = nil) {
        self.name = name
        self.typeBox = TypeBox(type)
    }

    public var wrappedValue: T {
        Container.current.resolve(typeBox.type, name: name)
    }
}

/// Resolves once on first access, then returns the cached value on every subsequent access.
///
/// The cache lives behind a `Mutex` inside a reference-typed storage box, so the wrapper itself
/// stays `Sendable` and safe to read from any isolation.
@propertyWrapper
public struct LazyInjected<T: Sendable>: Sendable {
    private let name: String?
    private let typeBox: TypeBox<T>
    private let storage: LazyStorage<T>

    public init(_ type: T.Type = T.self, name: String? = nil) {
        self.name = name
        self.typeBox = TypeBox(type)
        self.storage = LazyStorage()
    }

    public var wrappedValue: T {
        if let existing = storage.read() { return existing }
        let resolved: T = Container.current.resolve(typeBox.type, name: name)
        return storage.commit(resolved)
    }
}

/// Resolves an `AnyObject` dependency on first access and stores a weak reference.
/// Returns `nil` once no other code holds a strong reference. Re-resolves on the next access after that.
@propertyWrapper
public struct WeakInjected<T: AnyObject & Sendable>: Sendable {
    private let name: String?
    private let typeBox: TypeBox<T>
    private let storage: WeakStorage<T>

    public init(_ type: T.Type = T.self, name: String? = nil) {
        self.name = name
        self.typeBox = TypeBox(type)
        self.storage = WeakStorage()
    }

    public var wrappedValue: T? {
        if let live = storage.read() { return live }
        // Use `tryResolveOptional` rather than `resolve` so a missing registration
        // returns `nil` (matching the wrapper's optional return type) rather than
        // trapping. Resolution errors that indicate programming bugs (cycles, type
        // mismatches) still propagate via the trap inside `tryResolveOptional`.
        guard let resolved: T = Container.current.tryResolveOptional(typeBox.type, name: name) else {
            return nil
        }
        storage.set(resolved)
        return resolved
    }
}

// MARK: - Reference-typed storage helpers

/// Reference-typed wrapper around `Mutex<T?>` because `Mutex` is non-Copyable
/// and cannot live as a stored property of a struct.
final class LazyStorage<T: Sendable>: Sendable {
    private let mutex: Mutex<T?>
    init() { self.mutex = Mutex(nil) }

    func read() -> T? {
        mutex.withLock { $0 }
    }

    /// Commits `candidate` if the slot is empty; otherwise returns the already-stored value.
    func commit(_ candidate: T) -> T {
        mutex.withLock { stored in
            if let existing = stored { return existing }
            stored = candidate
            return candidate
        }
    }
}

final class WeakStorage<T: AnyObject & Sendable>: @unchecked Sendable {
    private let mutex: Mutex<WeakBox?>
    init() { self.mutex = Mutex(nil) }

    func read() -> T? {
        mutex.withLock { $0?.raw as? T }
    }

    func set(_ value: T) {
        mutex.withLock { $0 = WeakBox(value) }
    }
}

/// Wraps a metatype so a property wrapper can stay `Sendable` without `@unchecked`.
/// Metatypes are Sendable in Swift 6.2, but a dedicated `Sendable` box keeps the
/// wrapper's stored-property layout uniform across generic instantiations.
struct TypeBox<T>: @unchecked Sendable {
    let type: T.Type
    init(_ type: T.Type) { self.type = type }
}
