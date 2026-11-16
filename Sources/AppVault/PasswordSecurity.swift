import Foundation
import CommonCrypto
import Security

enum PasswordPolicy {
    static func violation(for password: String) -> String? {
        guard password.count >= 12 else { return "Use at least 12 characters." }
        guard password.rangeOfCharacter(from: .uppercaseLetters) != nil else { return "Include an uppercase letter." }
        guard password.rangeOfCharacter(from: .lowercaseLetters) != nil else { return "Include a lowercase letter." }
        guard password.rangeOfCharacter(from: .decimalDigits) != nil else { return "Include a number." }
        return nil
    }
}

enum PasswordSecurity {
    static func makeVerifier(password: String, salt: Data = randomSalt(), rounds: Int = PasswordVerifier.currentRounds) -> PasswordVerifier {
        PasswordVerifier(salt: salt, digest: derive(password: password, salt: salt, rounds: rounds), rounds: rounds)
    }
    static func verify(_ password: String, verifier: PasswordVerifier) -> Bool {
        constantTimeEqual(derive(password: password, salt: verifier.salt, rounds: verifier.rounds), verifier.digest)
    }
    private static func randomSalt() -> Data {
        var bytes = Data(repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        precondition(result == errSecSuccess, "Secure random generation failed")
        return bytes
    }
    private static func derive(password: String, salt: Data, rounds: Int) -> Data {
        var output = Data(repeating: 0, count: kCCKeySizeAES256)
        let outputLength = output.count
        let result = output.withUnsafeMutableBytes { outputBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes, password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
                        outputBytes.bindMemory(to: UInt8.self).baseAddress, outputLength
                    )
                }
            }
        }
        precondition(result == kCCSuccess, "PBKDF2 failed")
        return output
    }
    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }; var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { diff |= a ^ b }; return diff == 0
    }
}
