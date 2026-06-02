# Testing with overrides

Swap the active container per-Task with `Container.$current.withValue` — no globals to reset, no test pollution.

## Overview

``Container/current`` is a `@TaskLocal`. Inside `Container.$current.withValue(testContainer) { … }`, every ``Injected`` access, every ``Inject(name:)`` expansion, and any code reading `Container.current` directly will resolve from `testContainer`. The override scopes to the current Task and propagates automatically to child Tasks, so `withTaskGroup` and `Task { }` children inherit it.

## The basic pattern

```swift
@Test func loginCallsAPI() async {
    let test = Container()
    test.register(APIClient.self) { _ in MockAPIClient() }

    await Container.$current.withValue(test) {
        let vm = LoginViewModel()                 // @Injected resolves from `test`
        await vm.signIn(user: "alice")
        #expect(MockAPIClient.lastUser == "alice")
    }
}
```

The override leaves ``Container/default`` untouched — other tests running in parallel see their own override or the default.

## Layering test overrides on production wiring

Install your production ``Assembly`` first, then `register` to overwrite individual keys:

```swift
let test = Container()
test.install { AppAssembly() }                   // full production graph
test.register(APIClient.self) { _ in MockAPIClient() }
test.register(Clock.self) { _ in TestClock() }
```

Last writer wins — the explicit `register` after `install` replaces the assembly's registration.

## A reusable fixture

A small helper keeps every test self-contained:

```swift
@discardableResult
func withFreshContainer<R: Sendable>(
    _ body: (Container) async throws -> R
) async rethrows -> R {
    let container = Container()
    return try await Container.$current.withValue(container) {
        try await body(container)
    }
}

// In a test:
await withFreshContainer { container in
    container.install { AppAssembly() }
    container.register(APIClient.self) { _ in MockAPIClient() }
    // …
}
```

## Per-Task overrides for parallel tests

Swift Testing runs `@Test` cases in parallel by default. Because the override is `@TaskLocal`, parallel tests cannot pollute each other — each test's body runs inside its own Task with its own bound container.

## Verifying scoped behaviour

When testing `.scoped` dependencies, run inside `withScope` and use ``ScopeID/named(_:)`` so the same logical scope is reproducible across tests:

```swift
try await container.withScope(.named("request-42")) {
    let a = container.resolve(RequestContext.self)
    let b = container.resolve(RequestContext.self)
    #expect(a === b)
}
```
