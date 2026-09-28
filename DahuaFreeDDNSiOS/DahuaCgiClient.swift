import Foundation
import Darwin

struct CgiResult {
    let success: Bool
    let statusCode: Int
    let rawText: String
    let errorMessage: String?
}

struct PortScanResult: Identifiable {
    let id = UUID()
    let port: Int
    let service: String
    let isOpen: Bool
}

class DahuaCgiClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - DDNS & IP Configuration
    func fetchDahuaDDNSConfig(
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
        channelIdx: String,
        enable: Bool,
        serverAddr: String,
        domain: String,
        ddnsUser: String,
        ddnsPass: String,
        existingKeysText: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let enStr = enable ? "true" : "false"
        let encDomain = domain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? domain
        let encServer = serverAddr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? serverAddr
        let encUser = ddnsUser.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ddnsUser
        let encPass = ddnsPass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ddnsPass

        let idx = channelIdx
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=setConfig" +
            "&DDNS[\(idx)].Enable=\(enStr)" +
            "&DDNS[\(idx)].ServerAddress=\(encServer)" +
            "&DDNS[\(idx)].DomainName=\(encDomain)" +
            "&DDNS[\(idx)].Username=\(encUser)" +
            "&DDNS[\(idx)].Password=\(encPass)"

        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    func saveDahuaDDNSConfig(
        ip: String,
        port: String,
        user: String,
        pass: String,
        channelIdx: Int,
        enable: Bool,
        serverAddr: String,
        domain: String,
        ddnsUser: String,
        ddnsPass: String,
        existingKeysText: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        saveDahuaDDNSConfig(
            ip: ip,
            port: port,
            user: user,
            pass: pass,
            channelIdx: "\(channelIdx)",
            enable: enable,
            serverAddr: serverAddr,
            domain: domain,
            ddnsUser: ddnsUser,
            ddnsPass: ddnsPass,
            existingKeysText: existingKeysText,
            completion: completion
        )
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
        let urlString = "http://\(currentIp):80/cgi-bin/configManager.cgi?action=setConfig" +
            "&Network.eth0.IPAddress=\(newIp)" +
            "&Network.eth0.SubnetMask=\(subnetMask)" +
            "&Network.eth0.DefaultGateway=\(gateway)"

        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    // MARK: - Reboot Device
    func rebootDevice(
        ip: String,
        port: String = "80",
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let urlString = "http://\(ip):\(port)/cgi-bin/magicBox.cgi?action=reboot"
        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    // MARK: - Date / Time Sync
    func getDeviceTime(
        ip: String,
        port: String = "80",
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let urlString = "http://\(ip):\(port)/cgi-bin/global.cgi?action=getCurrentTime"
        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    func setDeviceTime(
        ip: String,
        port: String = "80",
        user: String,
        pass: String,
        timeString: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let encodedTime = timeString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? timeString
        let urlString = "http://\(ip):\(port)/cgi-bin/global.cgi?action=setCurrentTime&time=\(encodedTime)"
        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    // MARK: - NTP Config
    func getNtpConfig(
        ip: String,
        port: String = "80",
        user: String,
        pass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=getConfig&name=NTP"
        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    func setNtpConfig(
        ip: String,
        port: String = "80",
        user: String,
        pass: String,
        enable: Bool,
        server: String,
        ntpPort: Int = 123,
        period: Int = 60,
        completion: @escaping (CgiResult) -> Void
    ) {
        let enStr = enable ? "true" : "false"
        let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=setConfig&NTP.Enable=\(enStr)&NTP.Address=\(server)&NTP.Port=\(ntpPort)&NTP.UpdatePeriod=\(period)"
        executeWithAuth(urlString: urlString, user: user, pass: pass, completion: completion)
    }

    // MARK: - Port Checker Engine
    func checkPorts(
        host: String,
        ports: [Int] = [80, 443, 554, 37777, 37778, 8000, 8080, 23, 5000, 34567],
        timeoutSec: Double = 1.2,
        completion: @escaping ([PortScanResult]) -> Void
    ) {
        let serviceNames: [Int: String] = [
            80: "HTTP Web Quản lý",
            443: "HTTPS Web (SSL)",
            554: "RTSP Luồng Video",
            37777: "Dahua NetSDK TCP",
            37778: "Dahua DHDiscover UDP",
            8000: "Hikvision Private Port",
            8080: "Alternative HTTP",
            34567: "Xiongmai (XM) Port",
            23: "Telnet Shell",
            5000: "UPnP / ONVIF Media"
        ]

        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .components(separatedBy: "/").first ?? host

        let group = DispatchGroup()
        var results: [PortScanResult] = []
        let lock = NSLock()

        for p in ports {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let isOpen = self.probeTcpPort(host: cleanHost, port: p, timeoutSec: timeoutSec)
                let res = PortScanResult(
                    port: p,
                    service: serviceNames[p] ?? "Dịch vụ TCP",
                    isOpen: isOpen
                )
                lock.lock()
                results.append(res)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            results.sort(by: { $0.port < $1.port })
            completion(results)
        }
    }

    private func probeTcpPort(host: String, port: Int, timeoutSec: Double = 1.2) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        var tv = timeval(tv_sec: Int(timeoutSec), tv_usec: Int32((timeoutSec.truncatingRemainder(dividingBy: 1.0)) * 1000000))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian

        if inet_pton(AF_INET, host, &addr.sin_addr) <= 0 {
            // If domain name, try gethostbyname fallback
            guard let hostent = gethostbyname(host),
                  let addrList = hostent.pointee.h_addr_list,
                  let firstAddr = addrList[0] else {
                return false
            }
            memcpy(&addr.sin_addr, firstAddr, Int(hostent.pointee.h_length))
        }

        let connRes = withUnsafePointer(to: &addr) { saPtrIn in
            saPtrIn.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                connect(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connRes == 0
    }

    func changePassword(
        ip: String,
        port: String,
        user: String,
        oldPass: String,
        newPass: String,
        completion: @escaping (CgiResult) -> Void
    ) {
        let urlString = "http://\(ip):\(port)/cgi-bin/userManager.cgi?action=modifyPassword" +
                        "&name=\(user)&pwd=\(oldPass)&newpwd=\(newPass)"

        executeWithAuth(urlString: urlString, user: user, pass: oldPass, completion: completion)
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

        let ha1 = pureMd5("\(user):\(realm):\(pass)")
        let ha2 = pureMd5("\(method):\(uri)")

        let cnonce = randomHex(length: 16)
        let nc = "00000001"

        let response: String
        if qop.lowercased().contains("auth") {
            response = pureMd5("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
        } else {
            response = pureMd5("\(ha1):\(nonce):\(ha2)")
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

    private func pureMd5(_ string: String) -> String {
        let message = Array(string.utf8)
        var messageLenBits = UInt64(message.count) * 8

        var padded = message
        padded.append(0x80)

        while (padded.count % 64) != 56 {
            padded.append(0x00)
        }

        withUnsafeBytes(of: &messageLenBits) { ptr in
            padded.append(contentsOf: ptr)
        }

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
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
            0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
            0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
            0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
            0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
            0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
            0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
            0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
            0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
        ]

        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            let chunk = Array(padded[chunkStart..<chunkStart + 64])
            var M = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = i * 4
                M[i] = UInt32(chunk[offset]) |
                       (UInt32(chunk[offset + 1]) << 8) |
                       (UInt32(chunk[offset + 2]) << 16) |
                       (UInt32(chunk[offset + 3]) << 24)
            }

            var AA = a
            var BB = b
            var CC = c
            var DD = d

            for i in 0..<64 {
                var f: UInt32 = 0
                var g: Int = 0

                if i < 16 {
                    f = (BB & CC) | ((~BB) & DD)
                    g = i
                } else if i < 32 {
                    f = (DD & BB) | ((~DD) & CC)
                    g = (5 * i + 1) % 16
                } else if i < 48 {
                    f = BB ^ CC ^ DD
                    g = (3 * i + 5) % 16
                } else {
                    f = CC ^ (BB | (~DD))
                    g = (7 * i) % 16
                }

                let temp = DD
                DD = CC
                CC = BB
                let sum = AA &+ f &+ k[i] &+ M[g]
                let rotated = (sum << s[i]) | (sum >> (32 - s[i]))
                BB = BB &+ rotated
                AA = temp
            }

            a = a &+ AA
            b = b &+ BB
            c = c &+ CC
            d = d &+ DD
        }

        return String(format: "%08x%08x%08x%08x",
                      UInt32(bigEndian: a.littleEndian),
                      UInt32(bigEndian: b.littleEndian),
                      UInt32(bigEndian: c.littleEndian),
                      UInt32(bigEndian: d.littleEndian))
    }

    private func randomHex(length: Int) -> String {
        let letters = "abcdef0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
}
