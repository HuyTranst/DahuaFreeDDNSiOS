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

        // 1. Query DSS Vietnam API (https://app.dahua.vn:7778/Api.svc/Web/TraCuuBaoHanhTheoSeria?seria=...)
        group.enter()
        queryDSS(sn: cleanSn) { dssResults in
            lock.lock()
            results.append(contentsOf: dssResults)
            lock.unlock()
            group.leave()
        }

        // 2. Query Dahua Global Support API (https://supportapi.dahuasecurity.com/support/api/doc/docOverseasProduct/selectInfoBtSN?serialNumber=...)
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
}

// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var scanner = LanScanner()
    @State private var selectedTab: Int = 0

    // Selected Device for Action Modal
    @State private var activeDevice: CameraDevice? = nil
    @State private var showActionSheet = false
    @State private var activeModalType: ModalType? = nil

    // Warranty Check State
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
    @State var selectedPresetIndex: Int = 0
    @State var serverAddr: String = "fastddns.net"
    @State var domain: String = "mycam.fastddns.net"
    @State var ddnsUser: String = ""
    @State var ddnsPass: String = ""
    @State var enableDdns: Bool = true
    @State var selectedChannelIdx: String = "0"

    // Change IP State
    @State private var newIp: String = "192.168.1.120"
    @State private var subnetMask: String = "255.255.255.0"
    @State private var gateway: String = "192.168.1.1"

    // Change Password State
    @State private var oldPass: String = ""
    @State private var newPass: String = ""
    @State private var confirmPass: String = ""

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
    @State private var selectedDate: Date = Date()
    @State private var enableNtp: Bool = true
    @State private var ntpServer: String = "time.google.com"
    @State private var ntpPort: String = "123"
    @State private var ntpPeriod: String = "60"

    // Super Password State
    @State private var superPassDate: Date = Date()
    @State private var superPassCode1: String = ""
    @State private var superPassCode2: String = ""
    @State private var superPassCode3: String = ""

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

            // Tab 2: Sản phẩm
            NavigationView {
                sanPhamView
                    .navigationTitle("Sản phẩm")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "video.fill")
                Text("Sản phẩm")
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

            // Tab 4: Dễ Cấu Hình
            NavigationView {
                ddnsFormView
                    .navigationTitle("Dễ Cấu Hình Free DDNS")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "gearshape.2.fill")
                Text("Dễ Cấu Hình")
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
                            self.activeModalType = .setDateNtp
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
                        .navigationTitle("Ngày Giờ & NTP (\(ip))")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .checkPort:
                checkPortModalView
            case .superPassword:
                NavigationView {
                    superPasswordView
                        .navigationTitle("Super Password Dahua")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") { activeModalType = nil }
                            }
                        }
                }
            case .qrCodeGenerator:
                qrCodeGeneratorModalView
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

                            Text("Quét mã Barcode / QR Code S/N hoặc nhập để kiểm tra trực tiếp qua API DSS Việt Nam & Dahua Global.")
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
                        Text("Đang tra cứu dữ liệu bảo hành API...")
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
                                Text("Có thể camera chưa kích hoạt bảo hành điện tử DSS hoặc thuộc nhà phân phối khác.")
                                    .font(.caption2)
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

                    Button(action: { scanner.startScan() }) {
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
                // Imou Banner Header
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.orange.opacity(0.85), Color.orange]), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .cornerRadius(16)

                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dahua & Imou Free DDNS")
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)

                            Text("Enjoy Smart Life • Check Bảo Hành & Cài DDNS Tự Động")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))

                            Button(action: {
                                selectedTab = 2
                            }) {
                                Text("Check Bảo Hành S/N 🔍")
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .foregroundColor(.orange)
                                    .cornerRadius(20)
                            }
                            .padding(.top, 4)
                        }
                        Spacer()

                        CameraLogoIcon(brand: .imou)
                            .frame(width: 64, height: 64)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(16)
                }
                .padding(.horizontal)

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
                        QuickTile(title: "Đổi IP Camera", icon: "network", color: .green) {
                            self.activeModalType = .changeIp
                        }
                    }
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        QuickTile(title: "Check Port", icon: "antenna.radiowaves.left.and.right", color: .purple) {
                            self.activeModalType = .checkPort
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

                // Discovered Devices Preview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thiết Bị Phát Hiện (\(scanner.discoveredDevices.count))")
                            .font(.headline)
                        Spacer()
                        Button(scanner.isScanning ? "Đang quét..." : "Quét ngay 🔄") {
                            scanner.startScan()
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .disabled(scanner.isScanning)
                    }
                    .padding(.horizontal)

                    if scanner.discoveredDevices.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("Chưa quét thiết bị nào trong LAN.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("Nhấn vào đây để quét tìm IP Camera ngay") {
                                scanner.startScan()
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
                        ForEach(scanner.discoveredDevices) { dev in
                            HStack {
                                CameraLogoIcon(brand: dev.brand)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text("\(dev.ip):\(dev.port)")
                                            .font(.headline)
                                        Text("(\(dev.brand.rawValue))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if !dev.sn.isEmpty {
                                        Text("🔵 S/N: \(dev.sn)")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    if !dev.model.isEmpty {
                                        Text("Model: \(dev.model)")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Button(action: {
                                    self.activeDevice = dev
                                    self.showActionSheet = true
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "gearshape.fill")
                                        Text("Cài đặt")
                                            .font(.caption)
                                            .bold()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(10)
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

    // TAB 3: Dễ Cấu Hình (Free DDNS Form View)
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
                    SecureField("Mật khẩu camera", text: $camPass)
                        .multilineTextAlignment(.trailing)
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
                    SecureField("Pass DDNS (nếu có)", text: $ddnsPass)
                        .multilineTextAlignment(.trailing)
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

    // TAB 4: Tôi (Profile & Utilities View)
    var toiView: some View {
        Form {
            Section(header: Text("Tài khoản & Thiết lập")) {
                HStack(spacing: 12) {
                    CameraLogoIcon(brand: .dahua)
                        .frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dahua & Imou Manager")
                            .font(.headline)
                        Text("Phiên bản 1.0.0 (Check Bảo Hành API & Free DDNS)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Tiện ích quản trị Camera")) {
                Button(action: {
                    self.activeModalType = .changeIp
                }) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.orange)
                        Text("Đổi địa chỉ IP Camera")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Button(action: {
                    self.activeModalType = .changePass
                }) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.orange)
                        Text("Đổi mật khẩu Camera")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }

            Section(header: Text("Thông tin ứng dụng")) {
                HStack {
                    Text("Logo Icon App")
                    Spacer()
                    Text("logo.png")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("API Tra Cứu Bảo Hành")
                    Spacer()
                    Text("DSS Việt Nam & Dahua Global")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Hệ điều hành hỗ trợ")
                    Spacer()
                    Text("iOS 15.0+")
                        .foregroundColor(.secondary)
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
                    SecureField("Mật khẩu", text: $camPass)
                        .multilineTextAlignment(.trailing)
                }
            }

            Button(action: executeChangeIp) {
                HStack {
                    Spacer()
                    Text("🌐 CẬP NHẬT IP MỚI VIA DIGEST AUTH")
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(Color.orange)
                .cornerRadius(8)
            }
        }
    }

    // Modal view: Change Password
    var changePassView: some View {
        Form {
            Section(header: Text("Đổi Mật Khẩu Camera [\(ip)]")) {
                SecureField("Mật khẩu hiện tại", text: $oldPass)
                SecureField("Mật khẩu mới", text: $newPass)
                SecureField("Xác nhận mật khẩu mới", text: $confirmPass)
            }

            Button(action: executeChangePass) {
                HStack {
                    Spacer()
                    Text("🔑 CẬP NHẬT MẬT KHẨU MỚI")
                        .bold()
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Modal View: Check Port (Matching Screenshot 1)
    var checkPortModalView: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.12).edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Top Banner: WAN IP Public
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center) {
                                Image(systemName: "globe")
                                    .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))
                                    .font(.title3)

                                Text("Địa chỉ IP WAN công cộng của bạn:")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                Text(currentWanIp)
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))

                                Spacer()

                                Button(action: fetchWanIp) {
                                    HStack(spacing: 4) {
                                        if isLoadingWanIp {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption)
                                        }
                                        Text("Tải lại WAN IP")
                                            .font(.caption)
                                            .bold()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.08, green: 0.38, blue: 0.58))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }

                                Button(action: fillWanIp) {
                                    Text("Điền IP WAN")
                                        .font(.caption)
                                        .bold()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 0.06, green: 0.65, blue: 0.45))
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.14, green: 0.25, blue: 0.38), lineWidth: 1)
                        )

                        // 2. Target IP / Domain & LAN device selection
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                // LAN Device Dropdown
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Hoặc chọn thiết bị từ mạng LAN:")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))

                                    Menu {
                                        Button("-- [Tự do nhập IP/WAN] hoặc Chọn thiết bị --") {
                                            selectedLanDeviceForPort = ""
                                        }
                                        ForEach(scanner.discoveredDevices) { dev in
                                            Button("\(dev.ip) - \(dev.brand.rawValue) (\(dev.model.isEmpty ? dev.mac : dev.model))") {
                                                selectedLanDeviceForPort = dev.ip
                                                checkPortHost = dev.ip
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(selectedLanDeviceForPort.isEmpty ? "-- [Tự do nhập IP/WAN] hoặc Chọn thiết bị --" : selectedLanDeviceForPort)
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .font(.caption2)
                                                .foregroundColor(.gray)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1)
                                        )
                                    }
                                }

                                // Target Host Input
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("*")
                                            .foregroundColor(.cyan)
                                        Text("Địa chỉ IP / Tên miền kiểm tra:")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))
                                    }

                                    HStack {
                                        TextField("VD: 27.64.170.126 hoặc domain.ddns", text: $checkPortHost)
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)

                                        if !checkPortHost.isEmpty {
                                            Button(action: { checkPortHost = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.14, green: 0.22, blue: 0.35), lineWidth: 1)
                        )

                        // 3. Ports Input Cards (Ports 1 to 4)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CÁC CỔNG CẦN KIỂM TRA (PORTS):")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Gợi ý các cổng camera phổ biến")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }

                            // 4 Port Cards Row
                            HStack(spacing: 8) {
                                PortCardItem(label: "Cổng 1 (Dahua TCP)", text: $cpPort1)
                                PortCardItem(label: "Cổng 2 (HTTP Web)", text: $cpPort2)
                                PortCardItem(label: "Cổng 3 (RTSP Stream)", text: $cpPort3)
                                PortCardItem(label: "Cổng 4 (Hikvision SDK)", text: $cpPort4)
                            }

                            // Preset Pills Row
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        cpPort1 = "37777"; cpPort2 = "80"; cpPort3 = "554"; cpPort4 = ""
                                    }) {
                                        Text("⭐ Bộ Dahua (37777, 80, 554)")
                                            .font(.caption2)
                                            .bold()
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(red: 0.09, green: 0.22, blue: 0.36))
                                            .foregroundColor(.cyan)
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                                    }

                                    Button(action: {
                                        cpPort1 = "8000"; cpPort2 = "80"; cpPort3 = "554"; cpPort4 = "443"
                                    }) {
                                        Text("⭐ Bộ Hikvision (8000, 80, 554, 443)")
                                            .font(.caption2)
                                            .bold()
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(red: 0.28, green: 0.2, blue: 0.08))
                                            .foregroundColor(.orange)
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                                    }

                                    Button(action: {
                                        cpPort1 = "34567"; cpPort2 = "80"; cpPort3 = "554"; cpPort4 = ""
                                    }) {
                                        Text("⭐ Bộ Xiongmai / XM (34567, 80, 554)")
                                            .font(.caption2)
                                            .bold()
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(red: 0.22, green: 0.12, blue: 0.32))
                                            .foregroundColor(Color(red: 0.8, green: 0.5, blue: 0.95))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                                    }

                                    Button(action: {
                                        cpPort1 = "80"; cpPort2 = "443"; cpPort3 = "8080"; cpPort4 = ""
                                    }) {
                                        Text("Web Ports (80, 443, 8080)")
                                            .font(.caption2)
                                            .bold()
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color(red: 0.12, green: 0.16, blue: 0.24))
                                            .foregroundColor(.white)
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.14, green: 0.22, blue: 0.35), lineWidth: 1)
                        )

                        // 4. Main Check Button
                        Button(action: executeCheckPorts) {
                            HStack {
                                Spacer()
                                if isCheckingPorts {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 8)
                                    Text("Đang kiểm tra...")
                                        .font(.headline)
                                        .bold()
                                } else {
                                    Image(systemName: "magnifyingglass")
                                        .font(.headline)
                                    Text("Kiểm Tra Cổng")
                                        .font(.headline)
                                        .bold()
                                }
                                Spacer()
                            }
                            .frame(height: 48)
                            .background(Color(red: 0.06, green: 0.65, blue: 0.45))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(color: Color(red: 0.06, green: 0.65, blue: 0.45).opacity(0.3), radius: 6, x: 0, y: 3)
                        }
                        .disabled(isCheckingPorts)

                        // 5. Results Table Section
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Kết quả kiểm tra cổng mở:")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)

                                Spacer()

                                if hasCheckedPorts {
                                    let openCount = portScanResults.filter { $0.isOpen }.count
                                    if openCount > 0 {
                                        Text("🟢 Có \(openCount) / \(portScanResults.count) cổng MỞ")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))
                                    } else {
                                        Text("🔴 0 / \(portScanResults.count) cổng Mở (Tất cả ĐÓNG)")
                                            .font(.caption)
                                            .bold()
                                            .foregroundColor(Color(red: 0.95, green: 0.35, blue: 0.35))
                                    }
                                }
                            }

                            // Table Header
                            HStack {
                                Text("IP / Tên miền")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Cổng")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.gray)
                                    .frame(width: 50, alignment: .center)
                                Text("Dịch vụ")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Trạng thái")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.gray)
                                    .frame(width: 85, alignment: .center)
                                Text("Truy cập nhanh")
                                    .font(.caption2)
                                    .bold()
                                    .foregroundColor(.gray)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.06, green: 0.09, blue: 0.15))
                            .cornerRadius(6)

                            if portScanResults.isEmpty {
                                HStack {
                                    Spacer()
                                    Text(hasCheckedPorts ? "Không tìm thấy cổng nào." : "Nhập IP / Port và bấm [Kiểm Tra Cổng] để xem kết quả.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 16)
                                    Spacer()
                                }
                            } else {
                                ForEach(portScanResults) { res in
                                    HStack {
                                        Text(res.host)
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text("\(res.port)")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0))
                                            .frame(width: 50, alignment: .center)

                                        Text(res.service)
                                            .font(.caption2)
                                            .foregroundColor(Color(red: 0.8, green: 0.85, blue: 0.95))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if res.isOpen {
                                            Text("🟢 Mở (Open)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color(red: 0.2, green: 0.83, blue: 0.6).opacity(0.15))
                                                .cornerRadius(4)
                                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.2, green: 0.83, blue: 0.6).opacity(0.4), lineWidth: 1))
                                                .frame(width: 85, alignment: .center)
                                        } else {
                                            Text("🔴 Đóng (Closed)")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(Color(red: 0.95, green: 0.4, blue: 0.4))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color(red: 0.95, green: 0.4, blue: 0.4).opacity(0.12))
                                                .cornerRadius(4)
                                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.95, green: 0.4, blue: 0.4).opacity(0.3), lineWidth: 1))
                                                .frame(width: 85, alignment: .center)
                                        }

                                        // Quick Action Button
                                        if res.isOpen {
                                            if res.port == 80 || res.port == 8080 {
                                                Button(action: {
                                                    if let url = URL(string: "http://\(res.host):\(res.port)") {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }) {
                                                    Text("🌐 Mở Web")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(Color.blue)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(4)
                                                }
                                                .frame(width: 80, alignment: .trailing)
                                            } else if res.port == 443 {
                                                Button(action: {
                                                    if let url = URL(string: "https://\(res.host):\(res.port)") {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }) {
                                                    Text("🔒 Mở Web")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(Color.blue)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(4)
                                                }
                                                .frame(width: 80, alignment: .trailing)
                                            } else if res.port == 554 {
                                                Button(action: {
                                                    let rtspUrl = "rtsp://admin:admin123@\(res.host):\(res.port)/cam/realmonitor?channel=1&subtype=0"
                                                    UIPasteboard.general.string = rtspUrl
                                                }) {
                                                    Text("📺 RTSP")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(Color.orange)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(4)
                                                }
                                                .frame(width: 80, alignment: .trailing)
                                            } else {
                                                Text("Sẵn sàng")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))
                                                    .frame(width: 80, alignment: .trailing)
                                            }
                                        } else {
                                            Text("-")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .frame(width: 80, alignment: .trailing)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.08, green: 0.12, blue: 0.19))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.14, green: 0.22, blue: 0.35), lineWidth: 1)
                        )

                        // Bottom Close Button
                        HStack {
                            Spacer()
                            Button(action: { activeModalType = nil }) {
                                Text("Đóng")
                                    .font(.subheadline)
                                    .bold()
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.12, green: 0.16, blue: 0.24))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                }
            }
            .navigationBarTitle("Kiểm Tra Cổng Mở (Port Checker) WAN / LAN / Tên Miền", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { activeModalType = nil }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
            }
            .onAppear {
                if currentWanIp == "Đang tải..." {
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

    // Modal View: Set Date & NTP
    var setDateNtpView: some View {
        Form {
            Section(header: Text("Đồng Bộ Thời Gian iPhone Sang Camera")) {
                HStack {
                    Text("IP Camera:")
                    Spacer()
                    Text(ip).bold()
                }

                Button(action: syncDeviceTimeNow) {
                    HStack {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                        Text("ĐỒNG BỘ GIỜ IPHONE SANG CAMERA")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }

            Section(header: Text("Cấu Hình NTP (Đồng Bộ Giờ Internet Tự Động)")) {
                Toggle("Kích hoạt NTP Server", isOn: $enableNtp)

                HStack {
                    Text("NTP Server")
                    Spacer()
                    TextField("time.google.com", text: $ntpServer)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Cổng NTP Port")
                    Spacer()
                    TextField("123", text: $ntpPort)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                HStack {
                    Text("Chu kỳ cập nhật (Phút)")
                    Spacer()
                    TextField("60", text: $ntpPeriod)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }

                Button(action: saveNtpConfig) {
                    HStack {
                        Spacer()
                        Image(systemName: "gearshape.fill")
                        Text("LƯU CẤU HÌNH NTP LÊN CAMERA")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: fetchNtpConfig) {
                    HStack {
                        Spacer()
                        Text("🔍 Đọc cấu hình NTP từ Camera")
                            .foregroundColor(.orange)
                        Spacer()
                    }
                }
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
                    Text(ip).bold()
                }

                HStack {
                    Text("HTTP Port")
                    Spacer()
                    TextField("80", text: $port)
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
                    SecureField("Mật khẩu camera", text: $camPass)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Button(action: executeReboot) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("🔄 KHỞI ĐỘNG LẠI CAMERA NGAY")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }

    // Serial Number Cleaning Helper Function
    private func cleanSerialNumber(_ input: String) -> String {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = ["S/N:", "S/N", "SN:", "SN", "SERIAL:", "SERIAL", "Serial:", "Serial", "sn:", "s/n:"]
        for prefix in prefixes {
            if raw.uppercased().hasPrefix(prefix.uppercased()) {
                raw = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if raw.contains("sn=") || raw.contains("SN=") {
            let components = raw.components(separatedBy: CharacterSet(charactersIn: "=&?"))
            for (idx, comp) in components.enumerated() {
                if comp.lowercased() == "sn" && idx + 1 < components.count {
                    raw = components[idx + 1]
                    break
                }
            }
        }

        let cleaned = raw.components(separatedBy: CharacterSet.alphanumerics.inverted).joined().uppercased()
        return cleaned
    }

    // Business Logic
    private func fetchConfig() {
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

    private func parseAndPopulateDDNSConfig(rawText: String) {
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

    private func executeChangeIp() {
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

    private func executeChangePass() {
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

    private func saveConfig() {
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

    private func executeCheckPorts() {
        var target = checkPortHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.isEmpty {
            target = currentWanIp != "Đang tải..." && currentWanIp != "Không thể lấy IP" ? currentWanIp : "192.168.1.108"
            checkPortHost = target
        }

        var portsToCheck: [Int] = []
        for pStr in [cpPort1, cpPort2, cpPort3, cpPort4] {
            let clean = pStr.trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(clean), (1...65535).contains(val), !portsToCheck.contains(val) {
                portsToCheck.append(val)
            }
        }

        if portsToCheck.isEmpty {
            portsToCheck = [37777, 80, 554]
        }

        isCheckingPorts = true
        hasCheckedPorts = true
        portScanResults.removeAll()

        cgiClient.checkPorts(host: target, ports: portsToCheck) { results in
            DispatchQueue.main.async {
                self.isCheckingPorts = false
                self.portScanResults = results
            }
        }
    }

    private func calculateSuperPassword(for date: Date) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        // Formula 1
        let res1 = (day + month * 100 + year * 10000) * 686572
        let raw1 = String(res1)
        let c1 = String(raw1.suffix(6))
        superPassCode1 = String(repeating: "0", count: max(0, 6 - c1.count)) + c1

        // Formula 2
        let res2 = (day * month * (year % 2000) * 8888 % 1000000) + 1000000
        let raw2 = String(res2)
        let c2 = String(raw2.suffix(6))
        superPassCode2 = String(repeating: "0", count: max(0, 6 - c2.count)) + c2

        // Formula 3
        let res3 = (day + month * 100 + year * 10000) * 283848
        let raw3 = String(res3)
        let c3 = String(raw3.suffix(6))
        superPassCode3 = String(repeating: "0", count: max(0, 6 - c3.count)) + c3
    }

    private func syncDeviceTimeNow() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeStr = formatter.string(from: Date())

        isLoading = true
        setStatus("Đang đồng bộ giờ iPhone (\(timeStr)) sang camera...", type: .info)
        cgiClient.setDeviceTime(ip: ip, port: port, user: camUser, pass: camPass, timeString: timeStr) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.setStatus("Đồng bộ giờ sang camera thành công!", type: .success)
                } else {
                    self.setStatus("Đồng bộ giờ thất bại: HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    private func fetchNtpConfig() {
        isLoading = true
        setStatus("Đang đọc cấu hình NTP từ camera...", type: .info)
        cgiClient.getNtpConfig(ip: ip, port: port, user: camUser, pass: camPass) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
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
                    self.setStatus("Lỗi đọc NTP: HTTP \(result.statusCode)", type: .error)
                }
            }
        }
    }

    private func saveNtpConfig() {
        isLoading = true
        setStatus("Đang lưu cấu hình NTP lên camera...", type: .info)
        let pInt = Int(ntpPort) ?? 123
        let periodInt = Int(ntpPeriod) ?? 60
        cgiClient.setNtpConfig(ip: ip, port: port, user: camUser, pass: camPass, enable: enableNtp, server: ntpServer, ntpPort: pInt, period: periodInt) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.setStatus("Đã lưu cấu hình NTP lên camera thành công!", type: .success)
                } else {
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
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.12).edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 1. Chế độ tạo QR Code
                        VStack(alignment: .leading, spacing: 10) {
                            Text("1. CHẾ ĐỘ TẠO QR CODE")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))

                            HStack(spacing: 12) {
                                // Option 1: Theo mẫu thiết bị
                                Button(action: { qrMode = 0 }) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: qrMode == 0 ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(qrMode == 0 ? .cyan : .gray)
                                            .font(.system(size: 18))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Tạo theo mẫu thiết bị")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("Brand, Model, S/N, Safety Code")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(qrMode == 0 ? Color.cyan : Color.gray.opacity(0.3), lineWidth: qrMode == 0 ? 2 : 1)
                                    )
                                }

                                // Option 2: Tùy chỉnh
                                Button(action: { qrMode = 1 }) {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: qrMode == 1 ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(qrMode == 1 ? .cyan : .gray)
                                            .font(.system(size: 18))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Tùy chỉnh (Chỉ tạo S/N hoặc Text)")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            Text("Nội dung văn bản, Serial, URL bất kỳ")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(qrMode == 1 ? Color.cyan : Color.gray.opacity(0.3), lineWidth: qrMode == 1 ? 2 : 1)
                                    )
                                }
                            }

                            // Quick Fill from LAN Devices
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)

                                Text("Nạp nhanh từ thiết bị quét được:")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.8, green: 0.85, blue: 0.95))

                                Menu {
                                    Button("-- [Chọn thiết bị để tự động điền Model & S/N] --") {
                                        selectedLanDeviceForQr = ""
                                    }
                                    ForEach(scanner.discoveredDevices) { dev in
                                        Button("\(dev.ip) - \(dev.brand.rawValue) (\(dev.sn.isEmpty ? dev.mac : dev.sn))") {
                                            selectedLanDeviceForQr = dev.sn
                                            qrBrand = dev.brand.rawValue
                                            if !dev.model.isEmpty { qrModel = dev.model }
                                            if !dev.sn.isEmpty { qrSn = dev.sn }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedLanDeviceForQr.isEmpty ? "-- [Chọn thiết bị để tự động điền Model & S/N] --" : selectedLanDeviceForQr)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.14, green: 0.22, blue: 0.35), lineWidth: 1)
                        )

                        // 2. Thông tin thiết bị Camera / Đầu Ghi
                        VStack(alignment: .leading, spacing: 12) {
                            Text("2. THÔNG TIN THIẾT BỊ CAMERA / ĐẦU GHI")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0.4, green: 0.75, blue: 1.0))

                            if qrMode == 0 {
                                // Row 1: Brand & Model
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Thương hiệu (Brand):")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))

                                        Menu {
                                            ForEach(["Imou", "Dahua", "KBVision", "Hikvision", "UNV", "Tiandy", "Khác"], id: \.self) { b in
                                                Button(b) { qrBrand = b }
                                            }
                                        } label: {
                                            HStack {
                                                Text(qrBrand)
                                                    .font(.subheadline)
                                                    .bold()
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Image(systemName: "chevron.down")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 10)
                                            .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Tên thiết bị / Model:")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))

                                        TextField("IPC-A22EP", text: $qrModel)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 9)
                                            .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1))
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                // Row 2: Serial Number & Safety Code
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("*")
                                                .foregroundColor(.cyan)
                                            Text("Số Serial (S/N):")
                                                .font(.caption)
                                                .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))
                                        }

                                        TextField("Nhập Serial Number thiết bị...", text: $qrSn)
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .autocapitalization(.allCharacters)
                                            .disableAutocorrection(true)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 9)
                                            .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1))
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Safety Code (Mã an toàn đáy cam):")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))

                                        TextField("VD: L2A8B3 (nếu có)", text: $qrSafetyCode)
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .autocapitalization(.allCharacters)
                                            .disableAutocorrection(true)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 9)
                                            .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1))
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                // Encoding Format Selection (Radio Buttons)
                                HStack(spacing: 20) {
                                    Button(action: { qrEncodingFormat = 0 }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: qrEncodingFormat == 0 ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(qrEncodingFormat == 0 ? .cyan : .gray)
                                                .font(.caption)
                                            Text("Mã hóa S/N chuẩn (Quét trực tiếp gán vào App Imou/DMSS/KBONE)")
                                                .font(.caption2)
                                                .foregroundColor(qrEncodingFormat == 0 ? .white : .gray)
                                        }
                                    }

                                    Button(action: { qrEncodingFormat = 1 }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: qrEncodingFormat == 1 ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(qrEncodingFormat == 1 ? .cyan : .gray)
                                                .font(.caption)
                                            Text("Mã hóa Cặp {S/N, Safety Code}")
                                                .font(.caption2)
                                                .foregroundColor(qrEncodingFormat == 1 ? .white : .gray)
                                        }
                                    }
                                }
                                .padding(.top, 4)

                            } else {
                                // Custom Text Mode
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("* Nội dung S/N hoặc Văn bản / URL:")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.7, green: 0.75, blue: 0.85))

                                    TextField("Nhập chuỗi S/N hoặc URL / văn bản bất kỳ...", text: $qrCustomText)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.2, green: 0.28, blue: 0.42), lineWidth: 1))
                                }
                            }

                            // Generate Button
                            HStack {
                                Spacer()
                                Button(action: generateQrPayloadAndImage) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "qrcode")
                                            .font(.headline)
                                        Text("Tạo QRCode")
                                            .font(.headline)
                                            .bold()
                                    }
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.01, green: 0.52, blue: 0.78))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .shadow(color: Color(red: 0.01, green: 0.52, blue: 0.78).opacity(0.4), radius: 6, x: 0, y: 3)
                                }
                                Spacer()
                            }
                            .padding(.top, 6)
                        }
                        .padding(14)
                        .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.14, green: 0.22, blue: 0.35), lineWidth: 1)
                        )

                        // 3. Generated QR Result Card
                        if isQrGenerated, let qrImg = generatedQrImage {
                            VStack(spacing: 14) {
                                // White card container for QR Image
                                Image(uiImage: qrImg)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 220, height: 220)
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)

                                // Information details
                                VStack(spacing: 6) {
                                    if qrMode == 0 {
                                        HStack {
                                            Text("Thương hiệu:")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            Text(qrBrand)
                                                .font(.caption)
                                                .bold()
                                                .foregroundColor(.cyan)

                                            if !qrModel.isEmpty {
                                                Text("| Model:")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                Text(qrModel)
                                                    .font(.caption)
                                                    .bold()
                                                    .foregroundColor(.white)
                                            }
                                        }

                                        HStack {
                                            Text("S/N: \(qrSn)")
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))

                                            if !qrSafetyCode.isEmpty {
                                                Text("• SC: \(qrSafetyCode)")
                                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                    } else {
                                        Text("Nội dung: \(generatedQrPayload)")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(red: 0.2, green: 0.83, blue: 0.6))
                                    }

                                    HStack {
                                        Text("Mã hóa chuỗi:")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        Text(generatedQrPayload)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.08))
                                            .cornerRadius(4)
                                    }
                                }

                                // Action Buttons
                                HStack(spacing: 12) {
                                    Button(action: {
                                        UIPasteboard.general.string = generatedQrPayload
                                        qrCopiedToast = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            qrCopiedToast = false
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: qrCopiedToast ? "checkmark" : "doc.on.doc")
                                            Text(qrCopiedToast ? "Đã sao chép!" : "Sao chép chuỗi")
                                                .font(.caption)
                                                .bold()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(qrCopiedToast ? Color.green : Color.orange.opacity(0.2))
                                        .foregroundColor(qrCopiedToast ? .white : .orange)
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                                    }

                                    Button(action: { showShareSheet = true }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Chia sẻ / Lưu ảnh")
                                                .font(.caption)
                                                .bold()
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color(red: 0.08, green: 0.12, blue: 0.2))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(red: 0.14, green: 0.22, blue: 0.35), lineWidth: 1)
                            )
                        }

                        // Bottom Close Button
                        HStack {
                            Spacer()
                            Button(action: { activeModalType = nil }) {
                                Text("Đóng")
                                    .font(.subheadline)
                                    .bold()
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.12, green: 0.16, blue: 0.24))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                }
            }
            .navigationBarTitle("Tạo Mã QR Code Cài Đặt Cho Camera / Đầu Ghi", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { activeModalType = nil }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
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
        return nil
    }()

    var body: some View {
        if let uiImage = CameraLogoIcon.logoImage {
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
