# ``Jec``

A modern Swift 6.2 dependency injection container — concurrency-safe, macro-powered, and small enough to read in one sitting.

## Overview

`Jec` registers dependencies on a ``Container`` with explicit lifetime ``Scope``s, then resolves them on demand. Three resolution surfaces — direct calls, the ``Injected`` family of property wrappers, and the ``Inject(name:)`` accessor macro — cover every isolation context.

```swift
import Jec

Container.default.register(APIClient.self, scope: .singleton) { _ in
    LiveAPIClient()
}

struct ViewModel: Sendable {
    @Injected var api: APIClient
}
```

The container is `Sendable`, its registry lives behind a `Synchronization.Mutex`, and a ``Container/current`` `@TaskLocal` lets tests and previews override the active container without touching globals.

## Topics

### Essentials

- ``Container``
- ``Scope``
- ``Resolver``

### Resolving

- ``Injected``
- ``LazyInjected``
- ``WeakInjected``
- ``Inject(name:)``

### Eliminating factory boilerplate

- ``Injectable``
- ``Injectable()``

### Organising registrations

- ``Assembly``
- ``AssemblyBuilder``
- ``Module()``
- ``Provides(_:name:)``

### Scoped lifetime

- ``ScopeID``

### Errors

- ``ResolutionError``

### Articles

- <doc:ChoosingAScope>
- <doc:InjectableMacro>
- <doc:ModuleMacro>
- <doc:SwiftUIIntegration>
- <doc:TestingWithOverrides>
- <doc:AssemblingALargeApp>
- <doc:Diagnostics>
