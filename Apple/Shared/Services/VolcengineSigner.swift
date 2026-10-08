import Foundation
import CryptoKit

enum VolcengineSigner {
    static func sign(request: inout URLRequest, body: Data, accessKey: String, secretKey: String, region: String = "cn-beijing", date: Date = Date()) {
        let timestamp = Self.timestampFormatter.string(from: date)
        let dateStamp = Self.dateFormatter.string(from: date)
        let payloadHash = Self.sha256Hex(body)
        let contentType = "application/json; charset=utf-8"
        let host = request.url?.host ?? "open.volcengineapi.com"
        let signedHeaders = "content-type;host;x-content-sha256;x-date"

        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(timestamp, forHTTPHeaderField: "X-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Content-Sha256")

        let canonicalRequest = [
            request.httpMethod ?? "POST",
            "/",
            canonicalQueryString(request.url),
            "content-type:\(contentType)",
            "host:\(host)",
            "x-content-sha256:\(payloadHash)",
            "x-date:\(timestamp)",
            "",
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/ark/request"
        let stringToSign = [
            "HMAC-SHA256",
            timestamp,
            credentialScope,
            Self.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let dateKey = Self.hmac(key: Data(secretKey.utf8), message: dateStamp)
        let regionKey = Self.hmac(key: dateKey, message: region)
        let serviceKey = Self.hmac(key: regionKey, message: "ark")
        let signingKey = Self.hmac(key: serviceKey, message: "request")
        let signature = Self.hmac(key: signingKey, message: stringToSign)
            .map { String(format: "%02x", $0) }.joined()

        let authorization = "HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    private static func canonicalQueryString(_ url: URL?) -> String {
        guard let url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              !items.isEmpty else { return "" }
        var pairs: [(key: String, value: String)] = items.map { item in
            (key: percentEncode(item.name), value: percentEncode(item.value ?? ""))
        }
        pairs.sort { lhs, rhs in
            lhs.key == rhs.key ? lhs.value < rhs.value : lhs.key < rhs.key
        }
        return pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func hmac(key: Data, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
