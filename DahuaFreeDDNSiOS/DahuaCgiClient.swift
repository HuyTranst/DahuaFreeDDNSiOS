import Foundation
import CryptoKit

struct CgiResult {
    let success: Bool
    let statusCode: Int
    let rawText: String
    let errorMessage: String?
}

class DahuaCgiClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }

    func fetchDahuaConfig(
        ip: String,
        port: String,
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=getConfig&name=DDNS"
        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    func saveDahuaDDNSConfig(
        ip: String,
        port: String,
        user: String,
        pass: String,
        channelIdx: String = "0",
        enable: Bool,
        serverAddr: String,
        domain: String,
        ddnsUser: String,
        ddnsPass: String,
        existingKeysText: String = "",
        completion: @escaping (CgiResult) -> Void
    ) {
        let userKey = existingKeysText.contains("table.DDNS[\(channelIdx)].UserName") ? "UserName" : "User"
        let passKey = existingKeysText.contains("table.DDNS[\(channelIdx)].Password") ? "Password" : "Pass"

        let enableStr = enable ? "true" : "false"
        
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=setConfig" +
                        "&DDNS[\(channelIdx)].Enable=\(enableStr)" +
                        "&DDNS[\(channelIdx)].Address=\(serverAddr)" +
                        "&DDNS[\(channelIdx)].HostName=\(domain)" +
                        "&DDNS[\(channelIdx)].\(userKey)=\(ddnsUser)" +
                        "&DDNS[\(channelIdx)].\(passKey)=\(ddnsPass)"

        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    private func executeWithAuth(
        urlString: String,
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: "URL không hợp lệ"))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: error.localizedDescription))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: "Phản hồi không phải HTTP"))
                return
            }

            let rawText = String(data: data ?? Data(), encoding: .utf8) ?? ""

            if httpResponse.statusCode != 401 {
                let success = (200...299).contains(httpResponse.statusCode)
                completion(CgiResult(success: success, statusCode: httpResponse.statusCode, rawText: rawText, errorMessage: nil))
                return
            }

            // Extract WWW-Authenticate header CASE-INSENSITIVELY
            let authHeader = self.getHeaderValue(httpResponse, name: "WWW-Authenticate") ?? ""

            var authedRequest = URLRequest(url: url)
            authedRequest.httpMethod = "GET"

            if authHeader.lowercased().contains("digest") {
                let digestValue = self.buildDigestHeader(method: "GET", urlString: urlString, user: user, pass: pass, authHeader: authHeader)
                authedRequest.addValue(digestValue, forHTTPHeaderField: "Authorization")
            } else if authHeader.lowercased().contains("basic") {
                let loginData = "\(user):\(pass)".data(using: .utf8)?.base64EncodedString() ?? ""
                authedRequest.addValue("Basic \(loginData)", forHTTPHeaderField: "Authorization")
            } else {
                let digestValue = self.buildDigestHeader(method: "GET", urlString: urlString, user: user, pass: pass, authHeader: authHeader)
                authedRequest.addValue(digestValue, forHTTPHeaderField: "Authorization")
            }

            let secondTask = self.session.dataTask(with: authedRequest) { secondData, secondResponse, secondError in
                if let secondError = secondError {
                    completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: secondError.localizedDescription))
                    return
                }

                let statusCode = (secondResponse as? HTTPURLResponse)?.statusCode ?? 0
                let secondText = String(data: secondData ?? Data(), encoding: .utf8) ?? ""
                let success = (200...299).contains(statusCode)

                completion(CgiResult(success: success, statusCode: statusCode, rawText: secondText, errorMessage: nil))
            }
            secondTask.resume()
        }
        task.resume()
    }

    private func getHeaderValue(_ response: HTTPURLResponse, name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            if let keyStr = key as? String, keyStr.caseInsensitiveCompare(name) == .orderedSame {
                return "\(value)"
            }
        }
        return nil
    }

    private func buildDigestHeader(
        method: String,
        urlString: String,
        user: String,
        pass: String,
        authHeader: String
    ) -> String {
        let params = parseHeaderParameters(header: authHeader)
        let realm = params["realm"] ?? ""
        let nonce = params["nonce"] ?? ""
        let qop = params["qop"] ?? ""
        let uri = extractUriPath(urlString: urlString)

        let ha1 = md5("\(user):\(realm):\(pass)")
        let ha2 = md5("\(method):\(uri)")

        let cnonce = randomHex(length: 16)
        let nc = "00000001"

        let response: String
        if qop.lowercased().contains("auth") {
            response = md5("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
        } else {
            response = md5("\(ha1):\(nonce):\(ha2)")
        }

        var sb = "Digest username=\"\(user)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\", "
        if qop.lowercased().contains("auth") {
            sb += "qop=auth, nc=\(nc), cnonce=\"\(cnonce)\", "
        }
        sb += "response=\"\(response)\""
        return sb
    }

    private func parseHeaderParameters(header: String) -> [String: String] {
        var map = [String: String]()
        var cleaned = header
        if let firstSpace = header.firstIndex(of: " ") {
            cleaned = String(header[header.index(after: firstSpace)...])
        }

        let pairs = cleaned.components(separatedBy: ",")
        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                var value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                map[key] = value
            }
        }
        return map
    }

    private func extractUriPath(urlString: String) -> String {
        if let schemeRange = urlString.range(of: "://") {
            let afterScheme = urlString[schemeRange.upperBound...]
            if let firstSlash = afterScheme.firstIndex(of: "/") {
                return String(afterScheme[firstSlash...])
            }
        }
        return urlString
    }

    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func randomHex(length: Int) -> String {
        let letters = "abcdef0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
}
