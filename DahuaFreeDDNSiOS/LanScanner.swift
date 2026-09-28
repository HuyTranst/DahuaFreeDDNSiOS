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
            self.statusMessage = "Đang quét phát hiện Dahua, Imou & camera LAN..."
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
            sessionConfig.timeoutIntervalForRequest = 1.0
            sessionConfig.timeoutIntervalForResource = 1.0
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
        let ports = [80, 37777, 8000, 8080]
        var foundDevice: CameraDevice? = nil
        let innerGroup = DispatchGroup()

        for port in ports {
            if foundDevice != nil { break }

            guard let url = URL(string: "http://\(ip):\(port)/") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 1.0

            innerGroup.enter()
            let task = session.dataTask(with: request) { data, response, error in
                defer { innerGroup.leave() }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode > 0 || error == nil {
                    let httpRes = response as? HTTPURLResponse
                    let server = (httpRes?.allHeaderFields["Server"] as? String)?.lowercased() ?? ""
                    let auth = (httpRes?.allHeaderFields["WWW-Authenticate"] as? String)?.lowercased() ?? ""
                    let body = String(data: data ?? Data(), encoding: .utf8)?.lowercased() ?? ""
                    let combined = "\(server) \(auth) \(body)"

                    var brand: CameraBrand = .unknown
                    if combined.contains("imou") || combined.contains("lechange") {
                        brand = .imou
                    } else if combined.contains("dahua") || port == 37777 {
                        brand = .dahua
                    } else if combined.contains("hikvision") || port == 8000 {
                        brand = .hikvision
                    } else if combined.contains("uniview") || combined.contains("unv") {
                        brand = .unv
                    } else if combined.contains("seetong") {
                        brand = .seetong
                    } else if combined.contains("tiandy") {
                        brand = .tiandy
                    }

                    if foundDevice == nil && (statusCode > 0 || port == 37777) {
                        foundDevice = CameraDevice(
                            ip: ip,
                            port: port,
                            brand: brand,
                            model: "",
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
