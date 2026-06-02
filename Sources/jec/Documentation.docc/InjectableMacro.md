# Eliminating factory boilerplate with `@Injectable`

Drop the `register(...)` factory closure for any type whose initializer takes only resolvable dependencies.

## Overview

The default registration form requires a factory closure that wires each sub-dependency:

```swift
container.register(UserService.self, scope: .singleton) { resolver in
    UserService(api: resolver.resolve(), db: resolver.resolve())
}
```

For every type whose init parameters are themselves registered in the container, this closure is mechanical. ``Injectable()`` makes the compiler write it for you:

```swift
@Injectable
final class UserService: Sendable {
    let api: APIClient
    let db: Database
    init(api: APIClient, db: Database) {
        self.api = api
        self.db = db
    }
}

container.register(UserService.self, scope: .singleton)   // factory synthesised
```

## What the macro generates

`@Injectable` is an `@attached(extension)` macro. It expands to:

```swift
extension UserService: jec.Injectable {
    public static func resolve(from resolver: any jec.Resolver) -> UserService {
        UserService(api: resolver.resolve(), db: resolver.resolve())
    }
}
```

A no-factory ``Container/register(_:name:scope:)-injectable`` overload, available whenever `T: Injectable`, calls `T.resolve(from:)` for you.

## Requirements

- The type declares **exactly one** initializer. Multi-init types must conform to ``Injectable`` manually.
- The initializer is neither failable (`init?`) nor throwing (`init() throws`). The macro emits a diagnostic in both cases — conform manually if you need either.
- Every init parameter type is itself registered in the container (or otherwise resolvable as a `Sendable` value).
- The type is `Sendable` (the ``Injectable`` protocol requires it).

## Unlabeled parameters

The macro respects the external label, including `_`:

```swift
@Injectable
struct GreetingService: Sendable {
    let database: Database
    init(_ database: Database) { self.database = database }
}

// Expands to:
extension GreetingService: jec.Injectable {
    public static func resolve(from resolver: any jec.Resolver) -> GreetingService {
        GreetingService(resolver.resolve())
    }
}
```

## When to skip the macro

- The init takes parameters that aren't dependency-injection-shaped (e.g. a `baseURL` literal). Use a hand-written factory and inject only the resolvable parts.
- The type has multiple initializers, and which one to call depends on context.
- You want to swap the implementation based on a runtime flag. The factory closure is the natural place for that branching.

## Manual conformance

For everything the macro can't express, just conform yourself — `Container.register(_:name:scope:)` for `Injectable` doesn't care whether the conformance was synthesised:

```swift
extension UserService: Injectable {
    public static func resolve(from resolver: any Resolver) -> UserService {
        UserService(
            api: resolver.resolve(name: "primary"),
            db: resolver.resolve(),
            featureFlags: .live   // not in the container
        )
    }
}
```
