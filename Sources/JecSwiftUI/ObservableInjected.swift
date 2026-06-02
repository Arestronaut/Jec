#if canImport(SwiftUI)
import Observation
import SwiftUI
import Jec

/// Resolves an `@Observable` view model from the SwiftUI environment's container and
/// preserves the same instance across view re-renders.
///
/// Use for view-owned, observable state — typically `@Observable` view models — where
/// you want the container to construct the instance but SwiftUI to manage its lifetime
/// within the view tree.
///
/// ```swift
/// @Observable @MainActor
/// final class HomeViewModel: Sendable {
///     var count = 0
///     func increment() { count += 1 }
/// }
///
/// container.register(HomeViewModel.self) { _ in HomeViewModel() }
///
/// struct HomeView: View {
///     @ObservableInjected var vm: HomeViewModel
///     var body: some View {
///         VStack {
///             Text("\(vm.count)")
///             Button("Inc") { vm.increment() }
///         }
///     }
/// }
/// ```
///
/// Internally the wrapper uses `@State` to hold a reference box that survives
/// re-renders, so the dependency is resolved exactly once per view instance.
/// SwiftUI's `Observation` machinery tracks reads of the resolved value's properties
/// automatically.
@propertyWrapper
public struct ObservableInjected<T: AnyObject & Sendable>: DynamicProperty {
    @Environment(\.jecContainer) private var container
    @State private var box = ObservableInjectedBox<T>()
    private let typeBox: TypeBox<T>
    private let name: String?

    public init(_ type: T.Type = T.self, name: String? = nil) {
        self.typeBox = TypeBox(type)
        self.name = name
    }

    public var wrappedValue: T {
        if let existing = box.value { return existing }
        let resolved: T = container.resolve(typeBox.type, name: name)
        box.value = resolved
        return resolved
    }
}

/// Reference-typed holder so `@State` can preserve the resolved instance across renders.
/// Mutating `value` from inside a body is safe because the box itself is the `@State`
/// value (its identity doesn't change), not `value`.
final class ObservableInjectedBox<T: AnyObject>: @unchecked Sendable {
    var value: T?
    init() {}
}
#endif
