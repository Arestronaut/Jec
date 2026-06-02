import Foundation
import Testing
@testable import Jec

@Suite("Container.dump()")
struct DumpTests {
    @Test func emptyContainerReportsEmpty() async {
        await withFreshContainer { container in
            #expect(container.dump() == "Container is empty.")
        }
    }

    @Test func dumpListsRegistrationsWithScopeAndName() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient() }
            container.register(APIClient.self, name: "primary", scope: .transient) { _ in LiveAPIClient() }
            container.register(InMemoryLogger.self, scope: .cached) { _ in InMemoryLogger() }
            container.register(String.self, asyncFactory: { _ in await Task.yield(); return "" })

            let dump = container.dump()
            #expect(dump.contains("4 registration(s)"))
            #expect(dump.contains("APIClient"))
            #expect(dump.contains("[primary]"))
            #expect(dump.contains("singleton"))
            #expect(dump.contains("transient"))
            #expect(dump.contains("cached"))
            #expect(dump.contains("(async)"))
        }
    }
}
