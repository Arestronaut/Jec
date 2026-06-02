import Foundation
import Testing
@testable import Jec

@Suite("Macros — @Inject runtime smoke")
struct MacroRuntimeTests {
    struct ViewModel: Sendable {
        @Inject var api: APIClient
    }

    @Test func macroExpandedAccessorResolvesViaContainer() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient(endpoint: "https://macro") }
            let vm = ViewModel()
            #expect(vm.api.endpoint == "https://macro")
        }
    }
}
