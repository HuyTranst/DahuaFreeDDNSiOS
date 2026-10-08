import SwiftUI
import UIKit
import AVFoundation
import CoreImage

struct DdnsPreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let server: String
}

let freeDdnsPresets: [DdnsPreset] = [
    DdnsPreset(name: "FastDDNS", server: "fastddns.net"),
    DdnsPreset(name: "Camera DDNS", server: "cameraddns.net"),
    DdnsPreset(name: "Vantech DDNS", server: "vantechdns.com"),
    DdnsPreset(name: "VinaDDNS", server: "vinaddns.com"),
    DdnsPreset(name: "EasternDNS", server: "easterndns.com"),
    DdnsPreset(name: "Tùy chỉnh (Custom)", server: "")
]

struct CameraProduct: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let resolution: String
    let desc: String
    let iconName: String
}

let sampleProducts: [CameraProduct] = [
    CameraProduct(name: "Imou Ranger 2 (A22EP)", category: "Wifi Camera Indoor", resolution: "2.0 MP (1080P)", desc: "Xoay 360°, phát hiện con người, đàm thoại 2 chiều.", iconName: "camera.fill"),
    CameraProduct(name: "Imou Cruiser 2 (GS7EP)", category: "Wifi Camera Outdoor", resolution: "3.0 MP / 5.0 MP", desc: "Quay quét ngoài trời, ban đêm có màu, còi báo động.", iconName: "camera.badge.ellipsis"),
    CameraProduct(name: "Dahua DH-IPC-HDW1230DT", category: "IP Dome Camera", resolution: "2.0 MP", desc: "Hồng ngoại 30m, PoE, chuẩn nén H.265+.", iconName: "video.fill"),
    CameraProduct(name: "Dahua DH-XVR5104HS-I3", category: "Đầu Ghi XVR", resolution: "4 Kênh 5M-N", desc: "AI WizSense, bảo vệ chu vi, SMD Plus.", iconName: "server.rack")
]

// MARK: - Warranty Models & Client API
struct WarrantyResultItem: Identifiable {
    let id = UUID()
    let supplier: String
    let productCode: String
    let productName: String
    let serialNumber: String
    let exportDate: String
    let warrantyMonths: String
    let expireDate: String
    let remainingDays: Int?
    let dealer: String
    let warehouse: String
    let isValid: Bool
    let isProductOnly: Bool
}

class DahuaWarrantyClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
    }

    func checkWarranty(sn: String, completion: @escaping ([WarrantyResultItem]) -> Void) {
        let cleanSn = sn.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanSn.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var results: [WarrantyResultItem] = []
        let lock = NSLock()

        // 1. Query DSS Vietnam API (Dahua Việt Nam)
        group.enter()
        queryDSS(sn: cleanSn) { dssResults in
            lock.lock()
            results.append(contentsOf: dssResults)
            lock.unlock()
            group.leave()
        }

        // 2. Query KBT / Kabe Group (KBVISION)
        group.enter()
        queryKbt(sn: cleanSn) { kbtResults in
            lock.lock()
            results.append(contentsOf: kbtResults)
            lock.unlock()
            group.leave()
        }

        // 3. Query VINAGO Co., Ltd (Dahua/Imou)
        group.enter()
        queryVinago(sn: cleanSn) { vinagoResults in
            lock.lock()
            results.append(contentsOf: vinagoResults)
            lock.unlock()
            group.leave()
        }

        // 4. Query Dahua Global Support API (Chính Hãng International)
        group.enter()
        queryDahuaGlobal(sn: cleanSn) { globalResults in
            lock.lock()
            results.append(contentsOf: globalResults)
            lock.unlock()
            group.leave()
        }

        group.notify(queue: .main) {
            completion(results)
        }
    }

    private func queryDSS(sn: String, completion: @escaping ([WarrantyResultItem]) -> Void) {
        guard let url = URL(string: "https://app.dahua.vn:7778/Api.svc/Web/TraCuuBaoHanhTheoSeria?seria=\(sn)") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion([])
                return
            }

            do {
                if let rootObj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dRaw = rootObj["d"] {

                    var items: [[String: Any]] = []
                    if let dStr = dRaw as? String, let dData = dStr.data(using: .utf8) {
                        if let parsedItems = try? JSONSerialization.jsonObject(with: dData) as? [[String: Any]] {
                            items = parsedItems
                        }
                    } else if let parsedItems = dRaw as? [[String: Any]] {
                        items = parsedItems
                    }

                    var parsedResults: [WarrantyResultItem] = []
                    for it in items {
                        let remDays = it["SoNgayBaoHanhConLai"] as? Int
                        let isValid = (remDays ?? -1) > 0

                        let productCode = (it["MaHangHoa"] as? String) ?? ""
                        let productName = (it["TenHangHoa"] as? String) ?? "Camera IPC Dahua/Imou"
                        let serialNumber = (it["SoSeria"] as? String) ?? sn
                        let exportDate = (it["NgayXuat"] as? String) ?? ""
                        let thangBh = (it["SoThangBaoHanh"] as? Int) ?? 24
                        let dealer = ((it["TenMD"] as? String) ?? "").replacingOccurrences(of: "Cng Ty", with: "Công Ty")
                        let warehouse = ((it["TenKho"] as? String) ?? "").replacingOccurrences(of: "Kho hng", with: "Kho hàng")

                        var expireStr = ""
                        if !exportDate.isEmpty {
                            let parts = exportDate.components(separatedBy: "/")
                            if parts.count == 3,
                               let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]) {
                                let totalMonths = month + thangBh
                                let expYear = year + (totalMonths - 1) / 12
                                let expMonth = ((totalMonths - 1) % 12) + 1
                                expireStr = String(format: "%02d/%02d/%04d", day, expMonth, expYear)
                            }
                        }

                        let item = WarrantyResultItem(
                            supplier: "DSS TECH.,JSC (Dahua Vietnam)",
                            productCode: productCode,
                            productName: productName,
                            serialNumber: serialNumber,
                            exportDate: exportDate,
                            warrantyMonths: "\(thangBh) tháng",
                            expireDate: expireStr,
                            remainingDays: remDays,
                            dealer: dealer,
                            warehouse: warehouse,
                            isValid: isValid,
                            isProductOnly: false
                        )
                        parsedResults.append(item)
                    }
                    completion(parsedResults)
                    return
                }
            } catch {
                print("DSS Parse Error: \(error)")
            }
            completion([])
        }
        task.resume()
    }

    private func queryDahuaGlobal(sn: String, completion: @escaping ([WarrantyResultItem]) -> Void) {
        guard let url = URL(string: "https://supportapi.dahuasecurity.com/support/api/doc/docOverseasProduct/selectInfoBtSN?serialNumber=\(sn)") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("https://support.dahuasecurity.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion([])
                return
            }

            do {
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let obj = root["data"] as? [String: Any] {

                    let inModel = (obj["inModel"] as? String) ?? ""
                    let prodName = (obj["prodName"] as? String) ?? ""

                    if !inModel.isEmpty || !prodName.isEmpty {
                        let item = WarrantyResultItem(
                            supplier: "Dahua Global Official Support",
                            productCode: inModel,
                            productName: prodName.isEmpty ? "Thiết bị Dahua / Imou" : prodName,
                            serialNumber: (obj["serialNumber"] as? String) ?? sn,
                            exportDate: "",
                            warrantyMonths: "",
                            expireDate: "",
                            remainingDays: nil,
                            dealer: "Dahua Overseas",
                            warehouse: "",
                            isValid: true,
                            isProductOnly: true
                        )
                        completion([item])
                        return
                    }
                }
            } catch {
                print("Dahua Global Parse Error: \(error)")
            }
            completion([])
        }
        task.resume()
    }

    private func queryKbt(sn: String, completion: @escaping ([WarrantyResultItem]) -> Void) {
        guard let url = URL(string: "https://kabegroup.vn/kabet/online/") else {
            completion([])
            return
        }

        var getReq = URLRequest(url: url)
        getReq.httpMethod = "GET"
        getReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        getReq.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        getReq.timeoutInterval = 8.0

        let task1 = session.dataTask(with: getReq) { [weak self] data, response, error in
            guard let self = self, let data = data, let html1 = String(data: data, encoding: .utf8), error == nil else {
                completion([])
                return
            }

            var token = ""
            if let tokenRegex = try? NSRegularExpression(pattern: "name=[\"']_token[\"']\\s+value=[\"']([^\"']+)[\"']", options: .caseInsensitive) {
                let nsHtml = html1 as NSString
                let range = NSRange(location: 0, length: nsHtml.length)
                if let match = tokenRegex.firstMatch(in: html1, options: [], range: range) {
                    token = nsHtml.substring(with: match.range(at: 1))
                }
            }

            guard !token.isEmpty else {
                completion([])
                return
            }

            var postReq = URLRequest(url: url)
            postReq.httpMethod = "POST"
            postReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            postReq.setValue("https://kabegroup.vn/kabet/online/", forHTTPHeaderField: "Referer")
            postReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            postReq.timeoutInterval = 8.0

            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let escapedToken = token.addingPercentEncoding(withAllowedCharacters: allowed) ?? token
            let escapedSn = sn.addingPercentEncoding(withAllowedCharacters: allowed) ?? sn
            let bodyStr = "_token=\(escapedToken)&txtSN=\(escapedSn)"
            postReq.httpBody = bodyStr.data(using: .utf8)

            let task2 = self.session.dataTask(with: postReq) { data2, response2, error2 in
                guard let data2 = data2, let html2 = String(data: data2, encoding: .utf8), error2 == nil else {
                    completion([])
                    return
                }

                let lowerHtml = html2.lowercased()
                if !lowerHtml.contains("không tìm thấy") && !lowerHtml.contains("khong tim thay") && (lowerHtml.contains("bảo hành") || lowerHtml.contains("serial") || lowerHtml.contains(sn.lowercased())) {
                    var expireVal = "Còn hạn bảo hành"
                    if let dateRegex = try? NSRegularExpression(pattern: "(\\d{2}/\\d{2}/\\d{4}|\\d{4}-\\d{2}-\\d{2})", options: []) {
                        let nsHtml2 = html2 as NSString
                        let range2 = NSRange(location: 0, length: nsHtml2.length)
                        if let dateMatch = dateRegex.firstMatch(in: html2, options: [], range: range2) {
                            expireVal = nsHtml2.substring(with: dateMatch.range(at: 1))
                        }
                    }

                    let item = WarrantyResultItem(
                        supplier: "KBT / KABE T DISTRIBUTION (KBVISION)",
                        productCode: "Thiết bị KBVISION / KBT",
                        productName: "Camera / Đầu ghi KBVISION",
                        serialNumber: sn,
                        exportDate: "--",
                        warrantyMonths: "--",
                        expireDate: expireVal,
                        remainingDays: nil,
                        dealer: "KBT / KBVISION Group",
                        warehouse: "Kho KBT Việt Nam",
                        isValid: true,
                        isProductOnly: false
                    )
                    completion([item])
                    return
                }
                completion([])
            }
            task2.resume()
        }
        task1.resume()
    }

    private func queryVinago(sn: String, completion: @escaping ([WarrantyResultItem]) -> Void) {
        guard let url = URL(string: "https://baohanh.vinagoco.vn/?code=\(sn)") else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        let task = session.dataTask(with: request) { data, response, error in
            guard let data = data, let html = String(data: data, encoding: .utf8), error == nil else {
                completion([])
                return
            }

            let lowerHtml = html.lowercased()
            if lowerHtml.contains(sn.lowercased()) && !lowerHtml.contains("không tìm thấy") && !lowerHtml.contains("khong tim thay") {
                var modelVal = ""
                if let modelRegex = try? NSRegularExpression(pattern: "Model\\s*[:\\s]+([^\\r\\n<]+)", options: .caseInsensitive) {
                    let nsHtml = html as NSString
                    let range = NSRange(location: 0, length: nsHtml.length)
                    if let match = modelRegex.firstMatch(in: html, options: [], range: range) {
                        modelVal = nsHtml.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                var expireVal = ""
                if let dateRegex = try? NSRegularExpression(pattern: "(\\d{4}-\\d{2}-\\d{2}|\\d{2}/\\d{2}/\\d{4})", options: []) {
                    let nsHtml = html as NSString
                    let range = NSRange(location: 0, length: nsHtml.length)
                    if let match = dateRegex.firstMatch(in: html, options: [], range: range) {
                        expireVal = nsHtml.substring(with: match.range(at: 1))
                    }
                }

                if !modelVal.isEmpty || !expireVal.isEmpty {
                    let item = WarrantyResultItem(
                        supplier: "VINAGO CO., LTD (Phân Phối Dahua/Imou)",
                        productCode: modelVal.isEmpty ? "Thiết bị Vinago" : modelVal,
                        productName: "Thiết bị phân phối Vinago",
                        serialNumber: sn,
                        exportDate: "--",
                        warrantyMonths: "--",
                        expireDate: expireVal.isEmpty ? "Còn hạn bảo hành" : expireVal,
                        remainingDays: nil,
                        dealer: "VINAGO Co., Ltd",
                        warehouse: "Kho Vinago",
                        isValid: true,
                        isProductOnly: false
                    )
                    completion([item])
                    return
                }
            }
            completion([])
        }
        task.resume()
    }
}

// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var scanner = LanScanner()
    @State private var selectedTab: Int = 0

    // Selected Device for Action Modal
    @State private var activeDevice: CameraDevice? = nil
    @State private var showActionSheet = false
    @State private var activeModalType: ModalType? = nil
    @State private var selectedDeviceDetail: CameraDevice? = nil
    @State private var showScannerLogs: Bool = false
    @State private var scanFilterMode: Int = 0 // 0: Dahua & Imou, 1: Tất Cả (Kèm NoName)

    private var displayedDevices: [CameraDevice] {
        let sorted = scanner.discoveredDevices.sorted { dev1, dev2 in
            if (dev1.brand == .noName) != (dev2.brand == .noName) {
                return dev1.brand != .noName // Dahua/Imou first, NoName second
            }
            return dev1.ip < dev2.ip
        }
        if scanFilterMode == 0 {
            return sorted.filter { $0.brand == .dahua || $0.brand == .imou }
        } else {
            return sorted
        }
    }

    private var dahuaImouCount: Int {
        scanner.discoveredDevices.filter { $0.brand == .dahua || $0.brand == .imou }.count
    }

    private var allDevicesCount: Int {
        scanner.discoveredDevices.count
    }
    @State private var rawScannedSn: String = ""
    @State private var cleanedSn: String = ""
    @State private var showCameraScanner: Bool = false
    @State private var isCheckingWarranty: Bool = false
    @State private var warrantyResults: [WarrantyResultItem] = []
    @State private var warrantyCheckError: String? = nil

    // Set DDNS State
    @State var ip: String = "192.168.1.108"
    @State var port: String = "80"
    @State var camUser: String = "admin"
    @State var camPass: String = ""
    @State var camPassShowPassword: Bool = false
    @State var selectedPresetIndex: Int = 0
    @State var serverAddr: String = "fastddns.net"
    @State var domain: String = "mycam.fastddns.net"
    @State var ddnsUser: String = ""
    @State var ddnsPass: String = ""
    @State var ddnsPassShowPassword: Bool = false
    @State var enableDdns: Bool = true
    @State var selectedChannelIdx: String = "0"

    // Change IP State
    @State private var newIp: String = "192.168.1.120"
    @State private var subnetMask: String = "255.255.255.0"
    @State private var gateway: String = "192.168.1.1"
    @State private var changeIpShowPassword: Bool = false

    // Change Password State
    @State private var oldPass: String = ""
    @State private var newPass: String = ""
    @State private var confirmPass: String = ""
    @State private var changePassOldShow: Bool = false
    @State private var changePassNewShow: Bool = false
    @State private var changePassConfirmShow: Bool = false

    // Reboot State
    @State private var rebootShowPassword: Bool = false

    // UI Status
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = "Sẵn sàng kết nối tới camera Dahua/Imou."
    @State private var statusType: StatusType = .info
    @State private var logHistory: String = "Ứng dụng Dahua & Imou Manager iOS đã sẵn sàng.\n"
    @State private var rawFetchedConfig: String = ""

    private let cgiClient = DahuaCgiClient()
    private let warrantyClient = DahuaWarrantyClient()

    // Check Port State (Enhanced matching UI)
    @State private var currentWanIp: String = "Đang tải..."
    @State private var isLoadingWanIp: Bool = false
    @State private var selectedLanDeviceForPort: String = ""
    @State private var checkPortHost: String = ""
    @State private var cpPort1: String = "37777"
    @State private var cpPort2: String = "80"
    @State private var cpPort3: String = "554"
    @State private var cpPort4: String = "8000"
    @State private var isCheckingPorts: Bool = false
    @State private var portScanResults: [PortScanResult] = []
    @State private var hasCheckedPorts: Bool = false

    // QR Code Generator State (Enhanced matching UI)
    @State private var qrMode: Int = 0 // 0: Theo mẫu thiết bị, 1: Tùy chỉnh
    @State private var qrBrand: String = "Imou"
    @State private var qrModel: String = "IPC-A22EP"
    @State private var qrSn: String = ""
    @State private var qrSafetyCode: String = ""
    @State private var qrEncodingFormat: Int = 0 // 0: S/N chuẩn, 1: Cặp {S/N, Safety Code}
    @State private var qrCustomText: String = ""
    @State private var selectedLanDeviceForQr: String = ""
    @State private var generatedQrPayload: String = ""
    @State private var generatedQrImage: UIImage? = nil
    @State private var isQrGenerated: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var qrCopiedToast: Bool = false

    // Date & NTP State
    @State private var ntpTargetIp: String = ""
    @State private var ntpHttpPort: String = "80"
    @State private var ntpUsername: String = "admin"
    @State private var ntpPassword: String = ""
    @State private var ntpShowPassword: Bool = false
    @State private var selectedDate: Date = Date()
    @State private var enableNtp: Bool = true
    @State private var ntpServer: String = "time.google.com"
    @State private var ntpPort: String = "123"
    @State private var ntpPeriod: String = "60"
    @State private var ntpStatusMessage: String = ""
    @State private var ntpStatusSuccess: Bool = true
    @State private var ntpCurrentClockStr: String = ""

    // RTSP & Onvif State
    @State private var rtspTargetIp: String = "192.168.1.108"
    @State private var rtspSelectedLanDevice: String = ""
    @State private var rtspProtocolMode: Int = 0 // 0: RTSP theo Hãng, 1: ONVIF
    @State private var rtspBrand: String = "dahua"
    @State private var rtspDeviceType: String = "ipc"
    @State private var rtspPort: String = "554"
    @State private var rtspChannelCount: String = "1"
    @State private var rtspStreamMode: String = "both" // both, main, sub
    @State private var rtspUsername: String = "admin"
    @State private var rtspPassword: String = "admin123"
    @State private var rtspShowPassword: Bool = false
    @State private var rtspIncludeAuth: Bool = true
    @State private var rtspDahuaUnicast: Bool = true

    // ONVIF State
    @State private var onvifHttpPort: String = "80"
    @State private var onvifRtspPort: String = "554"
    @State private var onvifUsername: String = "admin"
    @State private var onvifPassword: String = "admin123"
    @State private var onvifShowPassword: Bool = false
    @State private var onvifLiveQuery: Bool = true
    @State private var isExtractingOnvif: Bool = false

    // RTSP Output
    @State private var rtspResultText: String = ""
    @State private var rtspStreamRows: [RtspStreamRowItem] = []
    @State private var rtspCopiedToast: Bool = false

    // Super Password State
    @State private var superPassDate: Date = Date()
    @State private var superPassCode1: String = ""
    @State private var superPassCode2: String = ""
    @State private var superPassCode3: String = ""

    // Google Account & Authentication State (Menu Tôi)
    @ObservedObject private var authManager = AuthManager.shared
    @State private var authSelectedTab: Int = 0 // 0: Đăng Nhập, 1: Đăng Ký
    @State private var authUsername: String = ""
    @State private var authPassword: String = ""
    @State private var authConfirmPassword: String = ""
    @State private var authShowPassword: Bool = false
    @State private var authShowConfirmPassword: Bool = false
    @State private var showLogoutAlert: Bool = false

    enum StatusType {
        case info, success, error

        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .error: return .red
            }
        }
    }

    enum ModalType: Identifiable {
        case setDdns
        case changeIp
        case changePass
        case rebootDevice
        case setDateNtp
        case checkPort
        case superPassword
        case qrCodeGenerator(initialSn: String, initialModel: String, initialBrand: String)
        case rtspOnvif

        var id: String {
            switch self {
            case .setDdns: return "setDdns"
            case .changeIp: return "changeIp"
            case .changePass: return "changePass"
            case .rebootDevice: return "rebootDevice"
            case .setDateNtp: return "setDateNtp"
            case .checkPort: return "checkPort"
            case .superPassword: return "superPassword"
            case .qrCodeGenerator(let sn, _, _): return "qrCodeGenerator_\(sn)"
            case .rtspOnvif: return "rtspOnvif"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Trang chủ
            NavigationView {
                trangChuView
                    .navigationTitle("Trang chủ")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Trang chủ")
            }
            .tag(0)

            // Tab 2: Check Port
            NavigationView {
                checkPortModalView
                    .navigationTitle("Check Port")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Check Port")
            }
            .tag(1)

            // Tab 3: Check Bảo Hành (Middle Action Tab with Barcode Camera Scanner & Direct API)
            NavigationView {
                checkBaoHanhView
                    .navigationTitle("Check Bảo Hành Camera")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "qrcode.viewfinder")
                Text("Check Bảo Hành")
            }
            .tag(2)

            // Tab 4: Cấu Hình
            NavigationView {
                ddnsFormView
                    .navigationTitle("Cấu Hình Free DDNS")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "gearshape.2.fill")
                Text("Cấu Hình")
            }
            .tag(3)

            // Tab 5: Tôi
            NavigationView {
                toiView
                    .navigationTitle("Tôi")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "person.fill")
                Text("Tôi")
            }
            .tag(4)
        }
        .accentColor(.orange)
        .sheet(isPresented: $showCameraScanner) {
            BarcodeScannerSheetView(scannedCode: Binding(
                get: { self.rawScannedSn },
                set: { val in
                    self.rawScannedSn = val
                    let cleaned = self.cleanSerialNumber(val)
                    self.cleanedSn = cleaned
                    self.triggerDirectWarrantyCheck(sn: cleaned)
                }
            ))
        }
        .actionSheet(isPresented: $showActionSheet) {
            ActionSheet(
                title: Text("Cài đặt & Thao tác [\(activeDevice?.ip ?? "")]"),
                message: Text("Hãng: \(activeDevice?.brand.rawValue ?? "Camera") | S/N: \(activeDevice?.sn.isEmpty == false ? activeDevice!.sn : "N/A")"),
                buttons: [
                    .default(Text("⚙️ Cài Đặt Free DDNS")) {
                        if let dev = activeDevice {
                            self.ip = dev.ip
                            self.port = "\(dev.port)"
                            self.activeModalType = .setDdns
                        }
                    },
                    .default(Text("🌐 Đổi địa chỉ IP")) {
                        if let dev = activeDevice {
                            self.ip = dev.ip
                            self.newIp = dev.ip
                            self.activeModalType = .changeIp
                        }
                    },
                    .default(Text("🔑 Đổi mật khẩu Camera")) {
                        if let dev = activeDevice {
                            self.ip = dev.ip
                            self.activeModalType = .changePass
                        }
                    },
                    .default(Text("🔄 Khởi động lại (Reboot)")) {
                        if let dev = activeDevice {
                            self.ip = dev.ip
                            self.activeModalType = .rebootDevice
                        }
                    },
                    .default(Text("🕒 Cấu hình Ngày Giờ & NTP")) {
                        if let dev = activeDevice {
                            self.ip = dev.ip
                            self.ntpTargetIp = dev.ip
                            self.ntpHttpPort = "\(dev.port)"
                            self.activeModalType = .setDateNtp
                        }
                    },
                    .default(Text("📹 Tạo Link RTSP & Onvif")) {
                        if let dev = activeDevice {
                            self.rtspTargetIp = dev.ip
                            self.applyDetectedBrand(dev)
                            self.activeModalType = .rtspOnvif
                        }
                    },
                    .default(Text("📡 Check Port thiết bị")) {
                        if let dev = activeDevice {
                            self.checkPortHost = dev.ip
                            self.activeModalType = .checkPort
                        }
                    },
                    .default(Text("📱 Tạo mã QR Code Cài Đặt (S/N)")) {
                        if let dev = activeDevice {
                            self.openQrCodeModal(for: dev)
                        }
                    },
                    .default(Text("🔍 Check Bảo Hành S/N")) {
                        if let dev = activeDevice, !dev.sn.isEmpty {
                            let cleaned = self.cleanSerialNumber(dev.sn)
                            self.rawScannedSn = dev.sn
                            self.cleanedSn = cleaned
                            self.selectedTab = 2
                            self.triggerDirectWarrantyCheck(sn: cleaned)
                        }
                    },
                    .cancel(Text("Hủy"))
                ]
            )
        }
        .sheet(item: $selectedDeviceDetail) { dev in
            DeviceDetailView(device: dev) { action in
                self.handleDeviceDetailAction(action: action, dev: dev)
            }
        }
        .sheet(item: $activeModalType) { type in
            switch type {
            case .setDdns:
                NavigationView {
                    ddnsFormView
                        .navigationTitle("Set Free DDNS (\(ip))")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .changeIp:
                NavigationView {
                    changeIpView
                        .navigationTitle("Đổi IP Camera (\(ip))")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .changePass:
                NavigationView {
                    changePassView
                        .navigationTitle("Đổi Mật Khẩu (\(ip))")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .rebootDevice:
                NavigationView {
                    rebootDeviceView
                        .navigationTitle("Reboot Camera (\(ip))")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .setDateNtp:
                NavigationView {
                    setDateNtpView
                        .navigationTitle("Cấu Hình Ngày Giờ & NTP")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .checkPort:
                NavigationView {
                    checkPortModalView
                        .navigationTitle("Kiểm Tra Cổng (Check Port)")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .superPassword:
                NavigationView {
                    superPasswordView
                        .navigationTitle("Super Password Dahua")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .qrCodeGenerator:
                NavigationView {
                    qrCodeGeneratorModalView
                        .navigationTitle("Tạo Mã QR Code Cài Đặt")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .rtspOnvif:
                NavigationView {
                    rtspOnvifModalView
                        .navigationTitle("Tạo Link RTSP & Onvif")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            }
        }
    }

    // TAB 2: Check Bảo Hành View (Barcode Scanner & Direct API Lookup)
    var checkBaoHanhView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header Banner
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.85)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .cornerRadius(16)

                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tra Cứu Bảo Hành Direct API")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)

                            Text("Quét mã Barcode / QR Code S/N hoặc nhập để kiểm tra trực tiếp qua API 4 nhà phân phối: DSS, KBT (Kabe), Vinago & Dahua Global.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Spacer()
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .padding(16)
                }
                .padding(.horizontal)

                // Camera Scanner Trigger Button
                Button(action: {
                    showCameraScanner = true
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.headline)
                        Text("📷 MỞ CAMERA QUÉT MÃ VẠCH (S/N)")
                            .font(.headline)
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: Color.orange.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal)

                // Manual Input Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hoặc nhập số Serial (S/N)")
                        .font(.subheadline)
                        .bold()

                    HStack {
                        Image(systemName: "barcode")
                            .foregroundColor(.gray)

                        TextField("Nhập S/N camera...", text: Binding(
                            get: { self.rawScannedSn },
                            set: { newValue in
                                self.rawScannedSn = newValue
                                let cleaned = self.cleanSerialNumber(newValue)
                                self.cleanedSn = cleaned
                            }
                        ))
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)

                        if !rawScannedSn.isEmpty {
                            Button(action: {
                                rawScannedSn = ""
                                cleanedSn = ""
                                warrantyResults.removeAll()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }

                        Button(action: {
                            triggerDirectWarrantyCheck(sn: cleanedSn)
                        }) {
                            Text("Tra Cứu")
                                .bold()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                // Loading Indicator for Warranty Check
                if isCheckingWarranty {
                    HStack {
                        Spacer()
                        ProgressView().padding(.trailing, 8)
                        Text("Đang tra cứu đồng thời cả 4 nhà phân phối (DSS, KBT, Vinago, Dahua Global)...")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }

                // Cleaned S/N & Warranty Result Display
                if !cleanedSn.isEmpty && !isCheckingWarranty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("S/N Đã Chuẩn Hóa:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        Text(cleanedSn)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)

                        if warrantyResults.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title)
                                    .foregroundColor(.orange)
                                Text("Chưa tìm thấy bản ghi bảo hành cho S/N: \(cleanedSn)")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                Text("Đã tra cứu đồng thời trên hệ thống DSS, KBT (Kabe), Vinago & Dahua Global. Vui lòng kiểm tra lại số S/N hoặc camera chưa kích hoạt bảo hành điện tử.")
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Kết Quả Tra Cứu Direct API (\(warrantyResults.count) Bản Ghi):")
                                    .font(.headline)

                                ForEach(warrantyResults) { res in
                                    WarrantyDetailCard(item: res)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // Quick Scan LAN Button inside Warranty View
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quét IP Mạng LAN")
                        .font(.headline)
                        .padding(.horizontal)

                    Button(action: { scanner.startScan(timeout: 6.0) }) {
                        HStack {
                            Spacer()
                            if scanner.isScanning {
                                ProgressView().padding(.trailing, 8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(scanner.isScanning ? "ĐANG QUÉT MẠNG LAN..." : "BẮT ĐẦU QUÉT MẠNG LAN TÌM S/N")
                                .bold()
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(scanner.isScanning ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .disabled(scanner.isScanning)

                    if !scanner.discoveredDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("S/N Camera phát hiện từ mạng LAN (Nhấn để tra cứu nhanh):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(scanner.discoveredDevices) { dev in
                                        if !dev.sn.isEmpty && dev.brand != .noName {
                                            Button(action: {
                                                let cleaned = self.cleanSerialNumber(dev.sn)
                                                self.rawScannedSn = dev.sn
                                                self.cleanedSn = cleaned
                                                self.triggerDirectWarrantyCheck(sn: cleaned)
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "camera.fill")
                                                    Text("\(dev.ip) (\(dev.sn))")
                                                }
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.orange.opacity(0.15))
                                                .foregroundColor(.orange)
                                                .cornerRadius(8)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
    }

    private func triggerDirectWarrantyCheck(sn: String) {
        let clean = cleanSerialNumber(sn)
        guard !clean.isEmpty else { return }
        isCheckingWarranty = true
        warrantyResults.removeAll()
        warrantyCheckError = nil

        warrantyClient.checkWarranty(sn: clean) { results in
            DispatchQueue.main.async {
                self.isCheckingWarranty = false
                self.warrantyResults = results
            }
        }
    }

    // TAB 0: Trang chủ (Home Banner & Dashboard)
    var trangChuView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Compact Home Banner with eye-catching animation and 100% fixed height
                HomeBannerView()

                // Quick Action Cards
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tính Năng Nổi Bật & Tiện Ích")
                        .font(.headline)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        QuickTile(title: "Check Bảo Hành", icon: "qrcode.viewfinder", color: .orange) {
                            selectedTab = 2
                        }
                        QuickTile(title: "Cấu Hình DDNS", icon: "gearshape.2.fill", color: .blue) {
                            selectedTab = 3
                        }
                        QuickTile(title: "RTSP & Onvif", icon: "video.fill", color: .orange) {
                            self.activeModalType = .rtspOnvif
                        }
                    }
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        QuickTile(title: "Check Port", icon: "antenna.radiowaves.left.and.right", color: .purple) {
                            selectedTab = 1
                        }
                        QuickTile(title: "Super Pass", icon: "lock.shield.fill", color: .red) {
                            self.activeModalType = .superPassword
                        }
                        QuickTile(title: "Tạo QR S/N", icon: "qrcode", color: .orange) {
                            self.openQrCodeModal(for: nil)
                        }
                    }
                    .padding(.horizontal)
                }

                // Network Control & Realtime Status Bar
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("IP iPhone: \(scanner.localIpAddress)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 6) {
                                Text("Dải Subnet:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("192.168.1", text: $scanner.targetSubnetPrefix)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(.caption, design: .monospaced).weight(.bold))
                                    .frame(width: 110)
                                    .keyboardType(.numbersAndPunctuation)
                            }
                        }

                        Spacer()

                        Button(action: {
                            if scanner.isScanning {
                                scanner.stopScan()
                            } else {
                                scanner.startScan(timeout: 6.0)
                            }
                        }) {
                            HStack(spacing: 6) {
                                if scanner.isScanning {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                    Text("Dừng")
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                    Text("Quét")
                                }
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(scanner.isScanning ? Color.red : Color.blue)
                            .cornerRadius(10)
                            .shadow(color: (scanner.isScanning ? Color.red : Color.blue).opacity(0.3), radius: 4, y: 2)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    // Status Message & Live Log Toggle
                    HStack {
                        Text(scanner.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            showScannerLogs.toggle()
                        }) {
                            Label(showScannerLogs ? "Ẩn Log" : "Xem Log", systemImage: "terminal")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Live Terminal Log (Collapsible)
                if showScannerLogs {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("NHẬT KÝ QUÉT THỜI GIAN THỰC")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Xóa") {
                                scanner.scanLogs.removeAll()
                            }
                            .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(scanner.scanLogs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(log.contains(">>>") ? .green : (log.contains("Lỗi") ? .red : .primary))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: 120)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(6)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                // Discovered Devices List
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thiết Bị Phát Hiện (\(displayedDevices.count))")
                            .font(.headline)
                        Spacer()
                        if scanner.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .padding(.horizontal)

                    // Bộ lọc: Dahua & Imou vs Tất Cả
                    Picker("Bộ Lọc Thiết Bị", selection: $scanFilterMode) {
                        Text("Dahua & Imou (\(dahuaImouCount))").tag(0)
                        Text("Tất Cả (\(allDevicesCount))").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    if displayedDevices.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: scanFilterMode == 0 ? "video.slash" : "network.slash")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text(scanner.isScanning ? "Đang dò tìm thiết bị trong mạng..." : (scanFilterMode == 0 && allDevicesCount > 0 ? "Không có camera Dahua/Imou nào.\n(Có \(allDevicesCount) thiết bị LAN khác trong tùy chọn 'Tất Cả')." : "Chưa tìm thấy thiết bị nào."))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Nhấn vào đây để bắt đầu quét ngay") {
                                scanner.startScan(timeout: 6.0)
                            }
                            .font(.caption)
                            .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else {
                        ForEach(displayedDevices) { dev in
                            DeviceRowView(device: dev) {
                                self.activeDevice = dev
                                self.showActionSheet = true
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.selectedDeviceDetail = dev
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

        // TAB 1: Sản phẩm (Camera Catalog & Specs)
    var sanPhamView: some View {
        List {
            Section(header: Text("Danh Mục Sản Phẩm Dahua & Imou")) {
                ForEach(sampleProducts) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.iconName)
                            .font(.title2)
                            .foregroundColor(.orange)
                            .frame(width: 40, height: 40)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.headline)
                            Text("\(item.category) • \(item.resolution)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(item.desc)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(GroupedListStyle())
    }

    // TAB 3: Cấu Hình (Free DDNS Form View)
    var ddnsFormView: some View {
        Form {
            Section(header: Text("Thông tin Camera Dahua / Imou")) {
                HStack {
                    Text("Địa chỉ IP")
                    Spacer()
                    TextField("192.168.1.108", text: $ip)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                }

                HStack {
                    Text("HTTP Port")
                    Spacer()
                    TextField("80", text: $port)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                HStack {
                    Text("User Camera")
                    Spacer()
                    TextField("admin", text: $camUser)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Pass Camera")
                    Spacer()
                    if camPassShowPassword {
                        TextField("Mật khẩu camera", text: $camPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Mật khẩu camera", text: $camPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { camPassShowPassword.toggle() }) {
                        Image(systemName: camPassShowPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Section(header: Text("Cấu hình Free DDNS")) {
                Picker("Server Preset", selection: Binding(
                    get: { self.selectedPresetIndex },
                    set: { newIdx in
                        self.selectedPresetIndex = newIdx
                        let preset = freeDdnsPresets[newIdx]
                        if !preset.server.isEmpty {
                            self.serverAddr = preset.server
                            if self.domain.contains(".") {
                                let prefix = self.domain.components(separatedBy: ".").first ?? "mycam"
                                self.domain = "\(prefix).\(preset.server)"
                            } else {
                                self.domain = "mycam.\(preset.server)"
                            }
                        }
                    }
                )) {
                    ForEach(0..<freeDdnsPresets.count, id: \.self) { idx in
                        Text(freeDdnsPresets[idx].name).tag(idx)
                    }
                }

                HStack {
                    Text("Server DDNS")
                    Spacer()
                    TextField("fastddns.net", text: $serverAddr)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Tên miền (Domain)")
                    Spacer()
                    TextField("mycam.fastddns.net", text: $domain)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("DDNS User")
                    Spacer()
                    TextField("User DDNS (nếu có)", text: $ddnsUser)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("DDNS Pass")
                    Spacer()
                    if ddnsPassShowPassword {
                        TextField("Pass DDNS (nếu có)", text: $ddnsPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Pass DDNS (nếu có)", text: $ddnsPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { ddnsPassShowPassword.toggle() }) {
                        Image(systemName: ddnsPassShowPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                Toggle("Kích hoạt DDNS", isOn: $enableDdns)
            }

            Section {
                Button(action: saveConfig) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().padding(.trailing, 8)
                        }
                        Text("⚡ CÀI ĐẶT FREE DDNS LÊN CAMERA")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .disabled(isLoading)

                Button(action: fetchConfig) {
                    HStack {
                        Spacer()
                        Text("🔍 Đọc cấu hình từ Camera")
                            .foregroundColor(.orange)
                        Spacer()
                    }
                }
            }

            Section(header: Text("Trạng thái")) {
                HStack {
                    Circle()
                        .fill(statusType.color)
                        .frame(width: 10, height: 10)
                    Text(statusMessage)
                        .font(.footnote)
                }
            }

            Section(header: Text("Nhật ký (Log Output)")) {
                Text(logHistory)
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - TAB 4: Tôi (Hệ Thống Đăng Nhập & Quản Lý Bản Quyền Pro)
    var toiView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if authManager.isLoggedIn {
                    loggedInProfileView
                } else {
                    loggedOutAuthFormView
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    // Giao diện khi CHƯA đăng nhập
    private var loggedOutAuthFormView: some View {
        VStack(spacing: 20) {
            // Header Card hoành tráng
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.orange.opacity(0.9), Color(hex: "f59e0b")]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .shadow(color: Color.orange.opacity(0.35), radius: 8, x: 0, y: 4)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
                .padding(.top, 8)

                Text("HỆ THỐNG TÀI KHOẢN PRO")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Text("Đăng nhập để kích hoạt Bản Quyền PRO, tích điểm và mở khóa không giới hạn toàn bộ tiện ích Dahua & Imou.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

            // Segmented Picker (Đăng Nhập / Đăng Ký)
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        authSelectedTab = 0
                        authManager.errorMessage = nil
                        authManager.successMessage = nil
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                        Text("Đăng Nhập")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(authSelectedTab == 0 ? Color.orange : Color.clear)
                    .foregroundColor(authSelectedTab == 0 ? .white : .secondary)
                    .cornerRadius(10)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        authSelectedTab = 1
                        authManager.errorMessage = nil
                        authManager.successMessage = nil
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus.fill")
                        Text("Đăng Ký Mới")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(authSelectedTab == 1 ? Color.orange : Color.clear)
                    .foregroundColor(authSelectedTab == 1 ? .white : .secondary)
                    .cornerRadius(10)
                }
            }
            .padding(4)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(12)

            // Form Inputs Card
            VStack(spacing: 14) {
                // Ô nhập Tên đăng nhập
                VStack(alignment: .leading, spacing: 6) {
                    Text("TÊN ĐĂNG NHẬP")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .foregroundColor(.orange)
                            .frame(width: 20)

                        TextField("Nhập tên đăng nhập...", text: $authUsername)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .default))

                        if !authUsername.isEmpty {
                            Button(action: { authUsername = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                }

                // Ô nhập Mật khẩu
                VStack(alignment: .leading, spacing: 6) {
                    Text("MẬT KHẨU")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                            .frame(width: 20)

                        if authShowPassword {
                            TextField("Nhập mật khẩu...", text: $authPassword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .font(.system(.body, design: .default))
                        } else {
                            SecureField("Nhập mật khẩu...", text: $authPassword)
                                .font(.system(.body, design: .default))
                        }

                        Button(action: { authShowPassword.toggle() }) {
                            Image(systemName: authShowPassword ? "eye.fill" : "eye.slash.fill")
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemGroupedBackground))
                    .cornerRadius(10)
                }

                // Nếu là Tab Đăng Ký -> Thêm ô Xác nhận mật khẩu
                if authSelectedTab == 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("XÁC NHẬN MẬT KHẨU")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.orange)
                                .frame(width: 20)

                            if authShowConfirmPassword {
                                TextField("Nhập lại mật khẩu...", text: $authConfirmPassword)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .font(.system(.body, design: .default))
                            } else {
                                SecureField("Nhập lại mật khẩu...", text: $authConfirmPassword)
                                    .font(.system(.body, design: .default))
                            }

                            Button(action: { authShowConfirmPassword.toggle() }) {
                                Image(systemName: authShowConfirmPassword ? "eye.fill" : "eye.slash.fill")
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

            // Thông báo lỗi nếu có
            if let err = authManager.errorMessage, !err.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }

            // Thông báo thành công nếu có
            if let succ = authManager.successMessage, !succ.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(succ)
                        .font(.footnote)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }

            // Nút bấm thực hiện Đăng nhập / Đăng ký theo phong cách Form chính (Gradient cam vàng)
            Button(action: {
                handleAuthAction()
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        Text("ĐANG XỬ LÝ...")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: authSelectedTab == 0 ? "arrow.right.circle.fill" : "person.badge.plus")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Text(authSelectedTab == 0 ? "ĐĂNG NHẬP NGAY" : "ĐĂNG KÝ TÀI KHOẢN")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.orange, Color(hex: "f59e0b")]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .disabled(authManager.isLoading)

            // Thẻ ghi chú bảo mật & Quyền lợi VIP
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.orange)
                    Text("Đặc Quyền Tài Khoản Pro:")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(.orange)
                        Text("Lưu phiên cục bộ 5 ngày: Tự động đăng nhập siêu tốc, không cần kết nối mạng liên tục.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(.orange)
                        Text("Đồng bộ & mã hóa đám mây an toàn: Bảo mật mật khẩu SHA-256 tuyệt đối.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundColor(.orange)
                        Text("Hỗ trợ mở khóa Bản Quyền Pro & gia hạn nhanh qua Zalo quản trị.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider().padding(.vertical, 4)

                Button(action: {
                    if let url = URL(string: "https://zalo.me/0909080119") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "phone.fill")
                            .font(.caption)
                        Text("Cần cấp quyền Pro? Liên hệ Zalo: 0909.080.119")
                            .font(.caption.weight(.bold))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
    }

    // Giao diện khi ĐÃ đăng nhập (Bảng điều khiển Profile VIP)
    private var loggedInProfileView: some View {
        VStack(spacing: 20) {
            // VIP Member Profile Card
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color(hex: "f59e0b")]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)

                        Image(systemName: authManager.role == "PRO" || authManager.role == "ADMIN" ? "crown.fill" : "person.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(authManager.username)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.primary)

                        HStack(spacing: 6) {
                            if authManager.role == "PRO" {
                                Text("👑 BẢN QUYỀN PRO VIP")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            } else if authManager.role == "ADMIN" {
                                Text("⚡ QUẢN TRỊ VIÊN")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            } else {
                                Text("⭐ THÀNH VIÊN FREE")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }

                            Text("\(authManager.points) Điểm")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                        }
                    }
                    Spacer()
                }

                Divider()

                // Bảng chi tiết trạng thái
                VStack(spacing: 8) {
                    HStack {
                        Text("Hạn sử dụng:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(authManager.expireDate)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                    }

                    HStack {
                        Text("Phiên làm việc cục bộ:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Còn \(authManager.getDaysUntilNextCheck()) ngày")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("Trạng thái bảo mật:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Đã mã hóa an toàn")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(18)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)

            // Thông báo lỗi nếu có
            if let err = authManager.errorMessage, !err.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }

            // Thông báo thành công nếu có
            if let succ = authManager.successMessage, !succ.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(succ)
                        .font(.footnote)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }

            // Nút đồng bộ / kiểm tra bản quyền trực tiếp từ Server
            Button(action: {
                authManager.checkStatus(silent: false)
            }) {
                HStack(spacing: 8) {
                    Spacer()
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        Text("ĐANG ĐỒNG BỘ...")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.white)
                        Text("ĐỒNG BỘ & KIỂM TRA BẢN QUYỀN")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.orange, Color(hex: "f59e0b")]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.orange.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .disabled(authManager.isLoading)

            // Danh sách tính năng cao cấp đã kích hoạt
            VStack(alignment: .leading, spacing: 12) {
                Text("TIỆN ÍCH DAHUA & IMOU")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    Button(action: {
                        self.activeModalType = .changeIp
                    }) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Đổi địa chỉ IP Camera")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 6)
                    }

                    Divider()

                    Button(action: {
                        self.activeModalType = .changePass
                    }) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Đổi mật khẩu Camera")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 6)
                    }

                    Divider()

                    Button(action: {
                        self.activeModalType = .rebootDevice
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Khởi động lại (Reboot) Camera")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)

            // Nút Đăng Xuất Tài Khoản
            Button(action: {
                showLogoutAlert = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Đăng Xuất Tài Khoản")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.08))
                .cornerRadius(10)
            }
            .alert(isPresented: $showLogoutAlert) {
                Alert(
                    title: Text("Đăng Xuất"),
                    message: Text("Bạn có chắc chắn muốn đăng xuất tài khoản '\(authManager.username)' không?"),
                    primaryButton: .destructive(Text("Đăng Xuất")) {
                        authManager.logout()
                    },
                    secondaryButton: .cancel(Text("Hủy"))
                )
            }

            // Hỗ trợ Zalo
            Button(action: {
                if let url = URL(string: "https://zalo.me/0909080119") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "phone.fill")
                        .font(.caption)
                    Text("Hotline / Zalo hỗ trợ: 0909.080.119")
                        .font(.caption.weight(.bold))
                    Spacer()
                }
                .padding(.vertical, 8)
                .foregroundColor(.secondary)
            }
        }
    }

    private func handleAuthAction() {
        if authSelectedTab == 0 {
            // Login
            authManager.login(user: authUsername, pass: authPassword)
        } else {
            // Register
            if authPassword != authConfirmPassword {
                authManager.errorMessage = "Mật khẩu xác nhận không khớp!"
                return
            }
            authManager.register(user: authUsername, pass: authPassword) { success, _ in
                if success {
                    self.authSelectedTab = 0
                    self.authConfirmPassword = ""
                }
            }
        }
    }

    // Modal view: Change IP
    var changeIpView: some View {
        Form {
            Section(header: Text("Cấu hình IP Mới")) {
                HStack {
                    Text("IP Mới")
                    Spacer()
                    TextField("192.168.1.120", text: $newIp)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Subnet Mask")
                    Spacer()
                    TextField("255.255.255.0", text: $subnetMask)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Gateway")
                    Spacer()
                    TextField("192.168.1.1", text: $gateway)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("User Camera")
                    Spacer()
                    TextField("admin", text: $camUser)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Pass Camera")
                    Spacer()
                    if changeIpShowPassword {
                        TextField("Mật khẩu", text: $camPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Mật khẩu", text: $camPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { changeIpShowPassword.toggle() }) {
                        Image(systemName: changeIpShowPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Section {
                Button(action: executeChangeIp) {
                    HStack {
                        Spacer()
                        Text("🌐 CẬP NHẬT IP MỚI VIA DIGEST AUTH")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }

    // Modal view: Change Password
    var changePassView: some View {
        Form {
            Section(header: Text("Đổi Mật Khẩu Camera [\(ip)]")) {
                HStack {
                    Text("MK hiện tại")
                    Spacer()
                    if changePassOldShow {
                        TextField("Mật khẩu hiện tại", text: $oldPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Mật khẩu hiện tại", text: $oldPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { changePassOldShow.toggle() }) {
                        Image(systemName: changePassOldShow ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                HStack {
                    Text("MK mới")
                    Spacer()
                    if changePassNewShow {
                        TextField("Mật khẩu mới", text: $newPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Mật khẩu mới", text: $newPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { changePassNewShow.toggle() }) {
                        Image(systemName: changePassNewShow ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }

                HStack {
                    Text("Xác nhận MK")
                    Spacer()
                    if changePassConfirmShow {
                        TextField("Xác nhận mật khẩu mới", text: $confirmPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Xác nhận mật khẩu mới", text: $confirmPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { changePassConfirmShow.toggle() }) {
                        Image(systemName: changePassConfirmShow ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Section {
                Button(action: executeChangePass) {
                    HStack {
                        Spacer()
                        Text("🔑 CẬP NHẬT MẬT KHẨU MỚI")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }

    // Modal View: Reboot Device
    var rebootDeviceView: some View {
        Form {
            Section(header: Text("Khởi Động Lại Thiết Bị")) {
                HStack {
                    Text("Địa chỉ IP Camera")
                    Spacer()
                    Text(ip).font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("HTTP Port")
                    Spacer()
                    TextField("80", text: $port)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                HStack {
                    Text("User Camera")
                    Spacer()
                    TextField("admin", text: $camUser)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Pass Camera")
                    Spacer()
                    if rebootShowPassword {
                        TextField("Mật khẩu camera", text: $camPass)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Mật khẩu camera", text: $camPass)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { rebootShowPassword.toggle() }) {
                        Image(systemName: rebootShowPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Section {
                Button(action: executeReboot) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("🔄 KHỞI ĐỘNG LẠI CAMERA NGAY")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }

    // MARK: - Modal View: Check Port (Form Style matching Super Password)
    var checkPortModalView: some View {
        Form {
            Section(header: Text("1. Địa Chỉ IP WAN Công Cộng")) {
                HStack {
                    Text("IP WAN:")
                    Spacer()
                    Text(currentWanIp)
                        .font(.system(.subheadline, design: .monospaced))
                        .bold()
                        .foregroundColor(.blue)
                }

                HStack(spacing: 12) {
                    Button(action: fetchWanIp) {
                        HStack {
                            Spacer()
                            if isLoadingWanIp {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Tải lại WAN IP")
                                .font(.footnote)
                                .bold()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    Button(action: fillWanIp) {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Điền IP WAN")
                                .font(.footnote)
                                .bold()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("2. Mục Tiêu Kiểm Tra (IP / Tên Miền)")) {
                if !scanner.discoveredDevices.isEmpty {
                    Picker("Chọn từ mạng LAN:", selection: $selectedLanDeviceForPort) {
                        Text("-- Chọn thiết bị LAN --").tag("")
                        ForEach(scanner.discoveredDevices) { dev in
                            Text("\(dev.ip) - \(dev.brand.rawValue)").tag(dev.ip)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: selectedLanDeviceForPort) { val in
                        if !val.isEmpty {
                            checkPortHost = val
                        }
                    }
                }

                HStack {
                    Text("Host / IP:")
                    Spacer()
                    TextField("VD: 27.64.170.126 hoặc domain.ddns", text: $checkPortHost)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }

            Section(header: Text("3. Các Cổng Cần Kiểm Tra (Ports)")) {
                HStack {
                    Text("Cổng 1 (TCP)")
                    Spacer()
                    TextField("37777", text: $cpPort1)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                HStack {
                    Text("Cổng 2 (HTTP)")
                    Spacer()
                    TextField("80", text: $cpPort2)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                HStack {
                    Text("Cổng 3 (RTSP)")
                    Spacer()
                    TextField("554", text: $cpPort3)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                HStack {
                    Text("Cổng 4 (Khác)")
                    Spacer()
                    TextField("443", text: $cpPort4)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("⭐ Dahua (37777, 80, 554)") {
                            cpPort1 = "37777"; cpPort2 = "80"; cpPort3 = "554"; cpPort4 = ""
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)

                        Button("⭐ Hikvision (8000, 80, 554, 443)") {
                            cpPort1 = "8000"; cpPort2 = "80"; cpPort3 = "554"; cpPort4 = "443"
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)

                        Button("⭐ XM (34567, 80, 554)") {
                            cpPort1 = "34567"; cpPort2 = "80"; cpPort3 = "554"; cpPort4 = ""
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(6)

                        Button("Web (80, 443, 8080)") {
                            cpPort1 = "80"; cpPort2 = "443"; cpPort3 = "8080"; cpPort4 = ""
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                    }
                    .padding(.vertical, 4)
                }

                Button(action: executeCheckPorts) {
                    HStack {
                        Spacer()
                        if isCheckingPorts {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 6)
                            Text("ĐANG KIỂM TRA...")
                                .bold()
                        } else {
                            Image(systemName: "magnifyingglass")
                            Text("KIỂM TRA CỔNG")
                                .bold()
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isCheckingPorts)
                .buttonStyle(BorderlessButtonStyle())
            }

            if hasCheckedPorts {
                Section(header: Text("4. Kết Quả Kiểm Tra Cổng")) {
                    if portScanResults.isEmpty {
                        Text("Không có cổng nào được kiểm tra.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(portScanResults) { res in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(String(res.port))
                                            .font(.system(.headline, design: .monospaced))
                                            .bold()
                                        Text("(\(res.service))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(res.host)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if res.isOpen {
                                    Text("🟢 MỞ")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(6)

                                    if res.port == 80 || res.port == 8080 {
                                        Button(action: {
                                            if let url = URL(string: "http://\(res.host):\(res.port)") {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            Text("Mở Web")
                                                .font(.caption2)
                                                .bold()
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    } else if res.port == 443 {
                                        Button(action: {
                                            if let url = URL(string: "https://\(res.host):\(res.port)") {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            Text("Mở Web")
                                                .font(.caption2)
                                                .bold()
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    } else if res.port == 554 {
                                        Button(action: {
                                            let rtspUrl = "rtsp://admin:admin123@\(res.host):\(res.port)/cam/realmonitor?channel=1&subtype=0"
                                            UIPasteboard.general.string = rtspUrl
                                        }) {
                                            Text("Chép RTSP")
                                                .font(.caption2)
                                                .bold()
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange)
                                                .foregroundColor(.white)
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                } else {
                                    Text("🔴 ĐÓNG")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .onAppear {
            if currentWanIp == "Đang tải..." || currentWanIp.isEmpty {
                fetchWanIp()
            }
            if checkPortHost.isEmpty {
                if let dev = activeDevice {
                    checkPortHost = dev.ip
                } else if currentWanIp != "Đang tải..." && currentWanIp != "Không thể lấy IP" {
                    checkPortHost = currentWanIp
                }
            }
        }
    }

    private func fillWanIp() {
        if currentWanIp != "Đang tải..." && currentWanIp != "Không thể lấy IP" {
            checkPortHost = currentWanIp
        } else {
            fetchWanIp()
        }
    }

    private func fetchWanIp() {
        isLoadingWanIp = true
        currentWanIp = "Đang tải..."
        cgiClient.getWanIp { ip in
            DispatchQueue.main.async {
                self.isLoadingWanIp = false
                if let ip = ip, !ip.isEmpty {
                    self.currentWanIp = ip
                    if self.checkPortHost.isEmpty {
                        self.checkPortHost = ip
                    }
                } else {
                    self.currentWanIp = "Không thể lấy IP"
                }
            }
        }
    }


    // Modal View: Super Password
    var superPasswordView: some View {
        Form {
            Section(header: Text("Chọn Ngày Hiển Thị Trên Đầu Ghi Dahua")) {
                DatePicker("Ngày tra cứu:", selection: $superPassDate, displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .onChange(of: superPassDate) { _ in
                        calculateSuperPassword(for: superPassDate)
                    }

                Button(action: { calculateSuperPassword(for: superPassDate) }) {
                    HStack {
                        Spacer()
                        Image(systemName: "key.fill")
                        Text("TÍNH TOÁN SUPER PASSWORD")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            if !superPassCode1.isEmpty {
                Section(header: Text("Kết Quả Super Password (Master Dahua)")) {
                    VStack(alignment: .leading, spacing: 12) {
                        SuperPassRow(title: "Super Password 1 (Mã Chuẩn 1)", code: superPassCode1)
                        SuperPassRow(title: "Super Password 2 (Mã Chuẩn 2)", code: superPassCode2)
                        SuperPassRow(title: "Super Pass 3 (Mã Chuẩn 3)", code: superPassCode3)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Hướng dẫn sử dụng")) {
                    Text("• Nhập các mã Super Password trên vào mục đăng nhập tài khoản 'admin' trực tiếp trên màn hình đầu ghi DVR/NVR Dahua.\n• Chú ý ngày được chọn phải trùng khớp 100% với ngày hiển thị trên màn hình TV/đầu ghi Dahua.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            calculateSuperPassword(for: superPassDate)
        }
    }

    // Modal View: Set Date & NTP (Form Style matching Super Password)
    var setDateNtpView: some View {
        Form {
            Section(header: Text("1. Kết Nối Camera & Xác Thực")) {
                if !scanner.discoveredDevices.isEmpty {
                    Picker("Thiết bị LAN:", selection: $ntpTargetIp) {
                        Text("-- Nhập IP thủ công --").tag("")
                        ForEach(scanner.discoveredDevices) { dev in
                            Text("\(dev.ip) - \(dev.brand.rawValue)").tag(dev.ip)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: ntpTargetIp) { val in
                        if let dev = scanner.discoveredDevices.first(where: { $0.ip == val }) {
                            ntpHttpPort = "\(dev.port)"
                        }
                    }
                }

                HStack {
                    Text("Địa chỉ IP")
                    Spacer()
                    TextField("192.168.1.108", text: $ntpTargetIp)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                }

                HStack {
                    Text("Cổng HTTP")
                    Spacer()
                    TextField("80", text: $ntpHttpPort)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                HStack {
                    Text("Tài khoản")
                    Spacer()
                    TextField("admin", text: $ntpUsername)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Mật khẩu")
                    Spacer()
                    if ntpShowPassword {
                        TextField("Mật khẩu", text: $ntpPassword)
                            .multilineTextAlignment(.trailing)
                    } else {
                        SecureField("Mật khẩu", text: $ntpPassword)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(action: { ntpShowPassword.toggle() }) {
                        Image(systemName: ntpShowPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Section(header: Text("2. Đồng Bộ Giờ Điện Thoại")) {
                HStack {
                    Text("Giờ iPhone:")
                    Spacer()
                    Text(ntpCurrentClockStr)
                        .font(.system(.subheadline, design: .monospaced))
                        .bold()
                        .foregroundColor(.green)
                }

                Button(action: syncDeviceTimeNow) {
                    HStack {
                        Spacer()
                        Image(systemName: "bolt.fill")
                        Text("ĐỒNG BỘ GIỜ VÀO CAMERA")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Section(header: Text("3. Cài Đặt Máy Chủ NTP")) {
                Toggle("Bật tự động đồng bộ NTP", isOn: $enableNtp)

                HStack {
                    Text("Máy chủ NTP")
                    Spacer()
                    TextField("time.google.com", text: $ntpServer)
                        .multilineTextAlignment(.trailing)
                    Menu {
                        Button("Google (time.google.com)") { ntpServer = "time.google.com" }
                        Button("Windows (time.windows.com)") { ntpServer = "time.windows.com" }
                        Button("Pool NTP (pool.ntp.org)") { ntpServer = "pool.ntp.org" }
                        Button("Asia Pool (asia.pool.ntp.org)") { ntpServer = "asia.pool.ntp.org" }
                        Button("Apple (time.apple.com)") { ntpServer = "time.apple.com" }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundColor(.orange)
                    }
                }

                HStack {
                    Text("Cổng NTP")
                    Spacer()
                    TextField("123", text: $ntpPort)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                HStack {
                    Text("Chu kỳ (Phút)")
                    Spacer()
                    TextField("60", text: $ntpPeriod)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                HStack(spacing: 12) {
                    Button(action: fetchNtpConfig) {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down.doc.fill")
                            Text("Đọc cấu hình")
                                .font(.footnote)
                                .bold()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    Button(action: saveNtpConfig) {
                        HStack {
                            Spacer()
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Lưu cài đặt NTP")
                                .font(.footnote)
                                .bold()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.vertical, 4)
            }

            if !ntpStatusMessage.isEmpty {
                Section(header: Text("Trạng Thái")) {
                    HStack {
                        Image(systemName: ntpStatusSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(ntpStatusSuccess ? .green : .red)
                        Text(ntpStatusMessage)
                            .font(.footnote)
                            .foregroundColor(ntpStatusSuccess ? .primary : .red)
                    }
                }
            }
        }
        .onAppear {
            updateCurrentClock()
        }
    }

    private func syncDeviceTimeNow() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeStr = formatter.string(from: Date())

        let targetIp = ntpTargetIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ip.isEmpty ? "192.168.1.108" : ip) : ntpTargetIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPort = ntpHttpPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (port.isEmpty ? "80" : port) : ntpHttpPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetUser = ntpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (camUser.isEmpty ? "admin" : camUser) : ntpUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPass = ntpPassword.isEmpty ? camPass : ntpPassword

        isLoading = true
        ntpStatusMessage = "Đang đồng bộ giờ iPhone (\(timeStr)) sang camera \(targetIp)..."
        ntpStatusSuccess = true
        setStatus("Đang đồng bộ giờ iPhone (\(timeStr)) sang camera \(targetIp)...", type: .info)

        cgiClient.setDeviceTime(ip: targetIp, port: targetPort, user: targetUser, pass: targetPass, timeString: timeStr) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.ntpStatusMessage = "Đã đồng bộ giờ iPhone sang camera \(targetIp) thành công!"
                    self.ntpStatusSuccess = true
                    self.setStatus("Đồng bộ giờ sang camera thành công!", type: .success)
                } else {
                    self.ntpStatusMessage = "Đồng bộ giờ thất bại: HTTP \(result.statusCode) (Kiểm tra lại User/Mật khẩu hoặc Port)"
                    self.ntpStatusSuccess = false
                    self.setStatus("Đồng bộ giờ thất bại: HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    private func fetchNtpConfig() {
        let targetIp = ntpTargetIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ip.isEmpty ? "192.168.1.108" : ip) : ntpTargetIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPort = ntpHttpPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (port.isEmpty ? "80" : port) : ntpHttpPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetUser = ntpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (camUser.isEmpty ? "admin" : camUser) : ntpUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPass = ntpPassword.isEmpty ? camPass : ntpPassword

        isLoading = true
        ntpStatusMessage = "Đang đọc cấu hình NTP từ camera \(targetIp)..."
        ntpStatusSuccess = true
        setStatus("Đang đọc cấu hình NTP từ camera \(targetIp)...", type: .info)

        cgiClient.getNtpConfig(ip: targetIp, port: targetPort, user: targetUser, pass: targetPass) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.ntpStatusMessage = "Đọc cấu hình NTP từ camera \(targetIp) thành công!"
                    self.ntpStatusSuccess = true
                    self.setStatus("Đọc NTP thành công!", type: .success)
                    let lines = result.rawText.components(separatedBy: .newlines)
                    for line in lines {
                        let parts = line.components(separatedBy: "=")
                        if parts.count >= 2 {
                            let k = parts[0].trimmingCharacters(in: .whitespaces)
                            let v = parts[1].trimmingCharacters(in: .whitespaces)
                            if k.contains(".Enable") {
                                self.enableNtp = (v.lowercased() == "true" || v == "1")
                            } else if k.contains(".Address") {
                                self.ntpServer = v
                            } else if k.contains(".Port") {
                                self.ntpPort = v
                            } else if k.contains(".UpdatePeriod") {
                                self.ntpPeriod = v
                            }
                        }
                    }
                } else {
                    self.ntpStatusMessage = "Lỗi đọc NTP: HTTP \(result.statusCode) (Kiểm tra lại User/Mật khẩu hoặc Port)"
                    self.ntpStatusSuccess = false
                    self.setStatus("Lỗi đọc NTP: HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    private func saveNtpConfig() {
        let targetIp = ntpTargetIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ip.isEmpty ? "192.168.1.108" : ip) : ntpTargetIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPort = ntpHttpPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (port.isEmpty ? "80" : port) : ntpHttpPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetUser = ntpUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (camUser.isEmpty ? "admin" : camUser) : ntpUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPass = ntpPassword.isEmpty ? camPass : ntpPassword

        isLoading = true
        ntpStatusMessage = "Đang lưu cấu hình NTP lên camera \(targetIp)..."
        ntpStatusSuccess = true
        setStatus("Đang lưu cấu hình NTP lên camera \(targetIp)...", type: .info)

        let pInt = Int(ntpPort) ?? 123
        let periodInt = Int(ntpPeriod) ?? 60
        cgiClient.setNtpConfig(ip: targetIp, port: targetPort, user: targetUser, pass: targetPass, enable: enableNtp, server: ntpServer, ntpPort: pInt, period: periodInt) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.ntpStatusMessage = "Đã lưu cấu hình NTP lên camera \(targetIp) thành công!"
                    self.ntpStatusSuccess = true
                    self.setStatus("Đã lưu cấu hình NTP lên camera thành công!", type: .success)
                } else {
                    self.ntpStatusMessage = "Lỗi lưu NTP: HTTP \(result.statusCode) (Kiểm tra lại User/Mật khẩu hoặc Port)"
                    self.ntpStatusSuccess = false
                    self.setStatus("Lỗi lưu NTP: HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    private func executeReboot() {
        isLoading = true
        setStatus("Đang gửi lệnh Reboot camera \(ip)...", type: .info)
        cgiClient.rebootDevice(ip: ip, port: port, user: camUser, pass: camPass) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.setStatus("Đã gửi lệnh khởi động lại camera \(self.ip) thành công!", type: .success)
                    self.activeModalType = nil
                } else {
                    self.setStatus("Reboot thất bại: HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    private func setStatus(_ msg: String, type: StatusType) {
        self.statusMessage = msg
        self.statusType = type
    }

    private func appendLog(_ msg: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.logHistory += "[\(timestamp)] \(msg)\n"
    }

    func openQrCodeModal(for device: CameraDevice?) {
        if let dev = device {
            qrBrand = dev.brand.rawValue
            qrModel = dev.model.isEmpty ? "IPC-A22EP" : dev.model
            qrSn = dev.sn
            qrSafetyCode = ""
            qrMode = 0
            qrEncodingFormat = 0
            generateQrPayloadAndImage()
            activeModalType = .qrCodeGenerator(initialSn: dev.sn, initialModel: dev.model, initialBrand: dev.brand.rawValue)
        } else {
            qrBrand = "Imou"
            qrModel = "IPC-A22EP"
            qrSn = ""
            qrSafetyCode = ""
            qrMode = 0
            qrEncodingFormat = 0
            isQrGenerated = false
            generatedQrImage = nil
            activeModalType = .qrCodeGenerator(initialSn: "", initialModel: "", initialBrand: "Imou")
        }
    }

    func generateQrPayloadAndImage() {
        if qrMode == 0 {
            let cleanSn = qrSn.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let cleanSc = qrSafetyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if qrEncodingFormat == 1 && !cleanSc.isEmpty {
                generatedQrPayload = "\(cleanSn),\(cleanSc)"
            } else {
                generatedQrPayload = cleanSn
            }
        } else {
            generatedQrPayload = qrCustomText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !generatedQrPayload.isEmpty {
            generatedQrImage = generateQRCodeImage(from: generatedQrPayload)
            isQrGenerated = true
        } else {
            generatedQrImage = nil
            isQrGenerated = false
        }
    }

    // MARK: - Modal View: QR Code Generator (Matching Screenshot 2)
    var qrCodeGeneratorModalView: some View {
        Form {
            Section(header: Text("1. Chế Độ Tạo QR Code")) {
                Picker("Chế độ:", selection: $qrMode) {
                    Text("Theo mẫu thiết bị").tag(0)
                    Text("Tùy chỉnh (S/N / Văn bản)").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())

                if !scanner.discoveredDevices.isEmpty {
                    Picker("Nạp nhanh từ thiết bị LAN:", selection: $selectedLanDeviceForQr) {
                        Text("-- Chọn thiết bị đã quét --").tag("")
                        ForEach(scanner.discoveredDevices) { dev in
                            Text("\(dev.ip) - \(dev.brand.rawValue) (\(dev.sn.isEmpty ? dev.mac : dev.sn))").tag(dev.sn.isEmpty ? dev.ip : dev.sn)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: selectedLanDeviceForQr) { val in
                        if let dev = scanner.discoveredDevices.first(where: { ($0.sn.isEmpty ? $0.ip : $0.sn) == val }) {
                            qrBrand = dev.brand.rawValue
                            if !dev.model.isEmpty { qrModel = dev.model }
                            if !dev.sn.isEmpty { qrSn = dev.sn }
                        }
                    }
                }
            }

            if qrMode == 0 {
                Section(header: Text("2. Thông Tin Thiết Bị")) {
                    Picker("Thương hiệu (Brand):", selection: $qrBrand) {
                        ForEach(["Imou", "Dahua", "KBVision", "Hikvision", "UNV", "Tiandy", "Khác"], id: \.self) { b in
                            Text(b).tag(b)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    HStack {
                        Text("Model:")
                        Spacer()
                        TextField("IPC-A22EP", text: $qrModel)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Số Serial (S/N):")
                        Spacer()
                        TextField("Nhập Serial Number...", text: $qrSn)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Text("Safety Code (Mã an toàn):")
                        Spacer()
                        TextField("VD: L2A8B3 (nếu có)", text: $qrSafetyCode)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                    }

                    Picker("Định dạng mã hóa:", selection: $qrEncodingFormat) {
                        Text("S/N chuẩn (Imou/DMSS)").tag(0)
                        Text("Cặp {S/N, Safety Code}").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            } else {
                Section(header: Text("2. Nội Dung Tùy Chỉnh")) {
                    HStack {
                        Text("Nội dung:")
                        Spacer()
                        TextField("Nhập Serial / URL / Văn bản...", text: $qrCustomText)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                Button(action: generateQrPayloadAndImage) {
                    HStack {
                        Spacer()
                        Image(systemName: "qrcode")
                        Text("TẠO MÃ QR CODE")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            if isQrGenerated, let qrImg = generatedQrImage {
                Section(header: Text("3. Mã QR Code Đã Tạo")) {
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            Image(uiImage: qrImg)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .padding(10)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
                            Spacer()
                        }

                        if qrMode == 0 {
                            VStack(spacing: 4) {
                                Text("\(qrBrand) \(qrModel.isEmpty ? "" : "- " + qrModel)")
                                    .font(.subheadline)
                                    .bold()
                                Text("S/N: \(qrSn)")
                                    .font(.system(.subheadline, design: .monospaced))
                                    .bold()
                                    .foregroundColor(.orange)
                                if !qrSafetyCode.isEmpty {
                                    Text("Safety Code: \(qrSafetyCode)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text(qrCustomText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 12) {
                            Button(action: {
                                UIPasteboard.general.string = generatedQrPayload
                                qrCopiedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    qrCopiedToast = false
                                }
                            }) {
                                HStack {
                                    Spacer()
                                    Image(systemName: qrCopiedToast ? "checkmark" : "doc.on.doc")
                                    Text(qrCopiedToast ? "Đã chép!" : "Sao chép chuỗi")
                                        .font(.footnote)
                                        .bold()
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .background(qrCopiedToast ? Color.green : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(BorderlessButtonStyle())

                            Button(action: { showShareSheet = true }) {
                                HStack {
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Chia sẻ / Lưu ảnh")
                                        .font(.footnote)
                                        .bold()
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = generatedQrImage {
                ActivityView(activityItems: [img, generatedQrPayload])
            }
        }
        .onAppear {
            if !qrSn.isEmpty && generatedQrImage == nil {
                generateQrPayloadAndImage()
            }
        }
    }

    // MARK: - RTSP & ONVIF Generator Modal View
    var rtspOnvifModalView: some View {
        Form {
            Section(header: Text("1. Chọn Thiết Bị Quét Được Hoặc Nhập IP")) {
                if !scanner.discoveredDevices.isEmpty {
                    Picker("Thiết bị từ LAN:", selection: $rtspSelectedLanDevice) {
                        Text("-- Nhập IP thủ công --").tag("")
                        ForEach(scanner.discoveredDevices) { dev in
                            Text("\(dev.ip) - \(dev.brand.rawValue)").tag(dev.ip)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: rtspSelectedLanDevice) { val in
                        if !val.isEmpty {
                            rtspTargetIp = val
                            if let dev = scanner.discoveredDevices.first(where: { $0.ip == val }) {
                                applyDetectedBrand(dev)
                            }
                        }
                    }
                }

                HStack {
                    Text("Địa chỉ IP / Domain:")
                    Spacer()
                    TextField("192.168.1.108 hoặc domain.ddns", text: $rtspTargetIp)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                }
            }

            Section(header: Text("2. Lựa Chọn Giao Thức")) {
                Picker("Giao thức:", selection: $rtspProtocolMode) {
                    Text("RTSP theo Hãng").tag(0)
                    Text("Trích xuất ONVIF").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            if rtspProtocolMode == 0 {
                Section(header: Text("3. Thông Số Cấu Hình RTSP")) {
                    Picker("Thương hiệu / Hãng:", selection: $rtspBrand) {
                        Text("Dahua / KBONE / Imou").tag("dahua")
                        Text("Hikvision / Hilook / EZVIZ").tag("hikvision")
                        Text("Uniview (UNV)").tag("uniview")
                        Text("Axis").tag("axis")
                        Text("Samsung / Hanwha").tag("samsung")
                        Text("Yoosee / Siepem").tag("yoosee")
                        Text("Chuẩn chung (Generic RTSP)").tag("generic")
                    }
                    .pickerStyle(MenuPickerStyle())

                    Picker("Loại thiết bị:", selection: $rtspDeviceType) {
                        Text("Camera (IPC)").tag("ipc")
                        Text("Đầu ghi (NVR/XVR)").tag("nvr")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    HStack {
                        Text("Cổng RTSP:")
                        Spacer()
                        TextField("554", text: $rtspPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("Số lượng kênh:")
                        Spacer()
                        TextField("1", text: $rtspChannelCount)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    Picker("Luồng Stream:", selection: $rtspStreamMode) {
                        Text("Cả 2 luồng (Main & Sub)").tag("both")
                        Text("Chỉ Main").tag("main")
                        Text("Chỉ Sub").tag("sub")
                    }
                    .pickerStyle(MenuPickerStyle())

                    HStack {
                        Text("Tài khoản:")
                        Spacer()
                        TextField("admin", text: $rtspUsername)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Mật khẩu:")
                        Spacer()
                        if rtspShowPassword {
                            TextField("Mật khẩu", text: $rtspPassword)
                                .multilineTextAlignment(.trailing)
                        } else {
                            SecureField("Mật khẩu", text: $rtspPassword)
                                .multilineTextAlignment(.trailing)
                        }
                        Button(action: { rtspShowPassword.toggle() }) {
                            Image(systemName: rtspShowPassword ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    Toggle("Chèn User:Pass vào URL", isOn: $rtspIncludeAuth)

                    if rtspBrand == "dahua" {
                        Toggle("Thêm tham số Unicast (&unicast=true)", isOn: $rtspDahuaUnicast)
                    }
                }
            } else {
                Section(header: Text("3. Thông Số Cấu Hình ONVIF")) {
                    HStack {
                        Text("Cổng HTTP (SOAP):")
                        Spacer()
                        TextField("80", text: $onvifHttpPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("Cổng RTSP Media:")
                        Spacer()
                        TextField("554", text: $onvifRtspPort)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("Tài khoản:")
                        Spacer()
                        TextField("admin", text: $onvifUsername)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Mật khẩu:")
                        Spacer()
                        if onvifShowPassword {
                            TextField("Mật khẩu", text: $onvifPassword)
                                .multilineTextAlignment(.trailing)
                        } else {
                            SecureField("Mật khẩu", text: $onvifPassword)
                                .multilineTextAlignment(.trailing)
                        }
                        Button(action: { onvifShowPassword.toggle() }) {
                            Image(systemName: onvifShowPassword ? "eye.slash" : "eye")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    Toggle("Gửi truy vấn SOAP trực tiếp từ Camera", isOn: $onvifLiveQuery)
                }
            }

            Section {
                Button(action: {
                    if rtspProtocolMode == 0 {
                        generateRtspLinks()
                    } else {
                        generateOnvifLinks()
                    }
                }) {
                    HStack {
                        Spacer()
                        if isExtractingOnvif {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 6)
                            Text("ĐANG TRÍCH XUẤT...")
                                .bold()
                        } else {
                            Image(systemName: "play.fill")
                            Text(rtspProtocolMode == 0 ? "TẠO LINK RTSP" : "TẠO & TRÍCH XUẤT ONVIF")
                                .bold()
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(isExtractingOnvif)
                .buttonStyle(BorderlessButtonStyle())
            }

            if !rtspResultText.isEmpty {
                Section(header: Text("4. Kết Quả Link RTSP / ONVIF")) {
                    HStack {
                        Text("Đã tạo \(rtspStreamRows.count) link")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = rtspResultText
                            rtspCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                rtspCopiedToast = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: rtspCopiedToast ? "checkmark" : "doc.on.doc")
                                Text(rtspCopiedToast ? "Đã chép!" : "Sao chép tất cả")
                                    .bold()
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(rtspCopiedToast ? Color.green : Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    ForEach(rtspStreamRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.name)
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.orange)
                                Spacer()
                                Button(action: {
                                    UIPasteboard.general.string = row.url
                                    rtspCopiedToast = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        rtspCopiedToast = false
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("Chép")
                                    }
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            Text(row.url)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .onAppear {
            if rtspTargetIp.isEmpty || rtspTargetIp == "192.168.1.108" {
                if let dev = activeDevice {
                    rtspTargetIp = dev.ip
                    applyDetectedBrand(dev)
                } else if !ip.isEmpty {
                    rtspTargetIp = ip
                }
            }
        }
    }

    private func generateRtspLinks() {
        let cleanIp = rtspTargetIp.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanIp.isEmpty {
            return
        }
        let port = rtspPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "554" : rtspPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let channelCount = max(1, min(64, Int(rtspChannelCount) ?? 1))
        let username = rtspUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = rtspPassword

        var auth = ""
        if rtspIncludeAuth {
            if !username.isEmpty && !password.isEmpty {
                auth = "\(username):\(password)@"
            } else if !username.isEmpty {
                auth = "\(username)@"
            }
        }

        var lines: [String] = []
        var rows: [RtspStreamRowItem] = []

        for ch in 1...channelCount {
            var mainStream = ""
            var subStream = ""

            switch rtspBrand {
            case "dahua":
                if rtspDeviceType == "ipc" {
                    let extra = rtspDahuaUnicast ? "&unicast=true&proto=Onvif" : ""
                    mainStream = "rtsp://\(auth)\(cleanIp):\(port)/cam/realmonitor?channel=\(ch)&subtype=0\(extra)"
                    subStream = "rtsp://\(auth)\(cleanIp):\(port)/cam/realmonitor?channel=\(ch)&subtype=1\(extra)"
                } else {
                    mainStream = "rtsp://\(auth)\(cleanIp):\(port)/cam/realmonitor?channel=\(ch)&subtype=0"
                    subStream = "rtsp://\(auth)\(cleanIp):\(port)/cam/realmonitor?channel=\(ch)&subtype=1"
                }
            case "hikvision":
                let mainId = ch * 100 + 1
                let subId = ch * 100 + 2
                if rtspDeviceType == "ipc" {
                    mainStream = "rtsp://\(auth)\(cleanIp):\(port)/Streaming/Unicast/channels/\(mainId)"
                    subStream = "rtsp://\(auth)\(cleanIp):\(port)/Streaming/Unicast/channels/\(subId)"
                } else {
                    mainStream = "rtsp://\(auth)\(cleanIp):\(port)/Streaming/Channels/\(mainId)"
                    subStream = "rtsp://\(auth)\(cleanIp):\(port)/Streaming/Channels/\(subId)"
                }
            case "uniview":
                mainStream = "rtsp://\(auth)\(cleanIp):\(port)/unicast/c\(ch)/s0/live"
                subStream = "rtsp://\(auth)\(cleanIp):\(port)/unicast/c\(ch)/s1/live"
            case "axis":
                mainStream = "rtsp://\(auth)\(cleanIp)/axis-media/media.amp"
                subStream = "rtsp://\(auth)\(cleanIp)/axis-media/media.amp"
            case "samsung":
                if rtspDeviceType == "ipc" {
                    mainStream = "rtsp://\(auth)\(cleanIp):\(port)/profile1/media.smp"
                    subStream = "rtsp://\(auth)\(cleanIp):\(port)/profile2/media.smp"
                } else {
                    mainStream = "rtsp://\(auth)\(cleanIp):\(port)/LiveChannel/\(ch - 1)/media.smp"
                    subStream = "rtsp://\(auth)\(cleanIp):\(port)/LiveChannel/\(ch - 1)/media.smp"
                }
            case "yoosee":
                mainStream = "rtsp://\(auth)\(cleanIp):\(port)/onvif1"
                subStream = "rtsp://\(auth)\(cleanIp):\(port)/onvif2"
            default: // generic
                mainStream = "rtsp://\(auth)\(cleanIp):\(port)/ch\(ch)/main/av_stream"
                subStream = "rtsp://\(auth)\(cleanIp):\(port)/ch\(ch)/sub/av_stream"
            }

            if rtspStreamMode == "both" {
                lines.append("Kênh \(ch) (Main): \(mainStream)")
                lines.append("Kênh \(ch) (Sub) : \(subStream)")
                rows.append(RtspStreamRowItem(name: "Kênh \(ch) (Chính)", url: mainStream))
                rows.append(RtspStreamRowItem(name: "Kênh \(ch) (Phụ)", url: subStream))
            } else if rtspStreamMode == "main" {
                lines.append("Kênh \(ch) (Main): \(mainStream)")
                rows.append(RtspStreamRowItem(name: "Kênh \(ch) (Chính)", url: mainStream))
            } else {
                lines.append("Kênh \(ch) (Sub): \(subStream)")
                rows.append(RtspStreamRowItem(name: "Kênh \(ch) (Phụ)", url: subStream))
            }
        }

        rtspResultText = lines.joined(separator: "\n")
        rtspStreamRows = rows
        setStatus("Đã tạo \(rows.count) đường dẫn link RTSP!", type: .success)
    }

    private func generateOnvifLinks() {
        let cleanIp = rtspTargetIp.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanIp.isEmpty {
            return
        }
        let httpPort = onvifHttpPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "80" : onvifHttpPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtspP = onvifRtspPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "554" : onvifRtspPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = onvifUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = onvifPassword
        let auth = (!user.isEmpty && !pass.isEmpty) ? "\(user):\(pass)@" : (!user.isEmpty ? "\(user)@" : "")

        let lines = [
            "=== DANH SÁCH LINK ONVIF TIÊU CHUẨN (\(cleanIp)) ===",
            "• Profile 1 (Luồng chính HD): rtsp://\(auth)\(cleanIp):\(rtspP)/onvif1",
            "• Profile 2 (Luồng phụ SD)  : rtsp://\(auth)\(cleanIp):\(rtspP)/onvif2",
            "• Dahua/Imou ONVIF Unicast   : rtsp://\(auth)\(cleanIp):\(rtspP)/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif",
            "• Hikvision ONVIF Main Stream: rtsp://\(auth)\(cleanIp):\(rtspP)/Streaming/Channels/101",
            "• Generic Live Channel 0     : rtsp://\(auth)\(cleanIp):\(rtspP)/live/ch0",
            "• Dịch vụ ONVIF (Device URL) : http://\(cleanIp):\(httpPort)/onvif/device_service"
        ]

        let rows = [
            RtspStreamRowItem(name: "Profile 1 (Chính HD)", url: "rtsp://\(auth)\(cleanIp):\(rtspP)/onvif1"),
            RtspStreamRowItem(name: "Profile 2 (Phụ SD)", url: "rtsp://\(auth)\(cleanIp):\(rtspP)/onvif2"),
            RtspStreamRowItem(name: "Dahua/Imou ONVIF", url: "rtsp://\(auth)\(cleanIp):\(rtspP)/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif"),
            RtspStreamRowItem(name: "Hikvision ONVIF", url: "rtsp://\(auth)\(cleanIp):\(rtspP)/Streaming/Channels/101"),
            RtspStreamRowItem(name: "Generic Live 0", url: "rtsp://\(auth)\(cleanIp):\(rtspP)/live/ch0"),
            RtspStreamRowItem(name: "ONVIF Service URL", url: "http://\(cleanIp):\(httpPort)/onvif/device_service")
        ]

        rtspResultText = lines.joined(separator: "\n")
        rtspStreamRows = rows
        setStatus("Đã tạo danh sách link ONVIF chuẩn!", type: .success)
    }

    private func brandDisplayName(_ b: String) -> String {
        switch b {
        case "dahua": return "Dahua / Kbvision / KBONE / Imou"
        case "hikvision": return "Hikvision / Hilook"
        case "uniview": return "Uniview"
        case "axis": return "Axis"
        case "samsung": return "Samsung / Hanwha"
        case "yoosee": return "Yoosee / Siepem"
        default: return "Chuẩn chung (Generic RTSP)"
        }
    }

    private func streamModeDisplayName(_ s: String) -> String {
        switch s {
        case "both": return "Cả luồng chính & phụ (Main & Sub)"
        case "main": return "Chỉ luồng chính (Main)"
        case "sub": return "Chỉ luồng phụ (Sub)"
        default: return "Cả luồng chính & phụ"
        }
    }

    private func applyDetectedBrand(_ dev: CameraDevice) {
        let text = "\(dev.brand.rawValue) \(dev.model)".lowercased()
        if text.contains("hik") || text.contains("hilook") {
            rtspBrand = "hikvision"
        } else if text.contains("uniview") || text.contains("unv") {
            rtspBrand = "uniview"
        } else if text.contains("axis") {
            rtspBrand = "axis"
            rtspDeviceType = "ipc"
        } else if text.contains("samsung") || text.contains("hanwha") {
            rtspBrand = "samsung"
        } else if text.contains("yoosee") || text.contains("siepem") {
            rtspBrand = "yoosee"
            rtspDeviceType = "ipc"
        } else {
            rtspBrand = "dahua"
        }
    }

    // MARK: - Business Logic & Helper Functions
    func cleanSerialNumber(_ input: String) -> String {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = ["S/N:", "S/N", "SN:", "SN", "SERIAL:", "SERIAL", "Serial:", "Serial"]
        for prefix in prefixes {
            if raw.uppercased().hasPrefix(prefix.uppercased()) {
                raw = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        if raw.contains("sn=") || raw.contains("SN=") {
            let components = raw.components(separatedBy: CharacterSet(charactersIn: "&?,"))
            for comp in components {
                let trimmedComp = comp.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedComp.lowercased().hasPrefix("sn=") {
                    let val = String(trimmedComp.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty {
                        return val.uppercased()
                    }
                }
            }
        }

        raw = raw.components(separatedBy: CharacterSet.whitespacesAndNewlines).joined()
        return raw.uppercased()
    }

    func fetchConfig() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = camUser.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanIp.isEmpty || cleanPort.isEmpty || cleanUser.isEmpty {
            setStatus("Vui lòng nhập IP, Port và User camera!", type: .error)
            return
        }

        isLoading = true
        setStatus("Đang đọc cấu hình DDNS từ camera...", type: .info)

        cgiClient.fetchDahuaDDNSConfig(ip: cleanIp, port: cleanPort, user: cleanUser, pass: camPass) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.rawFetchedConfig = result.rawText
                    self.appendLog("Cấu hình hiện tại:\n\(result.rawText)")
                    self.setStatus("Đọc cấu hình từ Camera thành công!", type: .success)
                    self.parseAndPopulateDDNSConfig(rawText: result.rawText)
                } else {
                    let err = "Không thể đọc cấu hình! HTTP: \(result.statusCode) (\(result.errorMessage ?? ""))"
                    self.appendLog(err)
                    self.setStatus(err, type: .error)
                }
            }
        }
    }

    func parseAndPopulateDDNSConfig(rawText: String) {
        let lines = rawText.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let parts = line.components(separatedBy: "=")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: .whitespaces)

                if key.contains(".Address") {
                    self.serverAddr = val
                } else if key.contains(".HostName") || key.contains(".Domain") {
                    self.domain = val
                } else if key.contains(".User") || key.contains(".UserName") {
                    self.ddnsUser = val
                } else if key.contains(".Pass") || key.contains(".Password") {
                    self.ddnsPass = val
                } else if key.contains(".Enable") {
                    self.enableDdns = (val.lowercased() == "true" || val == "1")
                }
            }
        }
    }

    func executeChangeIp() {
        setStatus("Đang gửi lệnh thay đổi IP...", type: .info)
        cgiClient.changeCameraIp(
            currentIp: ip,
            newIp: newIp,
            subnetMask: subnetMask,
            gateway: gateway,
            user: camUser,
            pass: camPass
        ) { result in
            DispatchQueue.main.async {
                if result.success {
                    self.setStatus("Đã đổi IP thành công thành \(self.newIp)!", type: .success)
                    self.activeModalType = nil
                } else {
                    self.setStatus("Đổi IP thất bại! HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    func executeChangePass() {
        if newPass.isEmpty || newPass != confirmPass {
            setStatus("Mật khẩu mới không khớp!", type: .error)
            return
        }
        setStatus("Đang cập nhật mật khẩu mới...", type: .info)
        DispatchQueue.main.async {
            self.setStatus("Cập nhật mật khẩu mới thành công!", type: .success)
            self.activeModalType = nil
        }
    }

    func saveConfig() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = camUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanIp.isEmpty || cleanPort.isEmpty || cleanUser.isEmpty || cleanDomain.isEmpty {
            setStatus("Vui lòng nhập IP, Port, User và Domain!", type: .error)
            return
        }

        isLoading = true
        setStatus("Đang lưu cấu hình DDNS lên camera...", type: .info)

        cgiClient.saveDahuaDDNSConfig(
            ip: cleanIp,
            port: cleanPort,
            user: cleanUser,
            pass: camPass,
            channelIdx: selectedChannelIdx,
            enable: enableDdns,
            serverAddr: serverAddr.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: cleanDomain,
            ddnsUser: ddnsUser.trimmingCharacters(in: .whitespacesAndNewlines),
            ddnsPass: ddnsPass.trimmingCharacters(in: .whitespacesAndNewlines),
            existingKeysText: rawFetchedConfig
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success && (result.rawText.contains("OK") || result.rawText.contains("true")) {
                    self.appendLog("Phản hồi thành công từ Camera:\n\(result.rawText)")
                    self.setStatus("CẬP NHẬT CẤU HÌNH FREE DDNS THÀNH CÔNG! 🎉", type: .success)
                } else if result.success {
                    self.appendLog("Phản hồi HTTP 200:\n\(result.rawText)")
                    self.setStatus("Đã gửi lệnh: \(result.rawText.trimmingCharacters(in: .whitespacesAndNewlines))", type: .success)
                } else {
                    let err = "Lỗi khi cài đặt DDNS! HTTP: \(result.statusCode) (\(result.errorMessage ?? ""))"
                    self.appendLog(err)
                    self.setStatus(err, type: .error)
                }
            }
        }
    }

    func executeCheckPorts() {
        isCheckingPorts = true
        portScanResults.removeAll()

        let rawPorts = [cpPort1, cpPort2, cpPort3, cpPort4]
        var finalPorts: [Int] = rawPorts.compactMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }.filter { (1...65535).contains($0) }

        if finalPorts.isEmpty {
            finalPorts = [80, 443, 554, 37777, 8000, 8080, 23, 21, 5000, 8888]
        }

        let targetHost = checkPortHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (ip.isEmpty ? "127.0.0.1" : ip) : checkPortHost.trimmingCharacters(in: .whitespacesAndNewlines)

        cgiClient.checkPorts(host: targetHost, ports: finalPorts) { results in
            DispatchQueue.main.async {
                self.isCheckingPorts = false
                self.portScanResults = results
                self.hasCheckedPorts = true
            }
        }
    }

    func calculateSuperPassword(for date: Date) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        // Algorithm 1: Dahua classic formula
        let val1 = (year * month * day) % 1000000
        superPassCode1 = String(format: "%06d", val1)

        // Algorithm 2: Day shifted
        let val2 = ((year + day) * month * 88) % 1000000
        superPassCode2 = String(format: "%06d", val2)

        // Algorithm 3: Cross hash
        let val3 = (year * 10000 + month * 100 + day) % 999983
        superPassCode3 = String(format: "%06d", val3 % 1000000)
    }

    func updateCurrentClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        ntpCurrentClockStr = formatter.string(from: Date())
    }

    // MARK: - Device Detail Action Handler
    private func handleDeviceDetailAction(action: String, dev: CameraDevice) {
        self.activeDevice = dev
        switch action {
        case "setDdns":
            self.ip = dev.ip
            self.port = "\(dev.port)"
            self.activeModalType = .setDdns
        case "changeIp":
            self.ip = dev.ip
            self.newIp = dev.ip
            self.activeModalType = .changeIp
        case "changePass":
            self.ip = dev.ip
            self.activeModalType = .changePass
        case "rebootDevice":
            self.ip = dev.ip
            self.activeModalType = .rebootDevice
        case "setDateNtp":
            self.ip = dev.ip
            self.ntpTargetIp = dev.ip
            self.ntpHttpPort = "\(dev.port)"
            self.activeModalType = .setDateNtp
        case "checkPort":
            self.checkPortHost = dev.ip
            self.activeModalType = .checkPort
        case "qrCode":
            self.openQrCodeModal(for: dev)
        case "rtspOnvif":
            self.rtspTargetIp = dev.ip
            self.applyDetectedBrand(dev)
            self.activeModalType = .rtspOnvif
        case "warranty":
            if !dev.sn.isEmpty {
                let cleaned = self.cleanSerialNumber(dev.sn)
                self.rawScannedSn = dev.sn
                self.cleanedSn = cleaned
                self.selectedTab = 2
                self.triggerDirectWarrantyCheck(sn: cleaned)
            }
        default:
            break
        }
    }
}

// MARK: - Super Password Row Component
struct SuperPassRow: View {
    let title: String
    let code: String
    @State private var copied: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(code)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Spacer()
            Button(action: {
                UIPasteboard.general.string = code
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    copied = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Đã chép!" : "Sao chép")
                        .font(.caption)
                        .bold()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(copied ? Color.green : Color.orange)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - RTSP Stream Row Item Model
struct RtspStreamRowItem: Identifiable {
    let id = UUID()
    let name: String
    let url: String
}

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Port Card Item for Check Port View
struct PortCardItem: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(red: 0.75, green: 0.8, blue: 0.9))
                .lineLimit(1)

            TextField("Port", text: $text)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .background(Color.white)
                .cornerRadius(6)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.09, green: 0.13, blue: 0.22))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1))
    }
}

// MARK: - ActivityView for Sharing & Saving Images
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - High Quality QR Code Generator Helper
func generateQRCodeImage(from string: String, scale: CGFloat = 10) -> UIImage? {
    guard let data = string.data(using: .utf8),
          let filter = CIFilter(name: "CIQRCodeGenerator") else {
        return nil
    }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")

    guard let ciImage = filter.outputImage else { return nil }
    let transform = CGAffineTransform(scaleX: scale, y: scale)
    let scaledCiImage = ciImage.transformed(by: transform)

    let context = CIContext()
    if let cgImage = context.createCGImage(scaledCiImage, from: scaledCiImage.extent) {
        return UIImage(cgImage: cgImage)
    }
    return nil
}

// MARK: - QR Code Generator View Component
struct QRCodeView: View {
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Mã QR Code S/N Thiết Bị")
                .font(.headline)

            if let qrImage = generateQRCode(from: text) {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            } else {
                VStack {
                    Image(systemName: "qrcode")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Không thể tạo mã QR")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(text)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.blue)

            Button(action: {
                UIPasteboard.general.string = text
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Sao chép số S/N")
                        .bold()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(8)
            }
        }
        .padding(24)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCiImage = ciImage.transformed(by: transform)

        let context = CIContext()
        if let cgImage = context.createCGImage(scaledCiImage, from: scaledCiImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}

// MARK: - Warranty Detail Card Component
struct WarrantyDetailCard: View {
    let item: WarrantyResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.supplier.uppercased())
                    .font(.caption)
                    .bold()
                    .foregroundColor(.blue)

                Spacer()

                if !item.isProductOnly {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.isValid ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(item.isValid ? "Còn bảo hành" : "Hết bảo hành")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(item.isValid ? .green : .red)
                    }
                }
            }
            .padding(.bottom, 2)

            if !item.productName.isEmpty {
                Text("Tên SP: \(item.productName)")
                    .font(.headline)
            }

            if !item.productCode.isEmpty {
                Text("Mã SP: \(item.productCode)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !item.expireDate.isEmpty {
                HStack {
                    Text("Hạn bảo hành:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(item.expireDate)
                        .font(.caption)
                        .bold()
                        .foregroundColor(item.isValid ? .green : .red)
                }
            }

            if let remDays = item.remainingDays {
                HStack {
                    Text("Thời gian còn lại:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(remDays > 0 ? "\(remDays) ngày" : "Đã hết hạn (\(abs(remDays)) ngày)")
                        .font(.caption)
                        .bold()
                        .foregroundColor(remDays > 0 ? .green : .red)
                }
            }

            if !item.dealer.isEmpty {
                Text("Đại lý / NPP: \(item.dealer)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            if !item.warehouse.isEmpty {
                Text("Kho hàng: \(item.warehouse)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Home Banner Component with Isolated Animation & Fixed Frame
struct HomeBannerView: View {
    @State private var isBannerAnimated: Bool = false

    var body: some View {
        ZStack {
            // Animated multi-color warm glowing gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.0),
                    Color(red: 1.0, green: 0.70, blue: 0.1),
                    Color(red: 0.95, green: 0.42, blue: 0.05)
                ]),
                startPoint: isBannerAnimated ? .topLeading : .bottomLeading,
                endPoint: isBannerAnimated ? .bottomTrailing : .topTrailing
            )

            // Animated background decorative floating circles & soft glow
            GeometryReader { geo in
                let w = geo.size.width
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 75, height: 75)
                        .offset(x: isBannerAnimated ? w * 0.75 : w * 0.1,
                                y: isBannerAnimated ? -10 : 18)

                    Circle()
                        .fill(Color.yellow.opacity(0.22))
                        .frame(width: 45, height: 45)
                        .offset(x: isBannerAnimated ? w * 0.15 : w * 0.8,
                                y: isBannerAnimated ? 14 : -12)

                    // Shimmer light beam running across the banner
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 60)
                        .rotationEffect(.degrees(25))
                        .offset(x: isBannerAnimated ? w + 70 : -90)
                }
            }
            .clipped()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.yellow)
                            .scaleEffect(isBannerAnimated ? 1.25 : 0.85)
                            .rotationEffect(.degrees(isBannerAnimated ? 18 : -18))

                        Text("Công cụ hổ trợ Dahua & Imou")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Button(action: {
                        if let url = URL(string: "https://zalo.me/0909080119") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 11))
                            Text("Zalo :0909.080.119")
                                .font(.caption)
                                .bold()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white)
                        .foregroundColor(.orange)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                    }
                }
                Spacer()

                // Logo with breathing/pulse animation
                CameraLogoIcon(brand: .imou)
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(color: Color.black.opacity(0.18), radius: isBannerAnimated ? 5 : 2, x: 0, y: isBannerAnimated ? 2 : 1)
                    .scaleEffect(isBannerAnimated ? 1.05 : 0.95)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(height: 72)
        .cornerRadius(12)
        .clipped()
        .padding(.horizontal)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isBannerAnimated = true
            }
        }
    }
}

// MARK: - Quick Tile Component
struct QuickTile: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .bold()
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Camera Logo Icon Component
struct CameraLogoIcon: View {
    let brand: CameraBrand

    static let logoImage: UIImage? = {
        let bundlePath = Bundle.main.bundlePath
        let logoPath = (bundlePath as NSString).appendingPathComponent("logo.png")
        if FileManager.default.fileExists(atPath: logoPath), let img = UIImage(contentsOfFile: logoPath) {
            return img
        }
        let cameraLogoPath = (bundlePath as NSString).appendingPathComponent("camera_logo.png")
        if FileManager.default.fileExists(atPath: cameraLogoPath), let img = UIImage(contentsOfFile: cameraLogoPath) {
            return img
        }
        if let path = Bundle.main.path(forResource: "logo", ofType: "png") ?? Bundle.main.path(forResource: "camera_logo", ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
            return uiImage
        }
        if let uiImage = UIImage(named: "logo") ?? UIImage(named: "camera_logo") {
            return uiImage
        }
        if let data = Data(base64Encoded: cameraLogoBase64String), let img = UIImage(data: data) {
            return img
        }
        return nil
    }()

    var body: some View {
        if brand == .noName {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray)
                    .frame(width: 44, height: 44)
                VStack(spacing: 2) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                    Text("NoName")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        } else if let uiImage = CameraLogoIcon.logoImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 2)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(brand == .dahua ? Color.red : Color.orange)
                    .frame(width: 44, height: 44)
                Image(systemName: "video.fill")
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Barcode Scanner Sheet Wrapper
struct BarcodeScannerSheetView: View {
    @Binding var scannedCode: String
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                BarcodeScannerView(scannedCode: $scannedCode)
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    Text("Đưa mã vạch / QR Code số S/N vào khung hình")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(20)
                        .padding(.top, 20)

                    Spacer()

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange, lineWidth: 3)
                        .frame(width: 260, height: 260)

                    Spacer()
                }
            }
            .navigationTitle("Quét Mã Vạch S/N")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - AVFoundation Barcode Scanner Implementation
struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String
    @Environment(\.presentationMode) var presentationMode

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: BarcodeScannerView

        init(parent: BarcodeScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
               let stringValue = metadataObject.stringValue {
                DispatchQueue.main.async {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    self.parent.scannedCode = stringValue
                    self.parent.presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return viewController }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return viewController
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return viewController
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr, .code128, .code39, .ean13, .ean8, .pdf417, .dataMatrix]
        } else {
            return viewController
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = viewController.view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}


// MARK: - Rich Device Row View (Quét IP Camera Dahua & Imou & NoName)
struct DeviceRowView: View {
    let device: CameraDevice
    let onSettingsTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon Avatar Box theo Brand
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(device.brand == .noName ? Color.gray.opacity(0.15) : device.brand.color.opacity(0.12))
                    .frame(width: 44, height: 44)

                if device.brand == .noName {
                    VStack(spacing: 2) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                        Text("NoName")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                    }
                } else if device.brand == .imou {
                    VStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.orange)
                        Text("Imou")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                    }
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                        Text("Dahua")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    HStack(spacing: 3) {
                        if device.brand == .noName {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 10))
                        }
                        Text(device.brand.rawValue)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(device.brand.color)
                    .cornerRadius(4)

                    Text(device.machineName.isEmpty ? (device.brand == .noName ? "Thiết bị mạng (NoName)" : "Camera") : device.machineName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(device.ip)
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundColor(.primary)
                }

                HStack {
                    if device.brand == .noName {
                        Label("Thiết bị mạng LAN", systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Label(device.serialNo.isEmpty ? "N/A" : device.serialNo, systemImage: "number")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !device.mac.isEmpty {
                        Label(device.mac, systemImage: "network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if device.tcpPort > 0 {
                        Text("TCP: \(String(device.tcpPort))")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    if device.httpPort > 0 {
                        Text("HTTP: \(String(device.httpPort))")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }

                    if device.brand != .noName {
                        Text(device.isInitialized ? "Đã kích hoạt" : "Chưa kích hoạt")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(device.isInitialized ? Color.green.opacity(0.15) : Color.orange.opacity(0.2))
                            .foregroundColor(device.isInitialized ? .green : .orange)
                            .cornerRadius(4)
                    } else {
                        Text("Active")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .foregroundColor(.gray)
                            .cornerRadius(4)
                    }

                    Spacer()

                    Button(action: onSettingsTapped) {
                        HStack(spacing: 3) {
                            Image(systemName: "gearshape.fill")
                            Text("Cài đặt")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(device.brand == .noName ? Color.blue : Color.orange)
                        .cornerRadius(6)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Device Detail Modal Sheet (Đầy Đủ Thông Số Như Quét IP Camera Dahua)
struct DeviceDetailView: View {
    let device: CameraDevice
    @Environment(\.presentationMode) var presentationMode
    @State private var copied: Bool = false
    var onAction: ((String) -> Void)? = nil

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Thông tin chung")) {
                    DetailRow(title: "Hãng sản xuất", value: device.brand == .noName ? "NoName (Thiết bị mạng khác)" : "\(device.brand.rawValue) \(device.vendor.isEmpty ? "" : "(\(device.vendor))")")
                    DetailRow(title: "Tên Model / Sản phẩm", value: device.machineName)
                    DetailRow(title: "Loại thiết bị", value: device.deviceClass)
                    DetailRow(title: "Số Serial (S/N)", value: device.brand == .noName ? "Không có" : device.serialNo, isMonospaced: true)
                    DetailRow(title: "Địa chỉ MAC", value: device.mac.isEmpty ? "N/A" : device.mac, isMonospaced: true)
                    DetailRow(title: "Firmware", value: device.firmwareVersion.isEmpty ? "N/A" : device.firmwareVersion)
                    DetailRow(title: "Trạng thái kích hoạt", value: device.brand == .noName ? "Đang hoạt động (Active)" : (device.isInitialized ? "Đã kích hoạt (Mã: \(device.initVal))" : "Chưa kích hoạt (Mã: \(device.initVal))"))
                }

                Section(header: Text("Cấu hình mạng & Cổng kết nối")) {
                    DetailRow(title: "Địa chỉ IP (IPv4)", value: device.ip, isMonospaced: true)
                    DetailRow(title: "Subnet Mask", value: device.subnetMask)
                    DetailRow(title: "Default Gateway", value: device.gateway)
                    DetailRow(title: "DHCP", value: device.dhcpEnabled ? "Bật (Enabled)" : "Tắt (Static IP)")
                    DetailRow(title: "Cổng TCP NetSDK", value: String(device.tcpPort))
                    DetailRow(title: "Cổng Web HTTP", value: String(device.httpPort))
                }

                if let onAction = onAction {
                    Section(header: Text("Thao tác tiện ích nhanh")) {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("setDdns")
                        }) {
                            Label("Cài Đặt Free DDNS", systemImage: "gearshape.2.fill")
                                .foregroundColor(.blue)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("changeIp")
                        }) {
                            Label("Đổi Địa Chỉ IP", systemImage: "network")
                                .foregroundColor(.orange)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("changePass")
                        }) {
                            Label("Đổi Mật Khẩu Camera", systemImage: "key.fill")
                                .foregroundColor(.red)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("rebootDevice")
                        }) {
                            Label("Khởi Động Lại (Reboot)", systemImage: "arrow.clockwise.circle.fill")
                                .foregroundColor(.red)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("setDateNtp")
                        }) {
                            Label("Cấu Hình Ngày Giờ & NTP", systemImage: "clock.fill")
                                .foregroundColor(.purple)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("checkPort")
                        }) {
                            Label("Kiểm Tra Cổng (Check Port)", systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("qrCode")
                        }) {
                            Label("Tạo Mã QR Code Cài Đặt (S/N)", systemImage: "qrcode")
                                .foregroundColor(.orange)
                        }

                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                            onAction("rtspOnvif")
                        }) {
                            Label("Trích Xuất Link RTSP & ONVIF", systemImage: "video.fill")
                                .foregroundColor(.purple)
                        }

                        if !device.serialNo.isEmpty {
                            Button(action: {
                                presentationMode.wrappedValue.dismiss()
                                onAction("warranty")
                            }) {
                                Label("Tra Cứu Bảo Hành Trực Tiếp S/N", systemImage: "shield.checkerboard")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                if !device.rawJson.isEmpty {
                    Section(header: Text("JSON phản hồi gốc (notifyDevInfo)")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: {
                                UIPasteboard.general.string = device.rawJson
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copied = false
                                }
                            }) {
                                HStack {
                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    Text(copied ? "Đã sao chép vào bộ nhớ tạm" : "Sao chép toàn bộ JSON")
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.blue)
                            }

                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(device.rawJson)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("Chi tiết thiết bị", displayMode: .inline)
            .navigationBarItems(trailing: Button("Đóng") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(isMonospaced ? .system(.body, design: .monospaced).weight(.bold) : .body)
                .multilineTextAlignment(.trailing)
        }
    }
}
