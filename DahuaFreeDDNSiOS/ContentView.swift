import SwiftUI

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

struct ContentView: View {
    @StateObject private var scanner = LanScanner()
    @State private var selectedTab = 0

    // Selected Device for Action Modal
    @State private var activeDevice: CameraDevice? = nil
    @State private var showActionSheet = false
    @State private var activeModalType: ModalType? = nil

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
        NavigationView {
            VStack(spacing: 0) {
                Picker("Chức năng", selection: $selectedTab) {
                    Text("Quét IP LAN").tag(0)
                    Text("Set DDNS Thủ Công").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                if selectedTab == 0 {
                    scanView
                } else {
                    ddnsFormView
                }
            }
            .navigationTitle("Dahua & Imou Manager")
            .actionSheet(isPresented: $showActionSheet) {
                ActionSheet(
                    title: Text("Thao tác thiết bị [\(activeDevice?.ip ?? "")]"),
                    message: Text("Hãng: \(activeDevice?.brand.rawValue ?? "Camera")"),
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
    }

    // TAB 1: Scan LAN View
    var scanView: some View {
        List {
            Section {
                Button(action: { scanner.startScan() }) {
                    HStack {
                        Spacer()
                        if scanner.isScanning {
                            ProgressView().padding(.trailing, 8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(scanner.isScanning ? "ĐANG QUÉT MẠNG LAN..." : "BẮT ĐẦU QUÉT IP CAMERA")
                            .bold()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(scanner.isScanning ? Color.gray : Color.blue)
                    .cornerRadius(10)
                }
                .disabled(scanner.isScanning)

                if scanner.isScanning {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: scanner.progress)
                        Text(scanner.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Danh sách thiết bị quét được (\(scanner.discoveredDevices.count))")) {
                if scanner.discoveredDevices.isEmpty && !scanner.isScanning {
                    Text("Chưa tìm thấy camera nào. Nhấn Bắt đầu quét để tìm thiết bị trong LAN.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(0..<scanner.discoveredDevices.count, id: \.self) { idx in
                        let dev = scanner.discoveredDevices[idx]
                        HStack(alignment: .center, spacing: 12) {
                            if dev.brand == .dahua || dev.brand == .imou {
                                CameraLogoIcon(brand: dev.brand)
                            } else {
                                Text(dev.brand.rawValue)
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(badgeColor(for: dev.brand))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(dev.ip):\(dev.port)")
                                    .font(.headline)

                                if !dev.sn.isEmpty {
                                    Text("🔵 S/N: \(dev.sn)")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(.blue)
                                }

                                if !dev.model.isEmpty {
                                    Text("⚙️ Model: \(dev.model)")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }

                                if !dev.mac.isEmpty {
                                    Text("📶 MAC: \(dev.mac)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if !dev.extraInfo.isEmpty {
                                    Text("Giao thức: \(dev.extraInfo)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }

                            Spacer()

                            // Display Gear/Settings icon for Dahua, Imou & IP Camera
                            if dev.brand.isConfigurable {
                                Button(action: {
                                    self.activeDevice = dev
                                    self.showActionSheet = true
                                }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                        .padding(8)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(GroupedListStyle())
    }

    // TAB 2: DDNS Form View
    var ddnsFormView: some View {
        Form {
            Section(header: Text("Thông tin Camera Dahua & Imou")) {
                HStack {
                    Image(systemName: "network").foregroundColor(.blue)
                    TextField("Địa chỉ IP (192.168.1.108)", text: $ip)
                }
                HStack {
                    Image(systemName: "number").foregroundColor(.blue)
                    TextField("Cổng HTTP (80)", text: $port)
                }
                HStack {
                    Image(systemName: "person.fill").foregroundColor(.blue)
                    TextField("Tài khoản Camera (admin)", text: $camUser)
                }
                HStack {
                    Image(systemName: "lock.fill").foregroundColor(.blue)
                    SecureField("Mật khẩu Camera", text: $camPass)
                }
            }

            Section(header: Text("Cấu hình Free DDNS")) {
                Picker("Nhà cung cấp DDNS", selection: $selectedPresetIndex) {
                    ForEach(0..<freeDdnsPresets.count, id: \.self) { i in
                        Text(freeDdnsPresets[i].name).tag(i)
                    }
                }
                .onChange(of: selectedPresetIndex) { i in
                    if !freeDdnsPresets[i].server.isEmpty {
                        serverAddr = freeDdnsPresets[i].server
                    }
                }

                HStack {
                    Image(systemName: "server.rack").foregroundColor(.orange)
                    TextField("Máy chủ DDNS", text: $serverAddr)
                }
                HStack {
                    Image(systemName: "link").foregroundColor(.orange)
                    TextField("Tên miền (Domain)", text: $domain)
                }
                HStack {
                    Image(systemName: "person.badge.key").foregroundColor(.orange)
                    TextField("DDNS Username (Nếu có)", text: $ddnsUser)
                }
                HStack {
                    Image(systemName: "key.fill").foregroundColor(.orange)
                    SecureField("DDNS Password (Nếu có)", text: $ddnsPass)
                }
                Toggle("Kích hoạt DDNS", isOn: $enableDdns)
            }

            Section {
                Button(action: saveConfig) {
                    HStack {
                        Spacer()
                        if isLoading { ProgressView().padding(.trailing, 4) }
                        Image(systemName: "checkmark.circle.fill")
                        Text("CÀI ĐẶT FREE DDNS").bold()
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(isLoading ? Color.gray : Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isLoading)

                Button(action: fetchConfig) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.clockwise")
                        Text("Đọc cấu hình từ Camera")
                        Spacer()
                    }
                }
                .disabled(isLoading)
            }

            Section(header: Text("Trạng thái & Log")) {
                HStack {
                    Circle().fill(statusType.color).frame(width: 10, height: 10)
                    Text(statusMessage).font(.subheadline).foregroundColor(statusType.color)
                }
                ScrollView {
                    Text(logHistory)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 100)
            }
        }
    }

    // Modal: Change IP View
    var changeIpView: some View {
        Form {
            Section(header: Text("Thông tin IP hiện tại: \(ip)")) {
                HStack {
                    Text("IP Mới:")
                    TextField("192.168.1.120", text: $newIp)
                }
                HStack {
                    Text("Subnet Mask:")
                    TextField("255.255.255.0", text: $subnetMask)
                }
                HStack {
                    Text("Gateway:")
                    TextField("192.168.1.1", text: $gateway)
                }
                HStack {
                    Text("User Camera:")
                    TextField("admin", text: $camUser)
                }
                HStack {
                    Text("Pass Camera:")
                    SecureField("Mật khẩu camera", text: $camPass)
                }
            }

            Section {
                Button(action: executeChangeIp) {
                    HStack {
                        Spacer()
                        Image(systemName: "network")
                        Text("CẬP NHẬT IP MỚI VIA DIGEST AUTH").bold()
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }

            Section(header: Text("Trạng thái")) {
                HStack {
                    Circle().fill(statusType.color).frame(width: 10, height: 10)
                    Text(statusMessage).font(.subheadline).foregroundColor(statusType.color)
                }
            }
        }
    }

    // Modal: Change Password View
    var changePassView: some View {
        Form {
            Section(header: Text("Đổi mật khẩu camera IP: \(ip)")) {
                HStack {
                    Text("Tài khoản:")
                    TextField("admin", text: $camUser)
                }
                HStack {
                    Text("Mật khẩu cũ:")
                    SecureField("Nhập mật khẩu cũ", text: $oldPass)
                }
                HStack {
                    Text("Mật khẩu mới:")
                    SecureField("Nhập mật khẩu mới", text: $newPass)
                }
                HStack {
                    Text("Xác nhận MK mới:")
                    SecureField("Nhập lại mật khẩu mới", text: $confirmPass)
                }
            }

            Section {
                Button(action: executeChangePassword) {
                    HStack {
                        Spacer()
                        Image(systemName: "key.fill")
                        Text("CẬP NHẬT MẬT KHẨU MỚI").bold()
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
                }
            }

            Section(header: Text("Trạng thái")) {
                HStack {
                    Circle().fill(statusType.color).frame(width: 10, height: 10)
                    Text(statusMessage).font(.subheadline).foregroundColor(statusType.color)
                }
            }
        }
    }

    private func badgeColor(for brand: CameraBrand) -> Color {
        switch brand {
        case .dahua: return .red
        case .imou: return .orange
        case .hikvision: return .pink
        case .unv: return .blue
        case .seetong: return .green
        case .tiandy: return .purple
        case .onvif: return .teal
        case .unknown: return .gray
        }
    }

    private func executeChangeIp() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNewIp = newIp.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = camUser.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanNewIp.isEmpty || cleanUser.isEmpty {
            setStatus("Vui lòng nhập IP mới và tài khoản camera!", type: .error)
            return
        }
        setStatus("Đang gửi lệnh đổi IP sang \(cleanNewIp)...", type: .info)

        cgiClient.changeIp(
            ip: cleanIp,
            port: port,
            user: cleanUser,
            pass: camPass,
            newIp: cleanNewIp,
            subnet: subnetMask,
            gateway: gateway
        ) { result in
            DispatchQueue.main.async {
                if result.success && (result.rawText.contains("OK") || result.rawText.contains("true")) {
                    self.setStatus("Đã đổi IP thành công sang \(cleanNewIp)! 🎉", type: .success)
                    self.appendLog("Đã đổi IP từ \(cleanIp) sang \(cleanNewIp). Camera sẽ nhận IP mới!")
                    self.ip = cleanNewIp
                    self.activeModalType = nil
                } else if result.success {
                    self.setStatus("Phản hồi camera: \(result.rawText)", type: .success)
                    self.ip = cleanNewIp
                    self.activeModalType = nil
                } else {
                    let err = "Lỗi đổi IP: HTTP \(result.statusCode) (\(result.errorMessage ?? ""))"
                    self.setStatus(err, type: .error)
                    self.appendLog(err)
                }
            }
        }
    }

    private func executeChangePassword() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = camUser.trimmingCharacters(in: .whitespacesAndNewlines)

        if newPass.isEmpty || newPass != confirmPass {
            setStatus("Mật khẩu mới không trùng khớp!", type: .error)
            return
        }
        setStatus("Đang gửi lệnh đổi mật khẩu...", type: .info)

        cgiClient.changePassword(
            ip: cleanIp,
            port: port,
            user: cleanUser,
            oldPass: oldPass,
            newPass: newPass
        ) { result in
            DispatchQueue.main.async {
                if result.success && (result.rawText.contains("OK") || result.rawText.contains("true")) {
                    self.setStatus("Đã đổi mật khẩu thành công! 🎉", type: .success)
                    self.appendLog("Đã đổi mật khẩu camera [\(cleanIp)] thành công!")
                    self.camPass = self.newPass
                    self.activeModalType = nil
                } else {
                    let err = "Lỗi đổi mật khẩu: HTTP \(result.statusCode) (\(result.errorMessage ?? ""))"
                    self.setStatus(err, type: .error)
                    self.appendLog(err)
                }
            }
        }
    }

    private func fetchConfig() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = camUser.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanIp.isEmpty || cleanPort.isEmpty || cleanUser.isEmpty {
            setStatus("Vui lòng nhập IP, Port và User camera!", type: .error)
            return
        }

        isLoading = true
        setStatus("Đang đọc cấu hình từ camera...", type: .info)
        appendLog("GET http://\(cleanIp):\(cleanPort)/cgi-bin/configManager.cgi?action=getConfig&name=DDNS")

        cgiClient.fetchDahuaConfig(ip: cleanIp, port: cleanPort, user: cleanUser, pass: camPass) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                if result.success {
                    self.appendLog("Thành công (HTTP \(result.statusCode)):\n\(result.rawText)")
                    self.rawFetchedConfig = result.rawText
                    self.parseAndPopulateDDNSConfig(result.rawText)
                    self.setStatus("Đã đọc và dán thành công cấu hình DDNS vào form! 🎉", type: .success)
                } else {
                    let errDesc = result.errorMessage ?? "Lỗi HTTP status: \(result.statusCode)"
                    self.appendLog("Lỗi: \(errDesc)")
                    self.setStatus("Không thể lấy cấu hình: \(errDesc)", type: .error)
                }
            }
        }
    }

    private func parseAndPopulateDDNSConfig(_ rawText: String) {
        let lines = rawText.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("=") {
                let parts = trimmed.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)

                    if key.contains(".Address") && !value.isEmpty {
                        self.serverAddr = value
                    } else if key.contains(".HostName") && !value.isEmpty {
                        self.domain = value
                    } else if (key.contains(".User") || key.contains(".UserName")) && !value.isEmpty {
                        self.ddnsUser = value
                    } else if (key.contains(".Pass") || key.contains(".Password")) && !value.isEmpty {
                        self.ddnsPass = value
                    } else if key.contains(".Enable") {
                        self.enableDdns = value.lowercased() == "true"
                    }
                }
            }
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

struct CameraLogoIcon: View {
    let brand: CameraBrand

    var body: some View {
        if let path = Bundle.main.path(forResource: "logo", ofType: "png") ?? Bundle.main.path(forResource: "camera_logo", ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
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
