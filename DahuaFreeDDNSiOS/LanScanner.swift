import Foundation
import Combine

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
        return self == .dahua || self == .imou
    }
}

struct CameraDevice: Identifiable, Hashable {
    let id = UUID()
    let ip: String
    let port: Int
    let brand: CameraBrand
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
            self.statusMessage = "Đang quét & phân biệt Dahua & Imou trong LAN..."
            self.discoveredDevices.removeAll()
        }

        scanQueue.async {
            let localIp = self.getLocalIPAddress()
            let subnetPrefix = self.getSubnetPrefix(from: localIp)

            let group = DispatchGroup()
            let lock = NSLock()
            let totalHosts = 254
            var completedCount = 0

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
                        if !self.discoveredDevices.contains(where: { $0.ip == dev.ip }) {
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
        // Probe 1: Dahua & Imou MagicBox CGI Endpoint
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

            // If /cgi-bin/configManager.cgi returns 401 or 200 -> It is Dahua or Imou!
            if statusCode == 401 || statusCode == 200 || bodyText.contains("table.magicbox") {
                // Secondary Probe: Query system info / deviceType to accurately distinguish Imou vs Dahua
                self.queryDeviceType(ip: ip, session: session, initialCombined: combined) { detectedBrand, modelName in
                    let device = CameraDevice(
                        ip: ip,
                        port: 80,
                        brand: detectedBrand,
                        model: modelName,
                        mac: "",
                        extraInfo: "CGI Verified (\(detectedBrand.rawValue))"
                    )
                    completion(device)
                }
                return
            }

            self.probeFallbackRoot(ip: ip, session: session, completion: completion)
        }
        task.resume()
    }

    private func queryDeviceType(ip: String, session: URLSession, initialCombined: String, completion: @escaping (CameraBrand, String) -> Void) {
        guard let url = URL(string: "http://\(ip):80/cgi-bin/magicBox.cgi?action=getSystemInfo") else {
            completion(self.determineBrand(text: initialCombined), "")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        session.dataTask(with: request) { data, response, _ in
            let text = String(data: data ?? Data(), encoding: .utf8)?.lowercased() ?? ""
            let fullCombined = "\(initialCombined) \(text)"

            let brand = self.determineBrand(text: fullCombined)

            var model = ""
            if let typeLine = text.components(separatedBy: .newlines).first(where: { $0.contains("devicetype") }) {
                model = typeLine.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            completion(brand, model)
        }.resume()
    }

    private func determineBrand(text: String) -> CameraBrand {
        let lower = text.lowercased()
        let isImou = lower.contains("imou") || lower.contains("lechange") ||
                     lower.contains("ranger") || lower.contains("cruiser") ||
                     lower.contains("rex") || lower.contains("cue") || lower.contains("verso") ||
                     lower.contains("ipc-a") || lower.contains("ipc-c") ||
                     lower.contains("ipc-f") || lower.contains("ipc-g") ||
                     lower.contains("ipc-k") || lower.contains("ipc-s") ||
                     lower.contains("ipc-t") || lower.contains("ipc-b")

        return isImou ? .imou : .dahua
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
            if combined.contains("imou") || combined.contains("lechange") {
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
