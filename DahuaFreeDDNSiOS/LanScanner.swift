import Foundation
import Network
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

            // Send UDP DHDiscover broadcast
            self.sendUDPDiscovery()

            let semaphore = DispatchSemaphore(value: 32)

            for host in 1...totalHosts {
                let targetIp = "\(subnetPrefix).\(host)"
                semaphore.wait()

                group.enter()
                DispatchQueue.global().async {
                    defer {
                        semaphore.signal()
                        group.leave()
                    }

                    if let device = self.probeDevice(ip: targetIp) {
                        lock.lock()
                        if !self.discoveredDevices.contains(where: { $0.ip == device.ip }) {
                            DispatchQueue.main.async {
                                self.discoveredDevices.append(device)
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

    private func probeDevice(ip: String) -> CameraDevice? {
        let is37777Open = isPortOpen(ip: ip, port: 37777, timeoutSec: 0.5)
        let is80Open = isPortOpen(ip: ip, port: 80, timeoutSec: 0.5)
        let is8000Open = isPortOpen(ip: ip, port: 8000, timeoutSec: 0.5)
        let is34567Open = isPortOpen(ip: ip, port: 34567, timeoutSec: 0.5)
        let is8080Open = isPortOpen(ip: ip, port: 8080, timeoutSec: 0.5)

        if !is37777Open && !is80Open && !is8000Open && !is34567Open && !is8080Open {
            return nil
        }

        var brand: CameraBrand = .unknown
        var extraBanner = ""

        if is37777Open {
            brand = .dahua
            let banner = checkHttpBanner(ip: ip, port: is80Open ? 80 : 8080)
            if banner.contains("imou") || banner.contains("lechange") {
                brand = .imou
            }
            extraBanner = "Port 37777 (Dahua/Imou)"
        } else if is8000Open {
            brand = .hikvision
            extraBanner = "Port 8000 (Hikvision SADP)"
        } else if is34567Open {
            brand = .seetong
            extraBanner = "Port 34567 (Seetong)"
        } else if is80Open || is8080Open {
            let port = is80Open ? 80 : 8080
            let banner = checkHttpBanner(ip: ip, port: port)
            if banner.contains("dahua") {
                brand = .dahua
            } else if banner.contains("imou") || banner.contains("lechange") {
                brand = .imou
            } else if banner.contains("hikvision") {
                brand = .hikvision
            } else if banner.contains("uniview") || banner.contains("unv") {
                brand = .unv
            } else if banner.contains("tiandy") {
                brand = .tiandy
            } else {
                brand = .unknown
            }
            extraBanner = "Port \(port)"
        }

        let primaryPort = is80Open ? 80 : (is37777Open ? 37777 : (is8080Open ? 8080 : 8000))
        return CameraDevice(
            ip: ip,
            port: primaryPort,
            brand: brand,
            model: "",
            mac: "",
            extraInfo: extraBanner
        )
    }

    private func isPortOpen(ip: String, port: Int32, timeoutSec: Double) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return false }

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return false }
        defer { close(sock) }

        var flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if res < 0 {
            if errno != EINPROGRESS { return false }
            var writefds = fd_set()
            FD_ZERO(&writefds)
            FD_SET(sock, &writefds)

            var tv = timeval(tv_sec: 0, tv_usec: suseconds_t(timeoutSec * 1_000_000))
            let selectRes = select(sock + 1, nil, &writefds, nil, &tv)
            if selectRes <= 0 { return false }

            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
            if err != 0 { return false }
        }
        return true
    }

    private func checkHttpBanner(ip: String, port: Int) -> String {
        guard let url = URL(string: "http://\(ip):\(port)/") else { return "" }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        var bannerText = ""
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpRes = response as? HTTPURLResponse {
                let server = (httpRes.allHeaderFields["Server"] as? String) ?? ""
                let auth = (httpRes.allHeaderFields["WWW-Authenticate"] as? String) ?? ""
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                bannerText = "\(server) \(auth) \(body)".lowercased()
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.2)
        return bannerText
    }

    private func sendUDPDiscovery() {
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
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    sendto(sock, ptr.baseAddress, data.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
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
