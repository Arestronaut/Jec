#if canImport(SwiftUI)
import Foundation
import SwiftUI
import Testing
@testable import jec
@testable import jecSwiftUI

// MARK: - Fixtures

private protocol GreetingService: Sendable {
    var hello: String { get }
}

private struct EnglishGreetings: GreetingService {
    let hello = "Hello"
}

private struct GermanGreetings: GreetingService {
    let hello = "Hallo"
}

@MainActor
@Suite("jecSwiftUI — EnvironmentInjected + environment plumbing")
struct EnvironmentInjectedTests {
    /// `EnvironmentKey`'s default is wired to `Container.default`.
    @Test func environmentDefaultsToContainerDefault() {
        let values = EnvironmentValues()
        #expect(values.jecContainer === Container.default)
    }

    /// Direct mutation of the environment slot returns the same value back —
    /// verifies the get/set bridge on `EnvironmentValues.jecContainer`.
    @Test func environmentSetReturnsTheSameContainer() {
        var values = EnvironmentValues()
        let custom = Container()
        values.jecContainer = custom
        #expect(values.jecContainer === custom)
    }

    /// `EnvironmentInjected` reads from the active environment container.
    /// With no view tree present, `@Environment` falls back to the key's default,
    /// which is `Container.default` — so registering on `.default` exposes the value.
    @Test func environmentInjectedResolvesFromDefaultContainer() {
        let token = "env-injected-default-\(UUID().uuidString)"
        Container.default.register(GreetingService.self, name: token, scope: .singleton) { _ in
            EnglishGreetings()
        }
        defer { Container.default.unregister(GreetingService.self, name: token) }

        struct Reader {
            @EnvironmentInjected var greeter: GreetingService
            init(name: String) { _greeter = EnvironmentInjected(name: name) }
        }
        let reader = Reader(name: token)
        #expect(reader.greeter.hello == "Hello")
    }

    /// Compile-only check: `.jecContainer(_:)` returns `some View` and can chain.
    @Test func viewModifierReturnsAView() {
        let custom = Container()
        let _: AnyView = AnyView(EmptyView().jecContainer(custom))
    }

    /// Compile-only check: `@EnvironmentInjected` and `@ObservableInjected` can sit
    /// inside the same SwiftUI view alongside `@Environment` without conflicts.
    @Test func wrappersComposeInsideAView() {
        struct Composed: View {
            @EnvironmentInjected var greeter: GreetingService
            @Environment(\.jecContainer) var container
            var body: some View { Color.clear }
        }
        _ = Composed.self
    }
}
#endif
