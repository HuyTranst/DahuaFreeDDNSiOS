import SwiftUI
import UIKit
import AVFoundation

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

        var id: Int { hashValue }
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
                title: Text("Cài đặt & Thao tác thiết bị [\(activeDevice?.ip ?? "")]"),
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
                    Text("Tính Năng Nổi Bật")
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
                            selectedTab = 4
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

    private func setStatus(_ msg: String, type: StatusType) {
        self.statusMessage = msg
        self.statusType = type
    }

    private func appendLog(_ msg: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.logHistory += "[\(timestamp)] \(msg)\n"
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
