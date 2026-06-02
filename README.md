# Jec

A modern Swift 6.2 dependency injection container. Strict-concurrency clean, macro-powered, and small enough to read in one sitting.

```swift
import Jec

// 1. Register
Container.default.register(APIClient.self, scope: .singleton) { _ in
    LiveAPIClient()
}

// 2. Resolve
let api = Container.default.resolve(APIClient.self)

// 3. Inject
struct ViewModel: Sendable {
    @Injected var api: APIClient
}
```

## Why

- **Swift 6.2-native.** `Sendable` end-to-end, `Synchronization.Mutex` for the registry, `@TaskLocal` for scopes and per-task overrides. No `nonisolated(unsafe)`, no warnings under `-strict-concurrency=complete`.
- **Both sync and async resolution.** Sync `resolve` for `Sendable` types, `resolveAsync` for `@MainActor` / async-initialised dependencies.
- **Property wrapper *and* macro.** `@Injected` for ergonomics, `@Inject` accessor macro for actor- and `@MainActor`-isolated consumers.
- **TaskLocal-scoped containers.** Swap the container per-Task for tests or previews with `Container.$current.withValue`.
- **Assembly DSL** for organising large apps into composable modules.

## Install

Swift Package Manager — `Package.swift`:

```swift
.package(url: "https://github.com/Arestronaut/Jec", from: "0.1.0"),
```

Platforms: macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2. Swift 6.2 toolchain required.

## Scopes

| Scope | Behaviour | Constraint |
|---|---|---|
| `.transient` (default) | Fresh instance on every `resolve`. | — |
| `.singleton` | One instance per container, retained for its lifetime. Single-flighted: concurrent first-resolves converge on one stored instance even if the factory runs more than once. | `T: Sendable` |
| `.cached` | Weakly cached — reused while at least one consumer holds it. Under concurrent first-resolves two callers may briefly observe distinct instances. | `T` must be a reference type at runtime. |
| `.scoped` | Bound to the innermost `withScope { … }` block on the current Task. Single-flighted within a scope. | Resolving outside any scope throws. |

Factory closures should be idempotent and side-effect-free. The container guarantees a single *value* per cached key under contention, but the factory itself may run more than once if multiple Tasks race a cache miss.

```swift
container.register(URLSession.self, scope: .singleton) { _ in .shared }
container.register(RequestID.self, scope: .scoped) { _ in RequestID.fresh() }

try await container.withScope {
    let a = container.resolve(RequestID.self)
    let b = container.resolve(RequestID.self)
    assert(a == b)        // same instance inside the scope
}
```

## Resolving

| API | When |
|---|---|
| `container.resolve(T.self)` | Sync resolve, traps if missing or registration is async-only. |
| `container.tryResolve(T.self)` | Sync resolve, throws on failure. |
| `container.tryResolveOptional(T.self)` | Sync resolve. Returns `nil` for `.unregistered` / `.asyncRequired` / `.scopeRequired` — the "key not satisfiable here" cases. Traps on `.cycle` and `.typeMismatch` (programming bugs that silent-`nil` would hide). |
| `container.resolveAsync(T.self)` | Async resolve — works for both sync and async registrations. |

## Property wrappers

```swift
struct Consumer: Sendable {
    @Injected var api: APIClient                 // re-resolves on every access
    @LazyInjected var db: Database               // resolves once, caches forever
    @WeakInjected var logger: ConsoleLogger?     // weak-held; `nil` if missing or freed
}
```

All three are `Sendable` and resolve against `Container.current` — the current Task's container. `@WeakInjected` uses `tryResolveOptional` under the hood: a missing registration returns `nil` rather than trapping, so it composes cleanly with optional-handling call sites.

## `@Inject` macro

Use `@Inject` on properties inside `@MainActor` types and actors — it expands inline to a computed accessor that inherits the enclosing isolation, sidestepping the SE-0401 property-wrapper isolation papercut.

```swift
@MainActor
final class HomeViewModel: Sendable {
    @Inject var api: APIClient
    @Inject(name: "primary") var primaryDB: Database
}
```

Pass `name:` to disambiguate when the same type is registered multiple times.

## `@Injectable` — register without a factory

For types whose initializer takes only resolvable dependencies, drop the factory closure entirely:

```swift
@Injectable
final class UserService: Sendable {
    let api: APIClient
    let db: Database
    init(api: APIClient, db: Database) { self.api = api; self.db = db }
}

container.register(UserService.self, scope: .singleton)   // no closure
```

The macro synthesises a `static func resolve(from:)` that calls the init with `resolver.resolve()` for each parameter. Requires the type to:
- have exactly one initializer,
- not be failable (`init?`),
- not be throwing (`init() throws`),
- conform to `Sendable`.

For more complex cases — multiple inits, failable inits, throwing inits — conform to `Injectable` manually and write `resolve(from:)` yourself.

For protocol-keyed registrations:

```swift
container.register(APIClient.self, implementedBy: LiveAPIClient.self, scope: .singleton)
```

## `@Module` + `@Provides`

Dagger/Hilt-style declarative assemblies. The `@Module` macro synthesises `assemble(in:)` from sibling methods marked `@Provides`:

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

container.install { NetworkAssembly(baseURL: URL(string: "https://api")!) }
```

Each `@Provides` method becomes a `register(...)` call: the return type is the key, parameters become resolved sub-dependencies. Pass `name:` to register under a name. Methods may be `async` (uses `asyncFactory:`) but must not throw.

## Assembly DSL

Group registrations into reusable, composable modules:

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
    }
}

Container.default.install {
    NetworkAssembly(baseURL: URL(string: "https://api.example.com")!)
    PersistenceAssembly()
    #if DEBUG
    DebugOverridesAssembly()
    #endif
}

// or, fluent form:
let container = Container().installing {
    NetworkAssembly(baseURL: apiURL)
    PersistenceAssembly()
}
```

The `install` block accepts plain assemblies, `if`/`else`, optional bindings, and `for` loops. Later registrations override earlier ones — convenient for layering test or environment overrides on top of production wiring.

## SwiftUI

Add the `JecSwiftUI` library product alongside `Jec` and you get an `@Environment` slot plus two SwiftUI-aware property wrappers.

```swift
import SwiftUI
import Jec
import JecSwiftUI

@main struct MyApp: App {
    let container: Container = {
        let c = Container.default
        c.install { AppAssembly() }
        return c
    }()
    var body: some Scene {
        WindowGroup { RootView().jecContainer(container) }
    }
}

struct UserBadge: View {
    @EnvironmentInjected var api: APIClient   // resolves from @Environment(\.jecContainer)
    var body: some View { /* … */ }
}

@Observable @MainActor
final class HomeViewModel: Sendable {
    var count = 0
    func increment() { count += 1 }
}

struct HomeView: View {
    @ObservableInjected var vm: HomeViewModel  // resolved once, persisted across renders
    var body: some View {
        Button("Count: \(vm.count)") { vm.increment() }
    }
}
```

Use `@EnvironmentInjected` for stateless services inside SwiftUI views (it always reads from `@Environment(\.jecContainer)`). Use `@ObservableInjected` for `@Observable` view models — it caches the resolved instance via `@State` so it survives view re-renders, while letting SwiftUI's Observation framework track property reads on it.

The plain `@Injected` / `@Inject` still work in non-SwiftUI code paths (services, test helpers); they read from the `Container.current` TaskLocal.

## Testing

Swap the container per-Task without touching globals:

```swift
@Test func loginSucceeds() async {
    let test = Container()
    test.install { AppAssembly() }
    test.register(APIClient.self) { _ in MockAPIClient() }   // override one key

    await Container.$current.withValue(test) {
        let vm = LoginViewModel()                            // uses @Injected
        await vm.signIn(user: "alice")
        #expect(vm.didSucceed)
    }
}
```

Anything resolved inside the block — including from child Tasks — sees the test container.

## Error handling

`ResolutionError` distinguishes the failure modes you'd want to handle separately:

- `.unregistered(type:name:chain:)` — nothing matches the key. Includes the chain of ancestor types whose factories were on the stack at the moment of failure.
- `.asyncRequired(type:name:chain:)` — sync resolve attempted on an async-only registration.
- `.scopeRequired(type:name:chain:)` — `.scoped` registration resolved outside any `withScope` block.
- `.cycle(chain:)` — registering A whose factory resolves B whose factory resolves A. The chain shows the cycle path.
- `.typeMismatch(expected:actual:)` — stored value's type does not match the resolve site.

The `chain` makes deep-tree wiring problems trivial to diagnose:

> No registration for `Database`. Resolved via: `AppCoordinator` → `UserService` → `Database`

```swift
do {
    let api = try container.tryResolve(APIClient.self)
} catch ResolutionError.unregistered(let type, _) {
    // log + recover
}
```

## Debugging the graph

`container.dump()` returns a human-readable listing of every registration. Print it from a breakpoint or REPL:

```
Container — 3 registration(s):
  - APIClient — singleton
  - APIClient [primary] — singleton
  - Database — cached (async)
```

## Observing resolves

Attach a callback to every successful resolve — useful for telemetry, signposts, and debugging:

```swift
let token = container.onResolve { event in
    print("\(event.typeName) ← \(event.source)")   // .factory, .cacheSingleton, .cacheScoped, .cacheWeak
}
// later:
container.removeObserver(token)
```

Observers fire inside the resolving call, so keep them cheap. They are dropped by `container.reset()`.

## License

TBD.
