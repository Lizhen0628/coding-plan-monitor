import Foundation
import CryptoKit

// 用法: swift asc-jwt.swift <p8路径> <keyId> <issuerId>
// 输出 App Store Connect API 用的 ES256 JWT（有效期 20 分钟）

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("usage: asc-jwt <p8 path> <keyId> <issuerId>\n".data(using: .utf8)!)
    exit(1)
}

let pem = try String(contentsOfFile: args[1], encoding: .utf8)
let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let header = base64URL(try JSONSerialization.data(withJSONObject: [
    "alg": "ES256",
    "kid": args[2],
    "typ": "JWT",
]))

let now = Int(Date().timeIntervalSince1970)
let payload = base64URL(try JSONSerialization.data(withJSONObject: [
    "iss": args[3],
    "iat": now,
    "exp": now + 20 * 60,
    "aud": "appstoreconnect-v1",
]))

let signingInput = "\(header).\(payload)"
let signature = try privateKey.signature(for: Data(signingInput.utf8))
print("\(signingInput).\(base64URL(signature.rawRepresentation))")
