import Foundation
import Testing
@testable import jec

// MARK: - Fixture assemblies used across the suite

private struct NetworkAssembly: Assembly {
    let endpoint: String
    func assemble(in container: Container) {
        container.register(APIClient.self, scope: .singleton) { _ in
            LiveAPIClient(endpoint: endpoint)
        }
    }
}

private struct LoggerAssembly: Assembly {
    func assemble(in container: Container) {
        container.register(InMemoryLogger.self, scope: .singleton) { _ in InMemoryLogger() }
    }
}

private struct CountingAssembly: Assembly {
    let counter: Counter
    func assemble(in container: Container) {
        container.register(APIClient.self, scope: .singleton) { _ in
            counter.increment()
            return CountingAPIClient()
        }
    }
}

private struct NamedAssembly: Assembly {
    let name: String
    let endpoint: String
    func assemble(in container: Container) {
        container.register(APIClient.self, name: name, scope: .singleton) { _ in
            LiveAPIClient(endpoint: endpoint)
        }
    }
}

@Suite("Assembly DSL")
struct AssemblyTests {
    @Test func singleAssemblyInstallsAndResolves() async {
        await withFreshContainer { container in
            container.install {
                NetworkAssembly(endpoint: "https://one")
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://one")
        }
    }

    @Test func multipleAssembliesInOneInstallBlock() async {
        await withFreshContainer { container in
            container.install {
                NetworkAssembly(endpoint: "https://multi")
                LoggerAssembly()
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://multi")
            #expect(container.resolve(InMemoryLogger.self) !== nil as InMemoryLogger?)
        }
    }

    @Test func declaredOrderIsInstallOrderAndLastWriterWins() async {
        await withFreshContainer { container in
            container.install {
                NetworkAssembly(endpoint: "https://first")
                NetworkAssembly(endpoint: "https://second")
            }
            // Second registration wins — confirms assemblies run in declared order
            // and the standard "last writer wins" behaviour from Container.register applies.
            #expect(container.resolve(APIClient.self).endpoint == "https://second")
        }
    }

    @Test func ifElseBranchesViaBuilder() async {
        await withFreshContainer { container in
            let useStaging = true
            container.install {
                if useStaging {
                    NetworkAssembly(endpoint: "https://staging")
                } else {
                    NetworkAssembly(endpoint: "https://prod")
                }
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://staging")
        }

        await withFreshContainer { container in
            let useStaging = false
            container.install {
                if useStaging {
                    NetworkAssembly(endpoint: "https://staging")
                } else {
                    NetworkAssembly(endpoint: "https://prod")
                }
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://prod")
        }
    }

    @Test func forLoopViaBuilder() async {
        await withFreshContainer { container in
            let regions = ["us", "eu", "ap"]
            container.install {
                for region in regions {
                    NamedAssembly(name: region, endpoint: "https://\(region).example.com")
                }
            }
            for region in regions {
                let resolved = container.resolve(APIClient.self, name: region)
                #expect(resolved.endpoint == "https://\(region).example.com")
            }
        }
    }

    @Test func optionalBranchViaBuilder() async {
        await withFreshContainer { container in
            let extra: NetworkAssembly? = NetworkAssembly(endpoint: "https://extra")
            container.install {
                LoggerAssembly()
                if let extra {
                    extra
                }
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://extra")
            #expect(container.resolve(InMemoryLogger.self) !== nil as InMemoryLogger?)
        }

        await withFreshContainer { container in
            let extra: NetworkAssembly? = nil
            container.install {
                LoggerAssembly()
                if let extra {
                    extra
                }
            }
            #expect(throws: ResolutionError.self) {
                _ = try container.tryResolve(APIClient.self)
            }
        }
    }

    @Test func nestedInstallInsideAnAssembly() async {
        struct OuterAssembly: Assembly {
            func assemble(in container: Container) {
                container.install {
                    NetworkAssembly(endpoint: "https://nested")
                    LoggerAssembly()
                }
                container.register(String.self, scope: .singleton) { _ in "outer" }
            }
        }
        await withFreshContainer { container in
            container.install { OuterAssembly() }
            #expect(container.resolve(APIClient.self).endpoint == "https://nested")
            #expect(container.resolve(InMemoryLogger.self) !== nil as InMemoryLogger?)
            #expect(container.resolve(String.self) == "outer")
        }
    }

    @Test func directRegisterAfterInstallOverrides() async {
        await withFreshContainer { container in
            container.install {
                NetworkAssembly(endpoint: "https://assembly")
            }
            container.register(APIClient.self, scope: .singleton) { _ in
                LiveAPIClient(endpoint: "https://override")
            }
            #expect(container.resolve(APIClient.self).endpoint == "https://override")
        }
    }

    @Test func mixOfDirectRegisterAndInstall() async {
        await withFreshContainer { container in
            container.register(String.self, scope: .singleton) { _ in "before" }
            container.install {
                NetworkAssembly(endpoint: "https://middle")
                LoggerAssembly()
            }
            container.register(Int.self, scope: .singleton) { _ in 42 }

            #expect(container.resolve(String.self) == "before")
            #expect(container.resolve(APIClient.self).endpoint == "https://middle")
            #expect(container.resolve(InMemoryLogger.self) !== nil as InMemoryLogger?)
            #expect(container.resolve(Int.self) == 42)
        }
    }

    @Test func countingAssemblyDoesNotDoubleRegister() async {
        let counter = Counter()
        await withFreshContainer { container in
            container.install {
                CountingAssembly(counter: counter)
            }
            _ = container.resolve(APIClient.self)
            _ = container.resolve(APIClient.self)
            // singleton: factory runs once even though assembly was installed once.
            #expect(counter.value == 1)
        }
    }
}
