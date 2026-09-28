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
    @State private var ip: String = "192.168.1.108"
    @State private var port: String = "80"
    @State private var camUser: String = "admin"
    @State private var camPass: String = ""
    
    @State private var selectedPresetIndex: Int = 0
    @State private var serverAddr: String = "fastddns.net"
    @State private var domain: String = "mycam.fastddns.net"
    @State private var ddnsUser: String = ""
    @State private var ddnsPass: String = ""
    @State private var enableDdns: Bool = true
    @State private var selectedChannelIdx: String = "0"
    @State private var availableChannels: [(name: String, idx: String)] = [("Kênh mặc định [0]", "0")]

    @State private var isLoading: Bool = false
    @State private var statusMessage: String = "Sẵn sàng kết nối tới đầu ghi Dahua."
    @State private var statusType: StatusType = .info
    @State private var logHistory: String = "Ứng dụng Dahua Free DDNS iOS đã sẵn sàng.\n"
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

    var body: some View {
        NavigationView {
            Form {
                // Section 1: Thông tin kết nối Camera / Đầu ghi
                Section(header: Text("Thông tin Camera / Đầu ghi Dahua").font(.headline)) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        TextField("Địa chỉ IP (VD: 192.168.1.108)", text: $ip)
                            .keyboardType(.decimalPad)
                            .autocapitalization(.none)
                    }
                    
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(.blue)
                        TextField("Cổng HTTP (VD: 80)", text: $port)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.blue)
                        TextField("Tài khoản Camera (admin)", text: $camUser)
                            .autocapitalization(.none)
                    }

                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.blue)
                        SecureField("Mật khẩu Camera", text: $camPass)
                    }
                }

                // Section 2: Cấu hình Free DDNS
                Section(header: Text("Cấu hình Free DDNS").font(.headline)) {
                    Picker("Chọn nhà cung cấp DDNS", selection: $selectedPresetIndex) {
                        ForEach(0..<freeDdnsPresets.count, id: \.self) { index in
                            Text(freeDdnsPresets[index].name).tag(index)
                        }
                    }
                    .onChange(of: selectedPresetIndex) { newIndex in
                        let preset = freeDdnsPresets[newIndex]
                        if !preset.server.isEmpty {
                            serverAddr = preset.server
                        }
                    }

                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.orange)
                        TextField("Máy chủ DDNS (Server)", text: $serverAddr)
                            .autocapitalization(.none)
                    }

                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.orange)
                        TextField("Tên miền (Domain)", text: $domain)
                            .autocapitalization(.none)
                    }

                    HStack {
                        Image(systemName: "person.badge.key")
                            .foregroundColor(.orange)
                        TextField("DDNS Username (Nếu có)", text: $ddnsUser)
                            .autocapitalization(.none)
                    }

                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.orange)
                        SecureField("DDNS Password (Nếu có)", text: $ddnsPass)
                    }

                    Toggle(isOn: $enableDdns) {
                        HStack {
                            Image(systemName: "power")
                                .foregroundColor(enableDdns ? .green : .gray)
                            Text("Kích hoạt DDNS (Enable)")
                        }
                    }
                }

                // Section 3: Thao tác & Hành động
                Section {
                    Button(action: saveConfig) {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 5)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("CÀI ĐẶT FREE DDNS")
                                .bold()
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

                // Section 4: Trạng thái & Nhật ký
                Section(header: Text("Trạng thái & Nhật ký hoạt động").font(.headline)) {
                    HStack {
                        Circle()
                            .fill(statusType.color)
                            .frame(width: 10, height: 10)
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(statusType.color)
                    }

                    ScrollView {
                        Text(logHistory)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                }
            }
            .navigationTitle("Dahua Free DDNS")
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
                    self.parseAndApplyChannelData(text: result.rawText)
                    self.setStatus("Đã đọc xong cấu hình DDNS từ camera!", type: .success)
                } else {
                    let errDesc = result.errorMessage ?? "Lỗi HTTP status: \(result.statusCode)"
                    self.appendLog("Lỗi: \(errDesc)")
                    self.setStatus("Không thể lấy cấu hình: \(errDesc)", type: .error)
                }
            }
        }
    }

    private func saveConfig() {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = camUser.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanIp.isEmpty || cleanPort.isEmpty || cleanUser.isEmpty {
            setStatus("Vui lòng nhập IP, Port và User camera!", type: .error)
            return
        }
        if cleanDomain.isEmpty {
            setStatus("Vui lòng nhập Tên miền (Domain)!", type: .error)
            return
        }

        isLoading = true
        setStatus("Đang lưu cấu hình DDNS lên camera...", type: .info)
        appendLog("Cập nhật Free DDNS cho camera [\(cleanIp)]...")

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

    private func parseAndApplyChannelData(text: String) {
        let prefix = "table.DDNS[\(selectedChannelIdx)]."
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(prefix) {
                let parts = trimmed.dropFirst(prefix.count).components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    switch key {
                    case "Enable":
                        self.enableDdns = value.lowercased() == "true"
                    case "Address":
                        self.serverAddr = value
                    case "HostName":
                        self.domain = value
                    case "UserName", "User":
                        self.ddnsUser = value
                    case "Password", "Pass":
                        self.ddnsPass = value
                    default:
                        break
                    }
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
