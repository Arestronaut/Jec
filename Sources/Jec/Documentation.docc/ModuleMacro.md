# Declarative modules with `@Module` and `@Provides`

Express an ``Assembly`` as a struct of provider methods. The ``Module()`` macro
synthesises `assemble(in:)` by enumerating every method marked ``Provides(_:name:)``.

## Overview

The Assembly protocol's `assemble(in:)` body is mechanical when every registration
follows the same shape:

```swift
container.register(URLSession.self, scope: .singleton) { _ in .shared }
container.register(APIClient.self, scope: .singleton) { r in
    LiveAPIClient(session: r.resolve(), baseURL: baseURL)
}
```

`@Module` rewrites the same intent as a struct of methods, with `@Provides` marking
which methods become registrations:

```swift
@Module struct NetworkAssembly {
    let baseURL: URL

    @Provides(.singleton)
    func session() -> URLSession { .shared }

    @Provides(.singleton)
    func api(_ session: URLSession) -> APIClient {
        LiveAPIClient(session: session, baseURL: baseURL)
    }
}
```

The macro expands to an extension that conforms `NetworkAssembly` to ``Assembly``
and synthesises `assemble(in:)`:

```swift
extension NetworkAssembly: Jec.Assembly {
    public func assemble(in container: Jec.Container) {
        container.register(URLSession.self, scope: .singleton) { resolver in
            self.session()
        }
        container.register(APIClient.self, scope: .singleton) { resolver in
            self.api(resolver.resolve())
        }
    }
}
```

Each parameter on a `@Provides` method becomes a `resolver.resolve()` call — the
container builds the dependency graph automatically.

## Usage

`@Module` types compose with the regular ``Container/install(_:)`` builder:

```swift
container.install {
    NetworkAssembly(baseURL: URL(string: "https://api")!)
    PersistenceAssembly()
    AnalyticsAssembly()
}
```

`@Provides` accepts the same arguments as ``Container/register(_:name:scope:factory:)-9bz59``:

```swift
@Provides(.singleton, name: "primary")
func primaryAPI() -> APIClient { LiveAPIClient(endpoint: "https://primary") }
```

## async providers

`@Provides` methods may be `async`. The macro emits an `asyncFactory:` registration:

```swift
@Module struct WarmupAssembly {
    @Provides(.singleton)
    func cache() async -> WarmCache {
        await WarmCache.preload()
    }
}
```

Resolve with `try await container.resolveAsync(WarmCache.self)`.

## Constraints

- The annotated type must be `Sendable` (required by ``Assembly``).
- `@Provides` methods must not throw — factory closures cannot propagate errors.
- Parameter and return types of `@Provides` methods must be `Sendable`.

## When to prefer `@Module` over a hand-written Assembly

- Use `@Module` when the module is mostly provider methods with simple dependencies.
- Stick with a hand-written `Assembly` when wiring logic needs branching, nested
  `install` calls, or registrations that vary by runtime configuration.

Both styles compose freely — a `@Module` type and a hand-written `Assembly` can sit
side by side in the same `install` block.
