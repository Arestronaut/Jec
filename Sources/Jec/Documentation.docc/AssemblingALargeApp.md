# Assembling a large app

Group related registrations into ``Assembly`` types and compose them with ``Container/install(_:)``.

## Overview

For anything beyond a handful of services, scatter-shot `register(...)` calls in `App.init` become unmaintainable. ``Assembly`` is a thin protocol around `assemble(in:)` that lets each subsystem own its wiring, and ``Container/install(_:)`` is a result-builder block that composes assemblies declaratively.

```swift
public protocol Assembly: Sendable {
    func assemble(in container: Container)
}
```

There's no hidden state and no separate registry — assemblies are sugar over the same ``Container/register(_:name:scope:factory:)-9bz59`` you'd call directly.

## A module per subsystem

```swift
struct NetworkAssembly: Assembly {
    let baseURL: URL
    func assemble(in container: Container) {
        container.register(URLSession.self, scope: .singleton) { _ in .shared }
        container.register(APIClient.self, scope: .singleton) { r in
            LiveAPIClient(session: r.resolve(), baseURL: baseURL)
        }
    }
}

struct PersistenceAssembly: Assembly {
    func assemble(in container: Container) {
        container.register(Database.self, scope: .singleton) { _ in SQLiteDatabase() }
        container.register(UserStore.self, scope: .singleton) { r in
            DefaultUserStore(db: r.resolve())
        }
    }
}
```

Each assembly is independently testable: instantiate one against a fresh ``Container``, resolve a key from it, assert behaviour.

## Composing at the app entry point

```swift
let container = Container.default
container.install {
    NetworkAssembly(baseURL: URL(string: "https://api.example.com")!)
    PersistenceAssembly()
    AnalyticsAssembly()
    #if DEBUG
    DebugOverridesAssembly()
    #endif
}
```

The block accepts plain assemblies, `if` / `else`, optional bindings, and `for` loops via ``AssemblyBuilder``.

## Nesting

An assembly may install other assemblies inside `assemble`, which is the natural pattern for layered apps:

```swift
struct AppAssembly: Assembly {
    let environment: Environment
    func assemble(in container: Container) {
        container.install {
            NetworkAssembly(baseURL: environment.apiURL)
            PersistenceAssembly()
        }
        container.register(AppCoordinator.self, scope: .singleton) { r in
            AppCoordinator(api: r.resolve(), users: r.resolve())
        }
    }
}
```

## Override semantics

Assemblies and direct `register` calls coexist on the same container. The rule is simple: **last writer wins per `(type, name)` key**. The previous registration's cached singleton (if any) is dropped at the same moment.

```swift
container.install { AppAssembly() }
container.register(APIClient.self) { _ in MockAPIClient() }   // overrides
```

This makes test overrides ergonomic — install the full production graph, then replace whichever keys you need.

## When to skip assemblies

For a tiny app (one screen, three services), inline `register` calls in `App.init` are clearer than splitting into modules. Reach for assemblies once you have two or more cohesive subsystems, want module-level test isolation, or need to vary wiring by build configuration.
