# Diagnostics: resolution chains and cycles

Every ``ResolutionError`` carries the chain of ancestor types whose factories were
running when the failure surfaced, and ``ResolutionError/cycle(chain:)`` detects
circular dependencies before they become infinite recursion.

## Overview

`Jec` maintains a per-Task resolution stack via `@TaskLocal`. Each call to
``Container/resolve(_:name:)``, ``Container/tryResolve(_:name:)``, or
``Container/resolveAsync(_:name:)`` pushes the key being built onto the stack
for the duration of its factory, then pops it.

Two things fall out of this:

- **Error messages name the chain.** When a deep dependency is missing, the error
  tells you not just what was missing but who tried to resolve it.
- **Cycle detection.** If a factory tries to resolve a key already on the stack,
  the container throws ``ResolutionError/cycle(chain:)`` with the full path.

## Chain in error messages

```
No registration for Database. Resolved via: AppCoordinator → UserService → Database
```

The chain is also available programmatically:

```swift
do {
    _ = try container.tryResolve(AppCoordinator.self)
} catch let ResolutionError.unregistered(type, _, chain) {
    log.error("missing \(type); path: \(chain.joined(separator: " → "))")
}
```

`asyncRequired` and `scopeRequired` carry chains too.

## Cycles

```swift
container.register(NodeA.self) { r in NodeA(b: r.resolve()) }
container.register(NodeB.self) { r in NodeB(a: r.resolve()) }
```

This wiring is a cycle: building `NodeA` needs `NodeB`, which needs `NodeA`. The
container detects it before recursing forever and throws:

```
Circular dependency detected: NodeA → NodeB → NodeA
```

Because ``Container/resolve(_:name:)`` is non-throwing and traps on errors, a
cycle inside a factory becomes a fast `preconditionFailure` with the chain in the
message — which is what you want during development: fail loud, fail with context.

To recover programmatically (e.g. in framework code wrapping the container),
use ``Container/tryResolve(_:name:)`` at every level so the cycle propagates as a
catchable error.
