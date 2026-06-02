import Foundation
import Testing
@testable import Jec

@Suite("Diagnostics — resolution chain + cycle detection")
struct DiagnosticsTests {
    // MARK: - Fixtures

    private struct DeepLeaf: Sendable { let label: String }
    private struct MiddleNode: Sendable { let leaf: DeepLeaf; init(leaf: DeepLeaf) { self.leaf = leaf } }
    private struct TopNode: Sendable { let middle: MiddleNode; init(middle: MiddleNode) { self.middle = middle } }
    private struct ChainKeeper: Sendable { let chain: [String] }

    // MARK: - Resolution chain

    /// When `tryResolve` fails for a missing key, the error carries the chain of
    /// ancestor types whose factories were on the stack at the moment of failure.
    /// We inject the stack directly to keep the test independent of factory-trap behaviour.
    @Test func unregisteredErrorCarriesAncestorChain() {
        let container = Container()
        let stack: [RegistrationKey] = [
            RegistrationKey(TopNode.self, name: nil),
            RegistrationKey(MiddleNode.self, name: nil),
        ]
        Container.$resolutionStack.withValue(stack) {
            do {
                _ = try container.tryResolve(DeepLeaf.self)
                #expect(Bool(false), "expected throw")
            } catch let ResolutionError.unregistered(_, _, chain) {
                #expect(chain.count == 2)
                #expect(chain.first?.contains("TopNode") == true)
                #expect(chain.last?.contains("MiddleNode") == true)
            } catch {
                #expect(Bool(false), "wrong error: \(error)")
            }
        }
    }

    /// Inside a factory, `Container.resolutionStack` includes the path including
    /// the key being built. Across separate top-level resolves the stack does not
    /// accumulate.
    @Test func chainDoesNotAccumulateAcrossTopLevelResolves() async {
        await withFreshContainer { container in
            container.register(ChainKeeper.self) { _ in
                ChainKeeper(chain: Container.resolutionStack.map(\.typeName))
            }
            let first = container.resolve(ChainKeeper.self)
            let second = container.resolve(ChainKeeper.self)
            #expect(first.chain == second.chain)
            #expect(first.chain.count == 1)   // just ChainKeeper itself, no leak
        }
    }

    /// Error description renders the chain in human-readable form.
    @Test func errorDescriptionRendersChain() {
        let err = ResolutionError.unregistered(
            type: "Foo",
            name: nil,
            chain: ["AppCoordinator", "UserService"]
        )
        let desc = String(describing: err)
        #expect(desc.contains("Foo"))
        #expect(desc.contains("AppCoordinator → UserService"))
    }

    // MARK: - Cycle detection

    /// Cycle detection fires when the key being resolved is already in the active
    /// resolution stack — proving the mechanism without needing recursive factories
    /// (which would trap via `resolve` before the test could observe the throw).
    @Test func cycleDetectedWhenKeyAlreadyInStack() {
        let container = Container()
        container.register(TopNode.self) { _ in TopNode(middle: MiddleNode(leaf: DeepLeaf(label: ""))) }

        let stack: [RegistrationKey] = [
            RegistrationKey(TopNode.self, name: nil),   // already on stack
            RegistrationKey(MiddleNode.self, name: nil),
        ]
        Container.$resolutionStack.withValue(stack) {
            do {
                _ = try container.tryResolve(TopNode.self)   // cycle: TopNode already in stack
                #expect(Bool(false), "expected cycle")
            } catch let ResolutionError.cycle(chain) {
                // Chain reads top → middle → top
                #expect(chain.count == 3)
                #expect(chain.first?.contains("TopNode") == true)
                #expect(chain[1].contains("MiddleNode"))
                #expect(chain.last?.contains("TopNode") == true)
            } catch {
                #expect(Bool(false), "wrong error: \(error)")
            }
        }
    }

    @Test func cycleErrorDescriptionFormatsArrowChain() {
        let err = ResolutionError.cycle(chain: ["A", "B", "A"])
        let desc = String(describing: err)
        #expect(desc.contains("A → B → A"))
    }
}
