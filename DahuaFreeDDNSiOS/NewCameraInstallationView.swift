import SwiftUI
import Network

// MARK: - New Camera Installation View (Tìm Camera Mới Lắp)
struct NewCameraInstallationView: View {
    @ObservedObject var invoiceMgr = InvoiceManager.shared
    @Environment(\.presentationMode) var presentationMode

    // Two LanScanner instances for Scan 1 and Scan 2
    @StateObject private var scanner1 = LanScanner()
    @StateObject private var scanner2 = LanScanner()

    @State private var list1Devices: [CameraDevice] = []
    @State private var list2Devices: [CameraDevice] = []
    @State private var hasScanned2: Bool = false

    // Location state
    @State private var installLocation: String = ""
    @State private var installGoogleUrl: String = ""
    @State private var isFetchingLocation: Bool = false

    // Modals
    @State private var showSaveModal: Bool = false
    @State private var showHistoryModal: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    // Customer Save Form
    @State private var customerName: String = ""
    @State private var customerPhone: String = ""
    @State private var installNotes: String = ""

    // Computed diff between Scan 1 and Scan 2
    var newlyAddedCameras: [CameraDevice] {
        guard hasScanned2 else { return [] }
        return list2Devices.filter { d2 in
            !list1Devices.contains { d1 in
                d1.serialNo == d2.serialNo || d1.ip == d2.ip
            }
        }
    }

    var missingCameras: [CameraDevice] {
        guard hasScanned2 else { return [] }
        return list1Devices.filter { d1 in
            !list2Devices.contains { d2 in
                d2.serialNo == d1.serialNo || d2.ip == d1.ip
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Banner
                headerBanner

                // Difference Alert Banner (After Scan 2)
                if hasScanned2 {
                    comparisonResultBanner
                }

                // Section 1: Quét trước khi gắn camera
                sectionScan1

                // Section 2: Quét sau khi lắp camera
                sectionScan2

                // Location info card (if fetched)
                locationInfoCard

                // Bottom Action Buttons
                bottomActionBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gray.opacity(0.06).edgesIgnoringSafeArea(.all))
        .navigationTitle("Tìm Camera Mới Lắp")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showHistoryModal = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Lịch Sử (\(invoiceMgr.savedInstallRecords.count))")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showSaveModal) {
            saveInstallModalView
        }
        .sheet(isPresented: $showHistoryModal) {
            InstallHistoryModalView(invoiceMgr: invoiceMgr)
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Header Banner
    private var headerBanner: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.85)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(14)

            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.title3)
                            .foregroundColor(.white)
                        Text("Tìm Camera Mới Lắp (Diff Scanner)")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                    }

                    Text("Quét lần 1 trước khi gắn camera, sau đó quét lần 2 sau khi gắn để phát hiện chính xác camera mới xuất hiện (IP, S/N, Model).")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(3)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    // MARK: - Comparison Result Banner
    private var comparisonResultBanner: some View {
        VStack(spacing: 10) {
            if !newlyAddedCameras.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        Text("PHÁT HIỆN \(newlyAddedCameras.count) CAMERA MỚI LẮP!")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.green)
                        Spacer()
                    }

                    ForEach(newlyAddedCameras) { cam in
                        HStack(spacing: 8) {
                            Text(cam.brand.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(cam.brand.color)
                                .cornerRadius(4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(cam.machineName) (\(cam.ip))")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.primary)
                                Text("S/N: \(cam.serialNo)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.5), lineWidth: 1.5))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Không phát hiện camera mới nào xuất hiện so với lần quét 1.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(10)
            }

            if !missingCameras.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Có \(missingCameras.count) camera bị mất kết nối so với lần 1:")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.red)
                    }

                    ForEach(missingCameras) { cam in
                        Text("• \(cam.machineName) - IP: \(cam.ip) (S/N: \(cam.serialNo))")
                            .font(.caption2)
                            .foregroundColor(.red.opacity(0.85))
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.06))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Section 1: Quét Trước Khi Gắn
    private var sectionScan1: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 24, height: 24)
                    Text("1").font(.caption.weight(.bold)).foregroundColor(.white)
                }

                Text("Quét Trước Khi Gắn Camera")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Spacer()

                Text("(\(list1Devices.count) camera)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: startScan1) {
                HStack {
                    if scanner1.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Đang quét lần 1...")
                    } else {
                        Image(systemName: "radar")
                        Text(list1Devices.isEmpty ? "Quét trước khi gắn camera (Lần 1)" : "Quét lại lần 1")
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(scanner1.isScanning ? Color.gray : Color.blue)
                .cornerRadius(8)
            }
            .disabled(scanner1.isScanning || scanner2.isScanning)

            if !list1Devices.isEmpty {
                VStack(spacing: 6) {
                    ForEach(list1Devices) { cam in
                        cameraItemRow(cam)
                    }
                }
            } else if !scanner1.isScanning {
                Text("Chưa quét hoặc chưa phát hiện camera nào trong LAN.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
    }

    // MARK: - Section 2: Quét Sau Khi Gắn
    private var sectionScan2: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().fill(Color.orange).frame(width: 24, height: 24)
                    Text("2").font(.caption.weight(.bold)).foregroundColor(.white)
                }

                Text("Quét Sau Khi Lắp Camera")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)

                Spacer()

                Text("(\(list2Devices.count) camera)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: startScan2) {
                HStack {
                    if scanner2.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Đang quét lần 2...")
                    } else {
                        Image(systemName: "camera.viewfinder")
                        Text(list2Devices.isEmpty ? "Quét sau khi lắp camera (Lần 2)" : "Quét lại lần 2")
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(scanner2.isScanning ? Color.gray : Color.orange)
                .cornerRadius(8)
            }
            .disabled(scanner1.isScanning || scanner2.isScanning)

            if !list2Devices.isEmpty {
                VStack(spacing: 6) {
                    ForEach(list2Devices) { cam in
                        let isNew = !list1Devices.contains { $0.serialNo == cam.serialNo || $0.ip == cam.ip }
                        cameraItemRow(cam, isNew: isNew)
                    }
                }
            } else if !scanner2.isScanning {
                Text("Gắn camera mới vào mạng rồi bấm nút để quét so sánh.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3, y: 1)
    }

    // MARK: - Camera Item Row Helper
    private func cameraItemRow(_ cam: CameraDevice, isNew: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(cam.brand.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(cam.brand.color)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(cam.machineName)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                    if isNew {
                        Text("MỚI")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green)
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 8) {
                    Text("IP: \(cam.ip)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("S/N: \(cam.serialNo)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(isNew ? Color.green.opacity(0.08) : Color.gray.opacity(0.04))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isNew ? Color.green : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Location Info Card
    @ViewBuilder
    private var locationInfoCard: some View {
        if !installLocation.isEmpty || !installGoogleUrl.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "globe.asia.australia.fill")
                    .foregroundColor(.green)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Vị trí Google Maps:")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                    Text(installLocation)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if let url = URL(string: installGoogleUrl), !installGoogleUrl.isEmpty {
                    Button(action: { UIApplication.shared.open(url) }) {
                        Text("Mở Map")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(10)
        }
    }

    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Button Lấy vị trí
                Button(action: fetchLocation) {
                    HStack(spacing: 4) {
                        if isFetchingLocation {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text("Lấy Vị Trí")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(10)
                }

                // Button Lưu Thông Tin
                Button(action: {
                    if list2Devices.isEmpty && list1Devices.isEmpty {
                        alertMessage = "Vui lòng quét camera trước khi lưu thông tin!"
                        showAlert = true
                        return
                    }
                    showSaveModal = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Lưu Thông Tin")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(10)
                }
            }

            // Button Xem Lịch Sử
            Button(action: { showHistoryModal = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle.fill")
                    Text("Xem Lịch Sử Lắp Đặt")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Save Modal View
    private var saveInstallModalView: some View {
        NavigationView {
            Form {
                Section(header: Text("Thông tin khách hàng")) {
                    HStack {
                        Image(systemName: "person.fill").foregroundColor(.orange).frame(width: 20)
                        TextField("Tên khách hàng *", text: $customerName)
                    }

                    HStack {
                        Image(systemName: "phone.fill").foregroundColor(.orange).frame(width: 20)
                        TextField("Số điện thoại (không bắt buộc)", text: $customerPhone)
                            .keyboardType(.phonePad)
                    }

                    HStack {
                        Image(systemName: "note.text").foregroundColor(.orange).frame(width: 20)
                        TextField("Ghi chú lắp đặt", text: $installNotes)
                    }
                }

                Section(header: Text("Dữ liệu lắp đặt hôm nay")) {
                    HStack {
                        Text("Ngày lắp:")
                            .font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))
                            .font(.subheadline.weight(.medium))
                    }

                    HStack {
                        Text("Số lượng camera:")
                            .font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        let count = list2Devices.isEmpty ? list1Devices.count : list2Devices.count
                        Text("\(count) camera")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.orange)
                    }

                    if !installLocation.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vị trí Google:")
                                .font(.caption).foregroundColor(.secondary)
                            Text(installLocation)
                                .font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("Lưu Thông Tin Lắp Đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { showSaveModal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveInstallation()
                    }
                    .font(.headline)
                    .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Scan Actions
    private func startScan1() {
        scanner1.startScan(timeout: 6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
            self.list1Devices = self.scanner1.discoveredDevices
        }
    }

    private func startScan2() {
        scanner2.startScan(timeout: 6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
            self.list2Devices = self.scanner2.discoveredDevices
            self.hasScanned2 = true
        }
    }

    private func fetchLocation() {
        isFetchingLocation = true
        LocationManager.shared.requestCurrentLocation { result in
            DispatchQueue.main.async {
                self.isFetchingLocation = false
                switch result {
                case .success(let data):
                    self.installLocation = data.address
                    self.installGoogleUrl = data.url
                case .failure(let err):
                    self.alertMessage = err
                    self.showAlert = true
                }
            }
        }
    }

    private func saveInstallation() {
        let trimmedName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            alertMessage = "Vui lòng nhập Tên khách hàng!"
            showAlert = true
            return
        }

        let sourceDevices = list2Devices.isEmpty ? list1Devices : list2Devices
        let cameraItems = sourceDevices.map { dev in
            InstalledCameraItem(
                ip: dev.ip,
                serialNo: dev.serialNo,
                model: dev.machineName,
                mac: dev.mac,
                brand: dev.brand.rawValue
            )
        }

        let record = CameraInstallRecord(
            customerName: trimmedName,
            customerPhone: customerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            date: Date(),
            googleLocation: installLocation,
            googleLocationUrl: installGoogleUrl,
            cameras: cameraItems,
            notes: installNotes,
            createdAt: Date()
        )

        invoiceMgr.addInstallRecord(record)
        showSaveModal = false
        alertMessage = "✅ Đã lưu thông tin lắp đặt cho khách hàng \(trimmedName) thành công!"
        showAlert = true
    }
}

// MARK: - Install History Modal View (Xem Lịch Sử Lắp Đặt)
struct InstallHistoryModalView: View {
    @ObservedObject var invoiceMgr: InvoiceManager
    @Environment(\.presentationMode) var presentationMode

    @State private var searchText: String = ""
    @State private var selectedRecord: CameraInstallRecord? = nil

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df
    }()

    var filteredRecords: [CameraInstallRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return invoiceMgr.savedInstallRecords
        }
        return invoiceMgr.savedInstallRecords.filter { rec in
            rec.customerName.lowercased().contains(q) ||
            rec.customerPhone.lowercased().contains(q) ||
            rec.googleLocation.lowercased().contains(q) ||
            rec.cameras.contains { cam in
                cam.serialNo.lowercased().contains(q) ||
                cam.model.lowercased().contains(q) ||
                cam.ip.lowercased().contains(q)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Tìm theo tên khách, S/N, SĐT...", text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                List {
                    if invoiceMgr.savedInstallRecords.isEmpty {
                        Text("Chưa có lịch sử lắp đặt nào được lưu.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    } else if filteredRecords.isEmpty {
                        Text("Không tìm thấy kết quả phù hợp với: \"\(searchText)\"")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredRecords) { rec in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(rec.customerName)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(dateFormatter.string(from: rec.date))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text(rec.customerPhone.isEmpty ? "Không có SĐT" : "SĐT: \(rec.customerPhone)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(rec.cameras.count) camera")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.orange)
                                }

                                if !rec.googleLocation.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.fill")
                                            .foregroundColor(.blue)
                                            .font(.caption2)
                                        Text(rec.googleLocation)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedRecord = rec
                            }
                        }
                        .onDelete(perform: invoiceMgr.deleteInstallRecord)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Lịch Sử Lắp Đặt Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(item: $selectedRecord) { rec in
                InstallRecordDetailModalView(record: rec)
            }
        }
    }
}

// MARK: - Install Record Detail Modal View (Xem Chi Tiết Lần Lắp)
struct InstallRecordDetailModalView: View {
    let record: CameraInstallRecord
    @Environment(\.presentationMode) var presentationMode

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df
    }()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Customer & Time Info Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("THÔNG TIN KHÁCH HÀNG")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Khách hàng:").foregroundColor(.secondary).font(.subheadline)
                            Text(record.customerName).font(.subheadline.weight(.bold))
                        }

                        HStack {
                            Text("Điện thoại:").foregroundColor(.secondary).font(.subheadline)
                            Text(record.customerPhone.isEmpty ? "Không có" : record.customerPhone)
                                .font(.subheadline.weight(.semibold))
                        }

                        HStack {
                            Text("Thời gian:").foregroundColor(.secondary).font(.subheadline)
                            Text(dateFormatter.string(from: record.date))
                                .font(.subheadline)
                        }

                        if !record.notes.isEmpty {
                            HStack(alignment: .top) {
                                Text("Ghi chú:").foregroundColor(.secondary).font(.subheadline)
                                Text(record.notes).font(.subheadline)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)

                    // Location Card
                    if !record.googleLocation.isEmpty || !record.googleLocationUrl.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VỊ TRÍ GOOGLE MAPS")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)

                            Text(record.googleLocation.isEmpty ? "Đã lưu tọa độ" : record.googleLocation)
                                .font(.subheadline)

                            if !record.googleLocationUrl.isEmpty, let url = URL(string: record.googleLocationUrl) {
                                Button(action: { UIApplication.shared.open(url) }) {
                                    HStack {
                                        Image(systemName: "map.fill")
                                        Text("Xem trên Google Maps")
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(12)
                    }

                    // Cameras List
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("DANH SÁCH CAMERA LẮP ĐẶT (\(record.cameras.count))")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        ForEach(record.cameras) { cam in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(cam.brand)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(cam.brand == "Imou" ? Color.orange : Color.red)
                                        .cornerRadius(4)

                                    Text(cam.model)
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text("IP: \(cam.ip)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Text("S/N: \(cam.serialNo)")
                                        .font(.system(.caption, design: .monospaced).weight(.bold))
                                        .foregroundColor(.orange)

                                    Spacer()

                                    Button(action: {
                                        UIPasteboard.general.string = cam.serialNo
                                    }) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "doc.on.doc")
                                            Text("Copy S/N")
                                        }
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }

                                if !cam.mac.isEmpty {
                                    Text("MAC: \(cam.mac)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color.gray.opacity(0.04))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .padding(16)
            }
            .background(Color.gray.opacity(0.06).edgesIgnoringSafeArea(.all))
            .navigationTitle("Chi Tiết Lắp Đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}
