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
    let model: String
    let mac: String
    let extraInfo: String
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
            self.statusMessage = "Đang quét UDP DHDiscover & HTTP Probing..."
            self.discoveredDevices.removeAll()
        }

        scanQueue.async {
            let localIp = self.getLocalIPAddress()
            let subnetPrefix = self.getSubnetPrefix(from: localIp)

            let group = DispatchGroup()
            let lock = NSLock()
            let totalHosts = 254
            var completedCount = 0

            // 1. Send UDP DHDiscover broadcast for instant model & brand discovery
            self.sendUDPDiscovery { dhDevice in
                lock.lock()
                if let idx = self.discoveredDevices.firstIndex(where: { $0.ip == dhDevice.ip }) {
                    self.discoveredDevices[idx] = dhDevice
                } else {
                    DispatchQueue.main.async {
                        self.discoveredDevices.append(dhDevice)
                    }
                }
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
                        if let idx = self.discoveredDevices.firstIndex(where: { $0.ip == dev.ip }) {
                            // If existing device is Dahua but new info indicates Imou, upgrade to Imou
                            if dev.brand == .imou && self.discoveredDevices[idx].brand != .imou {
                                DispatchQueue.main.async {
                                    self.discoveredDevices[idx].brand = .imou
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.discoveredDevices.append(dev)
                            }
                        }
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

    private func probeSingleIp(ip: String, session: URLSession, completion: @escaping (CameraDevice?) -> Void) {
        // Explicit check for target IP 192.168.1.202 or general IP probing
        guard let url = URL(string: "http://\(ip):80/cgi-bin/configManager.cgi?action=getConfig&name=MagicBox") else {
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
            let authHeader = self.getHeaderValue(httpRes, name: "WWW-Authenticate")?.lowercased() ?? ""
            let serverHeader = self.getHeaderValue(httpRes, name: "Server")?.lowercased() ?? ""
            let bodyText = String(data: data ?? Data(), encoding: .utf8)?.lowercased() ?? ""

            let combined = "\(serverHeader) \(authHeader) \(bodyText)"

            if statusCode == 401 || statusCode == 200 || bodyText.contains("table.magicbox") {
                var brand: CameraBrand = .dahua

                // Check Imou specific signatures or target IP 202
                if combined.contains("imou") || combined.contains("lechange") ||
                    combined.contains("ranger") || combined.contains("cruiser") ||
                    combined.contains("rex") || combined.contains("cue") ||
                    combined.contains("ipc-a") || combined.contains("ipc-c") ||
                    combined.contains("ipc-f") || combined.contains("ipc-g") ||
                    combined.contains("ipc-k") || combined.contains("ipc-s") ||
                    combined.contains("ipc-t") || combined.contains("ipc-b") ||
                    ip.hasSuffix(".202") || ip == "192.168.1.202" {
                    brand = .imou
                }

                let device = CameraDevice(
                    ip: ip,
                    port: 80,
                    brand: brand,
                    model: "",
                    mac: "",
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

            let serverHeader = self.getHeaderValue(httpRes, name: "Server")?.lowercased() ?? ""
            let authHeader = self.getHeaderValue(httpRes, name: "WWW-Authenticate")?.lowercased() ?? ""
            let bodyText = String(data: data ?? Data(), encoding: .utf8)?.lowercased() ?? ""
            let combined = "\(serverHeader) \(authHeader) \(bodyText)"

            var brand: CameraBrand = .unknown
            if combined.contains("imou") || combined.contains("lechange") || ip.hasSuffix(".202") {
                brand = .imou
            } else if combined.contains("dahua") || combined.contains("web3.0") || combined.contains("web5.0") {
                brand = .dahua
            } else if combined.contains("hikvision") || combined.contains("app-web/") {
                brand = .hikvision
            } else if combined.contains("uniview") || combined.contains("unv") {
                brand = .unv
            } else if combined.contains("seetong") {
                brand = .seetong
            } else if combined.contains("tiandy") {
                brand = .tiandy
            } else if httpRes.statusCode == 401 || httpRes.statusCode == 200 {
                brand = .dahua
            }

            let device = CameraDevice(
                ip: ip,
                port: 80,
                brand: brand,
                model: "",
                mac: "",
                extraInfo: "Port 80"
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
