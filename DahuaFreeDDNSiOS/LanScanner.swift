import Foundation
import Network

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

    private var scanningQueue = DispatchQueue(label: "com.dahua.lanning", qos: .userInitiated, attributes: .concurrent)

    func startScan() {
        guard !isScanning else { return }
        
        DispatchQueue.main.async {
            self.isScanning = true
            self.progress = 0.05
            self.statusMessage = "Đang quét đa giao thức trong mạng LAN..."
            self.discoveredDevices.removeAll()
        }

        scanningQueue.async {
            let localIp = self.getLocalIPAddress()
            let subnetPrefix = self.getSubnetPrefix(from: localIp)

            // Step 1: Subnet HTTP Probe
            let group = DispatchGroup()
            let lock = NSLock()

            let totalIps = 254
            var completedCount = 0

            for i in 1...totalIps {
                let targetIp = "\(subnetPrefix).\(i)"
                group.enter()

                self.probeIpAddress(ip: targetIp) { device in
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
                    let currentProgress = 0.05 + (Float(completedCount) / Float(totalIps)) * 0.95
                    DispatchQueue.main.async {
                        self.progress = currentProgress
                    }
                    lock.unlock()
                    group.leave()
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

    private func probeIpAddress(ip: String, completion: @escaping (CameraDevice?) -> Void) {
        let ports = [80, 37777, 8000]
        var foundDevice: CameraDevice? = nil
        let innerGroup = DispatchGroup()

        for port in ports {
            if foundDevice != nil { break }

            let urlString = "http://\(ip):\(port)/cgi-bin/configManager.cgi?action=getConfig&name=MagicBox"
            guard let url = URL(string: urlString) else { continue }

            innerGroup.enter()
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 1.2

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer { innerGroup.leave() }
                
                if let httpRes = response as? HTTPURLResponse {
                    let serverHeader = (httpRes.allHeaderFields["Server"] as? String)?.lowercased() ?? ""
                    let wwwAuth = (httpRes.allHeaderFields["WWW-Authenticate"] as? String)?.lowercased() ?? ""
                    let bodyText = String(data: data ?? Data(), encoding: .utf8)?.lowercased() ?? ""

                    if httpRes.statusCode == 401 || httpRes.statusCode == 200 {
                        var brand: CameraBrand = .unknown
                        var model = ""

                        if bodyText.contains("imou") || bodyText.contains("lechange") || serverHeader.contains("imou") {
                            brand = .imou
                        } else if bodyText.contains("dahua") || serverHeader.contains("dahua") || wwwAuth.contains("dahua") || port == 37777 || bodyText.contains("table.magicbox") {
                            brand = .dahua
                        } else if serverHeader.contains("hikvision") || wwwAuth.contains("hikvision") || port == 8000 {
                            brand = .hikvision
                        } else if serverHeader.contains("uniview") || serverHeader.contains("unv") {
                            brand = .unv
                        } else if serverHeader.contains("seetong") {
                            brand = .seetong
                        } else if serverHeader.contains("tiandy") {
                            brand = .tiandy
                        } else if wwwAuth.contains("digest") || wwwAuth.contains("basic") {
                            brand = .dahua // Fallback default Dahua-compatible CGI
                        }

                        foundDevice = CameraDevice(
                            ip: ip,
                            port: port,
                            brand: brand,
                            model: model,
                            mac: "",
                            extraInfo: "Port \(port)"
                        )
                    }
                }
            }
            task.resume()
        }

        innerGroup.notify(queue: .global()) {
            completion(foundDevice)
        }
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
