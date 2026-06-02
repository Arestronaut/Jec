# Choosing a scope

Pick the right ``Scope`` for each dependency based on lifetime and sharing requirements.

## Overview

Every registration carries a ``Scope`` that determines how many instances of the dependency exist and when they're released.

| Scope | Instances | Released when | Typical use |
|---|---|---|---|
| ``Scope/transient`` | New on every resolve | Immediately (caller owns it) | Stateless values, request DTOs |
| ``Scope/singleton`` | One per container | Container is released | Network clients, databases, loggers |
| ``Scope/cached`` | One while consumers retain it | All strong refs drop | Lazily-built workers, on-demand caches |
| ``Scope/scoped`` | One per ``Container/withScope(_:perform:)-9rmuy`` block | The block exits | Per-request state, per-screen context |

`transient` is the default — registering without a `scope:` argument behaves like `.transient`.

## `.singleton`

Use for any dependency that should be created once and shared. The factory runs lazily on the first `resolve`.

```swift
container.register(URLSession.self, scope: .singleton) { _ in .shared }
container.register(Logger.self, scope: .singleton) { _ in OSLogger() }
```

`.singleton` requires `T: Sendable`. The instance lives inside a `Synchronization.Mutex` and is safe to read from any isolation.

The container compare-and-sets the singleton on first store, so even when several Tasks race the first resolve they all observe the same instance. Note that the factory itself is not deduplicated — it may run more than once under contention, with all but one result dropped — so factories should be idempotent and side-effect-free.

## `.transient`

Every `resolve` invokes the factory afresh:

```swift
container.register(UUID.self, scope: .transient) { _ in UUID() }

let a = container.resolve(UUID.self)
let b = container.resolve(UUID.self)
assert(a != b)
```

Use for short-lived values, parameter objects, or anything where shared state would be wrong.

## `.cached`

Weak-referenced. The container holds onto the instance only while at least one consumer is keeping it alive — once they all release it, the cache is empty and the next `resolve` rebuilds.

```swift
container.register(ImageDecoder.self, scope: .cached) { _ in ImageDecoder() }

do {
    let decoder = container.resolve(ImageDecoder.self)   // built
    let again   = container.resolve(ImageDecoder.self)   // same instance
}
// `decoder` and `again` released — cache now empty.
let fresh = container.resolve(ImageDecoder.self)         // rebuilt
```

`.cached` only makes sense for reference types. Registering a value type with `.cached` behaves like `.transient` because each "cached" boxed copy dies immediately after being handed out.

Unlike `.singleton` and `.scoped`, `.cached` is not compare-and-set: concurrent first-resolves may briefly observe distinct instances before one of them is installed in the weak slot. This matches the weak-cache contract — `.cached` only promises sharing while at least one consumer is keeping the value alive — and the orphan instance is reclaimed as soon as its caller releases it.

## `.scoped`

Bound to the innermost ``Container/withScope(_:perform:)-9rmuy`` block on the current Task:

```swift
container.register(RequestContext.self, scope: .scoped) { _ in RequestContext() }

try await container.withScope {
    let a = container.resolve(RequestContext.self)
    let b = container.resolve(RequestContext.self)
    assert(a === b)                                       // same in this scope
}

// Outside any scope — throws ResolutionError.scopeRequired.
_ = try container.tryResolve(RequestContext.self)
```

Scopes nest. Each `withScope` block gets its own bucket, identified by a ``ScopeID``. Use ``ScopeID/named(_:)`` for deterministic scope identity (useful in tests); the default ``ScopeID/anonymous()`` gives every block a fresh identifier.

## Choosing in practice

- **Always the same instance, app-wide?** `.singleton`.
- **One-off value where sharing would be a bug?** `.transient`.
- **Heavy to build, fine to rebuild when unused?** `.cached`.
- **Lives for the duration of a request, screen, or task?** `.scoped`.
