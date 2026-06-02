#if canImport(SwiftUI)
import SwiftUI
import Jec

private struct JecContainerKey: EnvironmentKey {
    static let defaultValue: Container = .default
}

public extension EnvironmentValues {
    /// The `Jec` ``Container`` exposed to the SwiftUI environment. Defaults to ``Container/default``.
    ///
    /// Override at any point in the view hierarchy with ``SwiftUICore/View/jecContainer(_:)``.
    var jecContainer: Container {
        get { self[JecContainerKey.self] }
        set { self[JecContainerKey.self] = newValue }
    }
}

public extension View {
    /// Install a `Jec` ``Container`` into this view's environment.
    ///
    /// Use at the root of a SwiftUI hierarchy to scope all ``EnvironmentInjected`` and
    /// ``ObservableInjected`` resolution in descendants to a specific container:
    ///
    /// ```swift
    /// @main struct MyApp: App {
    ///     let container: Container = {
    ///         let c = Container.default
    ///         c.install { AppAssembly() }
    ///         return c
    ///     }()
    ///     var body: some Scene {
    ///         WindowGroup { RootView().jecContainer(container) }
    ///     }
    /// }
    /// ```
    ///
    /// In previews and tests, point this at a container with mock registrations.
    func jecContainer(_ container: Container) -> some View {
        environment(\.jecContainer, container)
    }
}
#endif
