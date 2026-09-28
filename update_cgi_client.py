import Foundation

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

    func fetchDahuaDDNSConfig(
        ip: String,
        port: String,
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        fetchDahuaConfig(ip: ip, port: port, user: user, pass: pass, completion: completion)
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

        var params = [
            "action=setConfig",
            "table.DDNS[\(channelIdx)].Enable=\(enableStr)",
            "table.DDNS[\(channelIdx)].Address=\(serverAddr)",
            "table.DDNS[\(channelIdx)].Domain=\(domain)",
            "table.DDNS[\(channelIdx)].HostName=\(domain)",
            "table.DDNS[\(channelIdx)].\(userKey)=\(ddnsUser)",
            "table.DDNS[\(channelIdx)].\(passKey)=\(ddnsPass)"
        ]

        if existingKeysText.contains("table.DDNS[\(channelIdx)].Server") {
            params.append("table.DDNS[\(channelIdx)].Server=\(serverAddr)")
        }

        let query = params.joined(separator: "&")
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?\(query)"

        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    func changeCameraIp(
        currentIp: String,
        newIp: String,
        subnetMask: String,
        gateway: String,
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let query = "action=setConfig&Network.eth0.IPAddress=\(newIp)&Network.eth0.SubnetMask=\(subnetMask)&Network.eth0.DefaultGateway=\(gateway)"
        let urlString = "http://\(currentIp):80/cgi-bin/configManager.cgi?\(query)"
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

        let task = session.dataTask(with: request) { data, response, error in
            if let err = error {
                completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: err.localizedDescription))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(CgiResult(success: false, statusCode: 0, rawText: "", errorMessage: "Phản hồi không xác định"))
                return
            }

            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""

            if httpResponse.statusCode == 401 {
                if let authHeader = self.getHeaderValue(httpResponse, name: "WWW-Authenticate") {
                    if authHeader.lowercased().contains("digest") {
                        self.executeDigestAuth(urlString: urlString, authHeader: authHeader, user: user, pass: pass, completion: completion)
                        return
                    } else if authHeader.lowercased().contains("basic") {
                        self.executeBasicAuth(urlString: urlString, user: user, pass: pass, completion: completion)
                        return
                    }
                }
            }

            let success = (httpResponse.statusCode == 200)
            completion(CgiResult(success: success, statusCode: httpResponse.statusCode, rawText: text, errorMessage: nil))
        }
        task.resume()
    }

    private func executeBasicAuth(
        urlString: String,
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let loginString = "\(user):\(pass)"
        if let loginData = loginString.data(using: .utf8) {
            let base64LoginString = loginData.base64EncodedString()
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        }

        let task = session.dataTask(with: request) { data, response, error in
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(CgiResult(success: (code == 200), statusCode: code, rawText: text, errorMessage: error?.localizedDescription))
        }
        task.resume()
    }

    private func executeDigestAuth(
        urlString: String,
        authHeader: String,
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let authParams = parseHeaderParameters(header: authHeader)
        let realm = authParams["realm"] ?? ""
        let nonce = authParams["nonce"] ?? ""
        let qop = authParams["qop"] ?? ""
        let opaque = authParams["opaque"] ?? ""

        let uri = extractUriPath(urlString: urlString)
        let nc = "00000001"
        let cnonce = randomHex(length: 16)

        let authVal = buildDigestHeader(
            user: user,
            pass: pass,
            realm: realm,
            nonce: nonce,
            uri: uri,
            qop: qop,
            nc: nc,
            cnonce: cnonce,
            opaque: opaque,
            method: "GET"
        )

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authVal, forHTTPHeaderField: "Authorization")

        let task = session.dataTask(with: request) { data, response, error in
            let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(CgiResult(success: (code == 200), statusCode: code, rawText: text, errorMessage: error?.localizedDescription))
        }
        task.resume()
    }

    private func buildDigestHeader(
        user: String,
        pass: String,
        realm: String,
        nonce: String,
        uri: String,
        qop: String,
        nc: String,
        cnonce: String,
        opaque: String,
        method: String
    ) -> String {
        let ha1 = md5("\(user):\(realm):\(pass)")
        let ha2 = md5("\(method):\(uri)")

        var response = ""
        if qop.contains("auth") {
            response = md5("\(ha1):\(nonce):\(nc):\(cnonce):\(qop):\(ha2)")
        } else {
            response = md5("\(ha1):\(nonce):\(ha2)")
        }

        var sb = "Digest username=\"\(user)\", realm=\"\(realm)\", nonce=\"\(nonce)\", uri=\"\(uri)\", "
        if !opaque.isEmpty {
            sb += "opaque=\"\(opaque)\", "
        }
        if !qop.isEmpty {
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
        var bytes = Array(string.utf8)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 {
            bytes.append(0)
        }
        var lenBytes = bitLength.littleEndian
        withUnsafeBytes(of: &lenBytes) { bytes.append(contentsOf: $0) }

        var a: UInt32 = 0x67452301
        var b: UInt32 = 0xefcdab89
        var c: UInt32 = 0x98badcfe
        var d: UInt32 = 0x10325476

        let s: [UInt32] = [
            7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
            5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
            4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
            6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
        ]

        let k: [UInt32] = [
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
        ]

        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let off = chunkStart + i * 4
                w[i] = UInt32(bytes[off]) | (UInt32(bytes[off+1]) << 8) | (UInt32(bytes[off+2]) << 16) | (UInt32(bytes[off+3]) << 24)
            }

            var aa = a, bb = b, cc = c, dd = d

            for i in 0..<64 {
                var f: UInt32 = 0
                var g: Int = 0
                if i < 16 {
                    f = (bb & cc) | (~bb & dd)
                    g = i
                } else if i < 32 {
                    f = (dd & bb) | (~dd & cc)
                    g = (5 * i + 1) % 16
                } else if i < 48 {
                    f = bb ^ cc ^ dd
                    g = (3 * i + 5) % 16
                } else {
                    f = cc ^ (bb | ~dd)
                    g = (7 * i) % 16
                }

                let temp = dd
                dd = cc
                cc = bb
                let sum = aa &+ f &+ k[i] &+ w[g]
                bb = bb &+ ((sum << s[i]) | (sum >> (32 - s[i])))
                aa = temp
            }

            a = a &+ aa
            b = b &+ bb
            c = c &+ cc
            d = d &+ dd
        }

        let res = [a, b, c, d]
        var md5Bytes = [UInt8]()
        for word in res {
            var w = word.littleEndian
            withUnsafeBytes(of: &w) { md5Bytes.append(contentsOf: $0) }
        }
        return md5Bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func getHeaderValue(_ response: HTTPURLResponse, name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            if let keyStr = key as? String, keyStr.caseInsensitiveCompare(name) == .orderedSame {
                return "\(value)"
            }
        }
        return nil
    }

    private func randomHex(length: Int) -> String {
        let letters = "abcdef0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
}
'''

with open(r"C:\Users\Windows\.gemini\antigravity\scratch\DahuaFreeDDNSiOS\DahuaFreeDDNSiOS\DahuaCgiClient.swift", "w", encoding="utf-8") as f:
    f.write(CodeContent)

print("Updated DahuaCgiClient.swift with pure Swift MD5!")
