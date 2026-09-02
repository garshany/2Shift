import Foundation
import Security

enum CodeSignatureInfo {
    static func current() -> String {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)

        guard status == errSecSuccess, let code else {
            return "unknown"
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)

        guard staticStatus == errSecSuccess, let staticCode else {
            return "unknown"
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)

        guard
            infoStatus == errSecSuccess,
            let dictionary = information as? [String: Any]
        else {
            return "unknown"
        }

        if dictionary[kSecCodeInfoCertificates as String] is [Any] {
            return "Developer ID or certificate"
        }

        if dictionary[kSecCodeInfoIdentifier as String] != nil {
            return "ad-hoc"
        }

        return "unsigned"
    }
}
