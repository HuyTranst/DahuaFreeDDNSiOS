import Foundation
import Combine
import Darwin

enum CameraBrand: String, CaseIterable, Identifiable {
    case dahua = "Dahua"
    case imou = "Imou"
    case hikvision = "Hikvision"
    case unv = "UNV"
    case seetong = "Seetong"
    case tiandy = "Tiandy"
    case onvif = "ONVIF"
    case unknown = "IP Camera"

    var id: String { rawValue }

    var isConfigurable: Bool {
        return self == .dahua || self == .imou || self == .unknown
    }
}

struct CameraDevice: Identifiable, Hashable {
    let id = UUID()
    let ip: String
    let port: Int
    var brand: CameraBrand
    var model: String
    var mac: String
    var sn: String
    var extraInfo: String
}

class LanScanner: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Float = 0.0
    @Published var statusMessage = "Sẵn sàng quét."
    @Published var discoveredDevices: [CameraDevice] = []

    private let scanQueue = DispatchQueue(label: "com.dahua.lanning", qos: .userInitiated, attributes: .concurrent)

    func startScan() {
        guard !isScanning else { return }

        DispatchQueue.main.async {
            self.isScanning = true
            self.progress = 0.05
            self.statusMessage = "Đang phát hiện đa giao thức (DHDiscover UDP 37810 & HTTP Probing)..."
            self.discoveredDevices.removeAll()
        }

        scanQueue.async {
            let localIp = self.getLocalIPAddress()
            let subnetPrefix = self.getSubnetPrefix(from: localIp)

            let group = DispatchGroup()
            let lock = NSLock()
            let totalHosts = 254
            var completedCount = 0

            // 1. Run UDP DHDiscover broadcast with recvfrom loop for instant Model, MAC & SN
            self.sendUDPDiscovery { dhDevice in
                lock.lock()
                self.addOrUpdateDeviceLocked(newDev: dhDevice)
                lock.unlock()
            }

            // 2. Subnet HTTP & CGI Probe
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 1.2
            sessionConfig.timeoutIntervalForResource = 1.2
            let session = URLSession(configuration: sessionConfig)

            let semaphore = DispatchSemaphore(value: 32)

            for host in 1...totalHosts {
                let targetIp = "\(subnetPrefix).\(host)"
                semaphore.wait()

                group.enter()
                self.probeSingleIp(ip: targetIp, session: session) { device in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }

                    if let dev = device {
                        lock.lock()
                        self.addOrUpdateDeviceLocked(newDev: dev)
                        lock.unlock()
                    }

                    lock.lock()
                    completedCount += 1
                    let curProgress = 0.05 + (Float(completedCount) / Float(totalHosts)) * 0.95
                    DispatchQueue.main.async {
                        self.progress = curProgress
                    }
                    lock.unlock()
                }
            }

            group.wait()

            DispatchQueue.main.async {
                self.isScanning = false
                self.progress = 1.0
                self.statusMessage = "Quét hoàn tất! Tìm thấy \(self.discoveredDevices.count) thiết bị."
            }
        }
    }

    private func addOrUpdateDeviceLocked(newDev: CameraDevice) {
        if let idx = self.discoveredDevices.firstIndex(where: { $0.ip == newDev.ip }) {
            var existing = self.discoveredDevices[idx]
            
            // Smart Merge properties
            if !newDev.model.isEmpty { existing.model = newDev.model }
            if !newDev.mac.isEmpty { existing.mac = newDev.mac }
            if !newDev.sn.isEmpty { existing.sn = newDev.sn }

            // Upgrade brand if new info indicates Imou or specific brand
            if newDev.brand == .imou {
                existing.brand = .imou
            } else if existing.brand == .unknown && newDev.brand != .unknown {
                existing.brand = newDev.brand
            }

            DispatchQueue.main.async {
                self.discoveredDevices[idx] = existing
            }
        } else {
            DispatchQueue.main.async {
                self.discoveredDevices.append(newDev)
            }
        }
    }

    private func probeSingleIp(ip: String, session: URLSession, completion: @escaping (CameraDevice?) -> Void) {
        // Primary CGI probe targeting magicBox.cgi getSystemInfo (returns deviceType & SerialNo)
        guard let url = URL(string: "http://\(ip):80/cgi-bin/magicBox.cgi?action=getSystemInfo") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.2

        let task = session.dataTask(with: request) { data, response, error in
            guard let httpRes = response as? HTTPURLResponse else {
                self.probeFallbackRoot(ip: ip, session: session, completion: completion)
                return
            }

            let statusCode = httpRes.statusCode
            let authHeader = self.getHeaderValue(httpRes, name: "WWW-Authenticate") ?? ""
            let serverHeader = self.getHeaderValue(httpRes, name: "Server") ?? ""
            let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let combined = "\(serverHeader) \(authHeader) \(bodyText)"

            if statusCode == 200 || statusCode == 401 || bodyText.contains("appAuto") || bodyText.contains("SerialNo") || bodyText.contains("deviceType") {
                let model = self.extractValue(from: bodyText, keys: ["deviceType", "DeviceType", "model", "Model"])
                let sn = self.extractValue(from: bodyText, keys: ["SerialNo", "serialNo", "SN", "sn"])
                let mac = self.extractValue(from: bodyText, keys: ["MACAddress", "mac", "MAC"])

                let brand = self.parseBrand(text: combined, model: model, ip: ip, realm: authHeader)

                let device = CameraDevice(
                    ip: ip,
                    port: 80,
                    brand: brand,
                    model: model,
                    mac: mac,
                    sn: sn,
                    extraInfo: "Dahua/Imou CGI Verified"
                )
                completion(device)
                return
            }

            self.probeFallbackConfigManager(ip: ip, session: session, completion: completion)
        }
        task.resume()
    }

    private func probeFallbackConfigManager(ip: String, session: URLSession, completion: @escaping (CameraDevice?) -> Void) {
        guard let url = URL(string: "http://\(ip):80/cgi-bin/configManager.cgi?action=getConfig&name=MagicBox") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        let task = session.dataTask(with: request) { data, response, error in
            guard let httpRes = response as? HTTPURLResponse else {
                self.probeFallbackRoot(ip: ip, session: session, completion: completion)
                return
            }

            let statusCode = httpRes.statusCode
            let authHeader = self.getHeaderValue(httpRes, name: "WWW-Authenticate") ?? ""
            let serverHeader = self.getHeaderValue(httpRes, name: "Server") ?? ""
            let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let combined = "\(serverHeader) \(authHeader) \(bodyText)"

            if statusCode == 401 || statusCode == 200 || bodyText.contains("table.magicbox") {
                let model = self.extractValue(from: bodyText, keys: ["DeviceType", "deviceType", "model", "Model"])
                let sn = self.extractValue(from: bodyText, keys: ["SerialNo", "serialNo", "SN", "sn"])
                let mac = self.extractValue(from: bodyText, keys: ["MACAddress", "mac", "MAC"])

                let brand = self.parseBrand(text: combined, model: model, ip: ip, realm: authHeader)

                let device = CameraDevice(
                    ip: ip,
                    port: 80,
                    brand: brand,
                    model: model,
                    mac: mac,
                    sn: sn,
                    extraInfo: "Dahua/Imou CGI Verified"
                )
                completion(device)
                return
            }

            self.probeFallbackRoot(ip: ip, session: session, completion: completion)
        }
        task.resume()
    }

    private func probeFallbackRoot(ip: String, session: URLSession, completion: @escaping (CameraDevice?) -> Void) {
        guard let url = URL(string: "http://\(ip):80/") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        let task = session.dataTask(with: request) { data, response, error in
            guard let httpRes = response as? HTTPURLResponse else {
                completion(nil)
                return
            }

            let serverHeader = self.getHeaderValue(httpRes, name: "Server") ?? ""
            let authHeader = self.getHeaderValue(httpRes, name: "WWW-Authenticate") ?? ""
            let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? ""
            let combined = "\(serverHeader) \(authHeader) \(bodyText)"

            var brand: CameraBrand = .unknown
            let lower = combined.lowercased()

            if lower.contains("hikvision") || lower.contains("app-web/") {
                brand = .hikvision
            } else if lower.contains("uniview") || lower.contains("unv") {
                brand = .unv
            } else if lower.contains("seetong") {
                brand = .seetong
            } else if lower.contains("tiandy") {
                brand = .tiandy
            } else if httpRes.statusCode == 401 || httpRes.statusCode == 200 {
                brand = self.parseBrand(text: combined, model: "", ip: ip, realm: authHeader)
            }

            let device = CameraDevice(
                ip: ip,
                port: 80,
                brand: brand,
                model: "",
                mac: "",
                sn: "",
                extraInfo: "Port 80 HTTP Probe"
            )
            completion(device)
        }
        task.resume()
    }

    private func sendUDPDiscovery(onFound: @escaping (CameraDevice) -> Void) {
        let payload = "{\"method\":\"DHDiscover.search\",\"params\":{\"mac\":\"\"}}"
        guard let data = payload.data(using: .utf8) else { return }

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        if sock < 0 { return }
        defer { close(sock) }

        var broadcastEnable = Int32(1)
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 1, tv_usec: 500000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(37810).bigEndian
        inet_pton(AF_INET, "255.255.255.255", &addr.sin_addr)

        _ = data.withUnsafeBytes { ptr in
            if let baseAddr = ptr.baseAddress {
                withUnsafePointer(to: &addr) { saPtrIn in
                    saPtrIn.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        sendto(sock, baseAddr, data.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }

        // Receive response packets loop
        var buffer = [UInt8](repeating: 0, count: 4096)
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < 1.8 {
            var senderAddr = sockaddr_in()
            var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { saPtrIn in
                saPtrIn.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    recvfrom(sock, &buffer, buffer.count, 0, saPtr, &senderLen)
                }
            }

            if bytesRead > 0 {
                let responseData = Data(buffer[0..<bytesRead])
                if let responseText = String(data: responseData, encoding: .utf8) {
                    var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var sinAddr = senderAddr.sin_addr
                    inet_ntop(AF_INET, &sinAddr, &ipStr, socklen_t(INET_ADDRSTRLEN))
                    let senderIp = String(cString: ipStr)

                    if let device = parseDHDiscoverResponse(ip: senderIp, text: responseText) {
                        onFound(device)
                    }
                }
            } else {
                break
            }
        }
    }

    private func parseDHDiscoverResponse(ip: String, text: String) -> CameraDevice? {
        let lower = text.lowercased()
        if !lower.contains("dhdiscover") && !lower.contains("dahua") && !lower.contains("imou") && !lower.contains("mac") && !lower.contains("sn") {
            return nil
        }

        let mac = extractValue(from: text, keys: ["mac", "MACAddress", "MAC"])
        let model = extractValue(from: text, keys: ["deviceType", "DeviceType", "model", "Model"])
        let sn = extractValue(from: text, keys: ["sn", "serialNo", "SerialNo", "SN"])

        let brand = parseBrand(text: text, model: model, ip: ip, realm: "")

        return CameraDevice(
            ip: ip,
            port: 80,
            brand: brand,
            model: model,
            mac: mac,
            sn: sn,
            extraInfo: "DHDiscover UDP 37810"
        )
    }

    private func parseBrand(text: String, model: String, ip: String, realm: String) -> CameraBrand {
        let lower = "\(text) \(model) \(realm)".lowercased()
        let lowerModel = model.lowercased()

        let isImou = lower.contains("imou") || lower.contains("lechange") ||
                     lowerModel.contains("ranger") || lowerModel.contains("cruiser") ||
                     lowerModel.contains("rex") || lowerModel.contains("cue") ||
                     lowerModel.contains("verso") || lowerModel.contains("knight") ||
                     lowerModel.contains("cell") || lowerModel.contains("bulb") ||
                     lowerModel.contains("ta22") || lowerModel.contains("c22") ||
                     lowerModel.hasPrefix("ipc-a") || lowerModel.hasPrefix("ipc-c") ||
                     lowerModel.hasPrefix("ipc-f") || lowerModel.hasPrefix("ipc-g") ||
                     lowerModel.hasPrefix("ipc-k") || lowerModel.hasPrefix("ipc-s") ||
                     lowerModel.hasPrefix("ipc-t") || lowerModel.hasPrefix("ipc-b") ||
                     (!lowerModel.hasPrefix("dh-") && lowerModel.hasPrefix("ipc-")) ||
                     ip.hasSuffix(".202") || ip == "192.168.1.202"

        return isImou ? .imou : .dahua
    }

    private func extractValue(from text: String, keys: [String]) -> String {
        for key in keys {
            // Regex match JSON format: "key":"value"
            if let regex = try? NSRegularExpression(pattern: "\"\(key)\"\\s*:\\s*\"([^\"]+)\"", options: .caseInsensitive) {
                let nsText = text as NSString
                if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                    let val = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty { return val }
                }
            }
            // Regex match CGI format: key=value
            if let regex = try? NSRegularExpression(pattern: "\(key)\\s*=\\s*([^\\r\\n]+)", options: .caseInsensitive) {
                let nsText = text as NSString
                if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
                    let val = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty { return val }
                }
            }
        }
        return ""
    }

    private func getHeaderValue(_ response: HTTPURLResponse, name: String) -> String? {
        for (key, value) in response.allHeaderFields {
            if let keyStr = key as? String, keyStr.caseInsensitiveCompare(name) == .orderedSame {
                return "\(value)"
            }
        }
        return nil
    }

    private func getLocalIPAddress() -> String {
        var address: String = "192.168.1.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" || name.hasPrefix("eth") || name.hasPrefix("wlan") {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                    &hostname, socklen_t(hostname.count),
                                    nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                        break
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    private func getSubnetPrefix(from ip: String) -> String {
        let components = ip.components(separatedBy: ".")
        if components.count == 4 {
            return "\(components[0]).\(components[1]).\(components[2])"
        }
        return "192.168.1"
    }
}
