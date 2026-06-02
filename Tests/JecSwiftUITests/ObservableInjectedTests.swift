#if canImport(SwiftUI)
import Foundation
import Observation
import SwiftUI
import Testing
@testable import Jec
@testable import JecSwiftUI

@Observable @MainActor
final class CounterViewModel: Sendable {
    var count = 0
    func increment() { count += 1 }
}

@MainActor
@Suite("JecSwiftUI — ObservableInjected")
struct ObservableInjectedTests {
    /// `ObservableInjected` resolves on first access to `wrappedValue` and caches the
    /// instance in its reference-typed box for subsequent accesses. We exercise the
    /// box directly rather than via SwiftUI's view tree (which would need a host).
    @Test func resolvesOnceAndReusesViaBox() {
        let token = "observable-injected-\(UUID().uuidString)"
        Container.default.register(CounterViewModel.self, name: token, scope: .transient) { _ in
            MainActor.assumeIsolated { CounterViewModel() }
        }
        defer { Container.default.unregister(CounterViewModel.self, name: token) }

        let wrapper = ObservableInjected<CounterViewModel>(name: token)
        let a = wrapper.wrappedValue
        let b = wrapper.wrappedValue
        // Box is a stored property of the struct, so two accesses on the same wrapper
        // instance hit the cached value rather than re-resolving from the container.
        #expect(a === b)
    }

    /// Compile-only: the wrapper composes inside a view and is `DynamicProperty`.
    @Test func wrappersComposeInsideAView() {
        struct Probe: View {
            @ObservableInjected var vm: CounterViewModel
            var body: some View { Text("\(vm.count)") }
        }
        _ = Probe.self
    }
}
#endif
