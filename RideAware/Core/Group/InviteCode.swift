import Foundation

/// Short, expiring invitation code for a private ride group.
///
/// The alphabet omits look-alike characters (0/O, 1/I/L). 31^6 ≈ 8.9 × 10^8 codes; a network
/// backend must still rate-limit join attempts and bind codes to a group server-side.
struct InviteCode: Sendable, Equatable, Codable, Hashable {
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 6
    static let defaultLifetime: TimeInterval = 30 * 60

    let value: String
    let expiresAt: Date

    static func generate<R: RandomNumberGenerator>(now: Date, lifetime: TimeInterval = defaultLifetime, using rng: inout R) -> InviteCode {
        let value = String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
        return InviteCode(value: value, expiresAt: now.addingTimeInterval(lifetime))
    }

    static func generate(now: Date, lifetime: TimeInterval = defaultLifetime) -> InviteCode {
        var rng = SystemRandomNumberGenerator()
        return generate(now: now, lifetime: lifetime, using: &rng)
    }

    /// Normalises user input ("abc-def", " ABC DEF ") to the canonical form, or `nil` if malformed.
    static func normalize(_ input: String) -> String? {
        let cleaned = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy(alphabet.contains) else { return nil }
        return cleaned
    }

    func isExpired(at now: Date) -> Bool { now >= expiresAt }

    /// "ABC-DEF" for display and reading aloud.
    var formatted: String {
        let split = value.index(value.startIndex, offsetBy: Self.length / 2)
        return "\(value[..<split])-\(value[split...])"
    }
}
