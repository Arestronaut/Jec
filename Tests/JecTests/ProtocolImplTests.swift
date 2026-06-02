import Foundation
import Testing
@testable import Jec

private protocol Greeter: Sendable {
    var greeting: String { get }
}

@Injectable
private struct LiveGreeter: Greeter {
    let greeting: String
    init() { self.greeting = "hello from impl" }
}

@Suite("Container.register(_:implementedBy:) — protocol → impl convenience")
struct ProtocolImplTests {
    @Test func registersImplUnderProtocolType() async {
        await withFreshContainer { container in
            container.register(Greeter.self, implementedBy: LiveGreeter.self, scope: .singleton)
            let resolved: Greeter = container.resolve(Greeter.self)
            #expect(resolved.greeting == "hello from impl")
        }
    }

    @Test func protocolKeyDistinctFromConcreteKey() async {
        await withFreshContainer { container in
            container.register(Greeter.self, implementedBy: LiveGreeter.self, scope: .singleton)
            // The concrete type is NOT also registered.
            let asProtocol: Greeter? = container.tryResolveOptional(Greeter.self)
            let asConcrete: LiveGreeter? = container.tryResolveOptional(LiveGreeter.self)
            #expect(asProtocol != nil)
            #expect(asConcrete == nil)
        }
    }
}
