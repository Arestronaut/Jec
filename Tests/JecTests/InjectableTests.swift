import Foundation
import Testing
@testable import Jec

// MARK: - Fixtures used by the runtime tests

@Injectable
final class UserService: Sendable {
    let api: APIClient
    let db: Database
    init(api: APIClient, db: Database) {
        self.api = api
        self.db = db
    }
}

protocol Database: Sendable {
    var name: String { get }
}

struct InMemoryDatabase: Database {
    let name: String
    init(name: String = "memory") { self.name = name }
}

@Injectable
struct GreetingService: Sendable {
    let database: Database
    init(_ database: Database) {   // unlabeled — tests the `_` codepath
        self.database = database
    }
}

@Suite("@Injectable — runtime registration")
struct InjectableRuntimeTests {
    @Test func registerWithoutFactoryClosure() async {
        await withFreshContainer { container in
            container.register(APIClient.self, scope: .singleton) { _ in LiveAPIClient(endpoint: "https://injectable") }
            container.register(Database.self, scope: .singleton) { _ in InMemoryDatabase(name: "main") }
            container.register(UserService.self, scope: .singleton)

            let service = container.resolve(UserService.self)
            #expect(service.api.endpoint == "https://injectable")
            #expect(service.db.name == "main")
        }
    }

    @Test func unlabeledInitResolvesCorrectly() async {
        await withFreshContainer { container in
            container.register(Database.self) { _ in InMemoryDatabase(name: "greet") }
            container.register(GreetingService.self)

            #expect(container.resolve(GreetingService.self).database.name == "greet")
        }
    }

    @Test func injectableConformanceIsSynthesised() {
        // Compile-time check: synthesised by the macro.
        let _: any Injectable.Type = UserService.self
        let _: any Injectable.Type = GreetingService.self
    }
}
