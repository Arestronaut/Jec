# SwiftUI integration

Use ``jecSwiftUI`` to wire a ``Container`` into the SwiftUI environment and resolve dependencies from inside views.

## Overview

The `jecSwiftUI` library (separate from the core `jec` library so non-SwiftUI consumers don't pull in SwiftUI) adds three pieces:

- An `@Environment(\.jecContainer)` slot whose default is ``Container/default``.
- A `.jecContainer(_:)` view modifier that overrides the slot for a subtree.
- Two SwiftUI-aware property wrappers — `@EnvironmentInjected` for stateless services and `@ObservableInjected` for `@Observable` view models.

The plain ``Injected`` / ``Inject(name:)`` accessors keep working in non-SwiftUI code (services, view models, tests); they read from the ``Container/current`` TaskLocal. The SwiftUI wrappers read from the environment — the natural source of truth inside a view tree.

## Wiring at the app root

```swift
import SwiftUI
import jec
import jecSwiftUI

@main struct MyApp: App {
    let container: Container = {
        let c = Container.default
        c.install { AppAssembly() }
        return c
    }()

    var body: some Scene {
        WindowGroup {
            RootView().jecContainer(container)
        }
    }
}
```

`.jecContainer(_:)` only affects descendants. Multiple subtrees can carry different containers (useful for previews or sandboxed sub-flows).

## `@EnvironmentInjected`

Resolve a stateless service inside a view:

```swift
struct UserBadge: View {
    @EnvironmentInjected var api: APIClient
    let userID: String
    var body: some View {
        AsyncImage(url: api.avatarURL(for: userID))
    }
}
```

Pass `name:` for named registrations. The wrapper requires `T: Sendable`.

## `@ObservableInjected`

For `@Observable` view models that the view should own across re-renders:

```swift
@Observable @MainActor
final class HomeViewModel: Sendable {
    var count = 0
    func increment() { count += 1 }
}

container.register(HomeViewModel.self) { _ in
    MainActor.assumeIsolated { HomeViewModel() }
}

struct HomeView: View {
    @ObservableInjected var vm: HomeViewModel
    var body: some View {
        Button("Count: \(vm.count)") { vm.increment() }
    }
}
```

The wrapper:

- Resolves from the SwiftUI environment's container on first access.
- Caches the resolved instance in a reference-typed box held via `@State`, so subsequent renders reuse the same instance.
- Lets SwiftUI's Observation framework track property reads on the resolved value — no special tracking ceremony required.

`@ObservableInjected` constrains `T: AnyObject & Sendable`. Most `@Observable` view models satisfy this either via explicit Sendable or via `@MainActor` (which is Sendable in Swift 6).

## Previews

Pair `.jecContainer(_:)` with a preview-specific container to render screens against canned data:

```swift
#Preview {
    let preview = Container()
    preview.register(APIClient.self, scope: .singleton) { _ in PreviewAPIClient() }
    return HomeView().jecContainer(preview)
}
```

## Tests with a SwiftUI surface

For unit tests that drive view models without rendering, the TaskLocal pattern from <doc:TestingWithOverrides> remains the right tool — view models constructed inside `Container.$current.withValue` get the test container. For tests that need an actual view tree, use UI testing or a library like ViewInspector to drive the body and read state.
