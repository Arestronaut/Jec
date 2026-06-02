import Foundation

/// Lifetime of a registered dependency.
public enum Scope: Sendable, Hashable {
    /// One instance per container, lazily created on first resolve and retained for the container's lifetime.
    case singleton
    /// A new instance is produced on every resolve.
    case transient
    /// Weakly cached — reused while at least one resolved consumer holds it, otherwise rebuilt.
    /// Only meaningful for reference types; registering a value type with `.cached` behaves
    /// like `.transient` because each boxed copy is released immediately after being handed out.
    case cached
    /// Bound to the innermost `Container.withScope { ... }` block on the current Task. Resolving outside any scope throws.
    case scoped
}

/// Opaque identifier for a `.scoped` lifetime bucket. Two scopes with the same identifier are the same bucket.
public struct ScopeID: Sendable, Hashable {
    let raw: UUID

    init(raw: UUID) { self.raw = raw }

    /// Fresh, unique scope identifier — typical default for `withScope`.
    public static func anonymous() -> ScopeID { ScopeID(raw: UUID()) }

    /// Deterministic identifier derived from a name (useful for tests).
    ///
    /// Uses FNV-1a 64-bit run twice with distinct seeds to fill 16 bytes. FNV-1a is not
    /// cryptographic, but it is strictly position-sensitive — unlike the prior XOR-fold,
    /// permutations like `"abc"` vs `"cba"` produce distinct UUIDs.
    public static func named(_ name: String) -> ScopeID {
        let utf8 = Array(name.utf8)
        let high = fnv1a64(utf8, seed: 0xcbf29ce484222325)
        let low  = fnv1a64(utf8, seed: 0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { bytes[i]     = UInt8((high >> (8 * (7 - i))) & 0xff) }
        for i in 0..<8 { bytes[i + 8] = UInt8((low  >> (8 * (7 - i))) & 0xff) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40   // RFC 4122 version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return ScopeID(raw: uuid)
    }

    private static func fnv1a64(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        var hash = seed
        for b in bytes {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return hash
    }
}
