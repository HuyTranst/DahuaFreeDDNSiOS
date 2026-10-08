import SwiftUI
import UIKit

// MARK: - Main Invoice Creation & Management View (Hóa Đơn Bán Hàng)
struct InvoiceView: View {
    @ObservedObject var invoiceMgr = InvoiceManager.shared

    // Step state: 1 = Thông tin khách hàng, 2 = Sản phẩm & Hoàn tất
    @State private var currentStep: Int = 1

    // Step 1: Customer Form
    @State private var customerSearchText: String = ""
    @State private var customerName: String = ""
    @State private var customerPhone: String = ""
    @State private var customerAddress: String = ""
    @State private var invoiceDate: Date = Date()
    @State private var warrantyMonths: Int = 24
    @State private var invoiceNo: String = ""
    @State private var currentEditingId: UUID? = nil

    // Step 2: Add Product
    @State private var productSearchText: String = ""
    @State private var inputModel: String = ""
    @State private var inputName: String = ""
    @State private var inputUnit: String = "Cái"
    @State private var inputQuantity: Int = 1
    @State private var inputPriceText: String = ""
    @State private var inputTaxRate: Double = 0.0

    // Invoice items & notes
    @State private var invoiceItems: [InvoiceItem] = []
    @State private var invoiceNotes: String = "Tặng hộp chống nước, Tặng dây điện 2m theo cam, bảo hành 2 năm"

    // Aspect ratio selection for preview & export
    @State private var previewRatio: InvoiceAspectRatio = .ratio9_16

    // Modals
    @State private var showCompanySetup: Bool = false
    @State private var showProductLibrary: Bool = false
    @State private var showSavedInvoicesList: Bool = false
    @State private var showPreviewModal: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var exportedImage: UIImage? = nil
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss"
        return df
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Action Bar
                topHeaderBar

                // Step Indicator (1: Thông tin khách hàng -> 2: Sản phẩm & Hoàn tất)
                stepIndicatorView

                // Form Content
                if currentStep == 1 {
                    step1CustomerView
                } else {
                    step2ProductsView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.gray.opacity(0.05).edgesIgnoringSafeArea(.all))
        .onAppear {
            if invoiceNo.isEmpty {
                generateNewInvoiceNo()
            }
        }
        .sheet(isPresented: $showCompanySetup) {
            CompanySetupModalView(company: $invoiceMgr.companyInfo)
        }
        .sheet(isPresented: $showProductLibrary) {
            ProductLibraryModalView(
                invoiceMgr: invoiceMgr,
                onSelectProduct: { preset in
                    selectPresetProduct(preset)
                }
            )
        }
        .sheet(isPresented: $showSavedInvoicesList) {
            SavedInvoicesModalView(
                invoiceMgr: invoiceMgr,
                onLoadInvoice: { record in
                    loadExistingInvoice(record)
                }
            )
        }
        .sheet(isPresented: $showPreviewModal) {
            InvoicePreviewModalView(
                invoice: buildCurrentInvoiceRecord(),
                company: invoiceMgr.companyInfo,
                selectedRatio: $previewRatio,
                onExportJpg: {
                    exportInvoiceToJpg()
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = exportedImage {
                ShareSheet(activityItems: [img, "Hóa đơn bán hàng camera: \(invoiceNo)"])
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Top Header Bar
    var topHeaderBar: some View {
        HStack {
            Button(action: { showSavedInvoicesList = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                    Text("Đã Lưu (\(invoiceMgr.savedInvoices.count))")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            Spacer()

            Button(action: { showProductLibrary = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "cube.box.fill")
                    Text("Kho SP")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(8)
            }

            Button(action: { showCompanySetup = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "building.2.fill")
                    Text("Cài Đặt Cty")
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Step Indicator
    var stepIndicatorView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(currentStep == 1 ? Color.orange : Color.green)
                        .frame(width: 26, height: 26)
                    if currentStep > 1 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("1")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                Text("Thông tin khách hàng")
                    .font(.subheadline.weight(currentStep == 1 ? .bold : .medium))
                    .foregroundColor(currentStep == 1 ? .orange : .secondary)
            }

            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 2)

            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(currentStep == 2 ? Color.orange : Color.gray.opacity(0.3))
                        .frame(width: 26, height: 26)
                    Text("2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(currentStep == 2 ? .white : .secondary)
                }
                Text("Sản phẩm & Hoàn tất")
                    .font(.subheadline.weight(currentStep == 2 ? .bold : .medium))
                    .foregroundColor(currentStep == 2 ? .orange : .secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Step 1: Customer View
    var step1CustomerView: some View {
        VStack(spacing: 16) {
            // Customer Info Box
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "person.text.rectangle.fill")
                        .foregroundColor(.orange)
                    Text("THÔNG TIN KHÁCH HÀNG")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Làm mới HĐ") {
                        resetForm()
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                }

                // Số Hóa Đơn & Ngày Lập
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Số Hóa Đơn:").font(.caption).foregroundColor(.secondary)
                        Text(invoiceNo)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Ngày lập:").font(.caption).foregroundColor(.secondary)
                        DatePicker("", selection: $invoiceDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)

                // Input fields
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "person.fill").foregroundColor(.orange).frame(width: 20)
                        TextField("Tên khách hàng *", text: $customerName)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)

                    HStack {
                        Image(systemName: "phone.fill").foregroundColor(.orange).frame(width: 20)
                        TextField("Số điện thoại", text: $customerPhone)
                            .keyboardType(.phonePad)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)

                    HStack {
                        Image(systemName: "mappin.and.ellipse").foregroundColor(.orange).frame(width: 20)
                        TextField("Địa chỉ lắp đặt", text: $customerAddress)
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)

                    HStack {
                        Image(systemName: "shield.fill").foregroundColor(.orange).frame(width: 20)
                        Text("Bảo hành (tháng):")
                            .font(.subheadline)
                        Spacer()
                        Stepper("\(warrantyMonths) tháng", value: $warrantyMonths, in: 0...60)
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)

            // Next button
            Button(action: {
                if customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    alertMessage = "Vui lòng nhập Tên khách hàng!"
                    showAlert = true
                    return
                }
                withAnimation { currentStep = 2 }
            }) {
                HStack {
                    Spacer()
                    Text("Tiếp theo: Thêm sản phẩm")
                        .font(.body.weight(.bold))
                    Image(systemName: "arrow.right")
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Step 2: Products View
    var step2ProductsView: some View {
        VStack(spacing: 16) {
            // Quick Load Product from Local Library
            if !invoiceMgr.savedProducts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.orange)
                        Text("CHỌN NHANH TỪ KHO CCTV")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if !productSearchText.isEmpty {
                            Button(action: { productSearchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }

                    // Khung text nhập sản phẩm cần tìm kiếm
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.caption)
                        TextField("Nhập tên sản phẩm hoặc model cần tìm...", text: $productSearchText)
                            .font(.subheadline)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)

                    let filteredPresets = invoiceMgr.savedProducts.filter { preset in
                        if productSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
                        let q = productSearchText.lowercased()
                        return preset.name.lowercased().contains(q) || preset.model.lowercased().contains(q)
                    }

                    if filteredPresets.isEmpty {
                        Text("Không tìm thấy sản phẩm phù hợp")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filteredPresets) { preset in
                                    Button(action: { selectPresetProduct(preset) }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(preset.model)
                                                .font(.caption2.weight(.bold))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Text(preset.name)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                            Text(formatVndCurrency(preset.price))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(.orange)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.gray.opacity(0.08))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
            }

            // Input New Product Box
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.orange)
                    Text("THÊM SẢN PHẨM MỚI")
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField("Model (VD: DH-IPC-HDW1230T)", text: $inputModel)
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(6)

                    TextField("Tên sản phẩm *", text: $inputName)
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(6)
                }

                HStack(spacing: 10) {
                    TextField("ĐVT", text: $inputUnit)
                        .frame(width: 60)
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(6)

                    HStack(spacing: 4) {
                        Text("SL:")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.secondary)

                        Button(action: { if inputQuantity > 1 { inputQuantity -= 1 } }) {
                            Text("-")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(Color.gray.opacity(0.18))
                                .foregroundColor(.primary)
                                .cornerRadius(5)
                        }

                        Text("\(inputQuantity)")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.orange)
                            .frame(minWidth: 26, alignment: .center)

                        Button(action: { inputQuantity += 1 }) {
                            Text("+")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(5)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)

                    TextField("Đơn giá (VD: 1.710.000)", text: $inputPriceText)
                        .keyboardType(.numbersAndPunctuation)
                        .padding(8)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(6)
                }

                Button(action: addProductToInvoice) {
                    HStack {
                        Spacer()
                        Image(systemName: "plus")
                        Text("Thêm vào hóa đơn")
                            .font(.body.weight(.bold))
                        Spacer()
                    }
                    .padding(.vertical, 9)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)

            // Current Product List Table
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .foregroundColor(.orange)
                    Text("DANH SÁCH SẢN PHẨM (\(invoiceItems.count))")
                        .font(.headline)
                    Spacer()
                }

                if invoiceItems.isEmpty {
                    Text("Chưa có sản phẩm nào trong hóa đơn. Vui lòng chọn hoặc thêm sản phẩm ở trên.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(0..<invoiceItems.count, id: \.self) { idx in
                        let item = invoiceItems[idx]
                        VStack(spacing: 6) {
                            HStack {
                                Text("\(idx + 1).")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                    if !item.model.isEmpty {
                                        Text("Model: \(item.model)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Button(action: {
                                    invoiceItems.remove(at: idx)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }

                            HStack {
                                Text("\(item.quantity) \(item.unit) x \(formatVndCurrency(item.price))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(formatVndCurrency(item.total))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(12)

            // Notes and Totals
            VStack(spacing: 10) {
                HStack {
                    Text("Ghi chú:")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                TextField("Ghi chú hóa đơn (VD: Tặng hộp kỹ thuật, dây mạng...)", text: $invoiceNotes)
                    .padding(8)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)

                Divider()

                HStack {
                    Text("Tiền hàng:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatVndCurrency(calculateSubtotal()))
                        .font(.subheadline.weight(.semibold))
                }

                HStack {
                    Text("TỔNG CỘNG:")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Spacer()
                    Text(formatVndCurrency(calculateTotal()))
                        .font(.title3.weight(.heavy))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(12)

            // Action Buttons (Quay lại, Xem trước & Xuất JPG)
            HStack(spacing: 12) {
                Button(action: { withAnimation { currentStep = 1 } }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Quay lại")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }

                Button(action: {
                    if invoiceItems.isEmpty {
                        alertMessage = "Vui lòng thêm ít nhất 1 sản phẩm vào hóa đơn!"
                        showAlert = true
                        return
                    }
                    saveCurrentInvoice()
                    showPreviewModal = true
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("XEM TRƯỚC & XUẤT ẢNH")
                            .font(.body.weight(.bold))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Logic Helpers
    private func generateNewInvoiceNo() {
        let rand = Int.random(in: 100...999)
        invoiceNo = "HD\(dateFormatter.string(from: Date()))-\(rand)"
    }

    private func resetForm() {
        generateNewInvoiceNo()
        currentEditingId = nil
        customerName = ""
        customerPhone = ""
        customerAddress = ""
        invoiceItems.removeAll()
        warrantyMonths = 24
        invoiceNotes = "Tặng hộp chống nước, Tặng dây điện 2m theo cam, bảo hành 2 năm"
        currentStep = 1
    }

    private func selectPresetProduct(_ preset: PresetProduct) {
        inputModel = preset.model
        inputName = preset.name
        inputUnit = preset.unit
        inputPriceText = formatVndCurrency(preset.price).replacingOccurrences(of: "đ", with: "")
        inputQuantity = 1
        inputTaxRate = preset.taxRate
    }

    private func addProductToInvoice() {
        let trimmedName = inputName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            alertMessage = "Vui lòng nhập Tên sản phẩm!"
            showAlert = true
            return
        }

        let price = parseVndCurrency(inputPriceText)
        let item = InvoiceItem(
            model: inputModel.trimmingCharacters(in: .whitespacesAndNewlines),
            name: trimmedName,
            unit: inputUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cái" : inputUnit,
            quantity: inputQuantity,
            price: price,
            taxRate: inputTaxRate,
            note: ""
        )

        invoiceItems.append(item)

        // Clear input
        inputModel = ""
        inputName = ""
        inputPriceText = ""
        inputQuantity = 1
    }

    private func calculateSubtotal() -> Double {
        invoiceItems.reduce(0) { $0 + $1.subtotal }
    }

    private func calculateTotal() -> Double {
        invoiceItems.reduce(0) { $0 + $1.total }
    }

    private func buildCurrentInvoiceRecord() -> InvoiceRecord {
        var rec = InvoiceRecord(
            invoiceNo: invoiceNo,
            date: invoiceDate,
            warrantyMonths: warrantyMonths,
            customerName: customerName,
            customerPhone: customerPhone,
            customerAddress: customerAddress,
            items: invoiceItems,
            notes: invoiceNotes
        )
        if let editId = currentEditingId {
            rec.id = editId
        }
        return rec
    }

    private func saveCurrentInvoice() {
        let record = buildCurrentInvoiceRecord()
        currentEditingId = record.id
        invoiceMgr.addInvoice(record)
    }

    private func loadExistingInvoice(_ record: InvoiceRecord) {
        currentEditingId = record.id
        invoiceNo = record.invoiceNo
        invoiceDate = record.date
        warrantyMonths = record.warrantyMonths
        customerName = record.customerName
        customerPhone = record.customerPhone
        customerAddress = record.customerAddress
        invoiceItems = record.items
        invoiceNotes = record.notes
        currentStep = 2
        showSavedInvoicesList = false
    }

    private func exportInvoiceToJpg() {
        let invoice = buildCurrentInvoiceRecord()
        let paper = InvoicePaperView(invoice: invoice, company: invoiceMgr.companyInfo, aspectRatio: previewRatio)

        let targetWidth = previewRatio.canvasWidth
        let targetHeight = previewRatio.canvasHeight(itemsCount: invoice.items.count)

        if let img = paper.renderAsImage(targetSize: CGSize(width: targetWidth, height: targetHeight)) {
            // Save directly to iOS Photo Library (Bộ sưu tập ảnh)
            PhotoLibrarySaver.shared.saveImageToAlbum(img) { success, error in
                self.showPreviewModal = false
                if success {
                    self.alertMessage = "✅ Đã lưu ảnh hóa đơn (\(previewRatio.rawValue)) thành công vào Bộ sưu tập ảnh của bạn!"
                    self.showAlert = true
                } else {
                    self.alertMessage = "❌ Lỗi lưu ảnh: \(error ?? "Không rõ lỗi")"
                    self.showAlert = true
                }
            }
        } else {
            alertMessage = "Không thể xuất ảnh hóa đơn!"
            showAlert = true
        }
    }
}

// MARK: - Company Setup Modal View
struct CompanySetupModalView: View {
    @Binding var company: CompanyInfo
    @Environment(\.presentationMode) var presentationMode

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Thông tin đơn vị / Công ty lắp đặt")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên công ty / Cửa hàng:").font(.caption).foregroundColor(.secondary)
                        TextField("Tên công ty", text: $name)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Địa chỉ (có thể để trống):").font(.caption).foregroundColor(.secondary)
                        TextField("Địa chỉ", text: $address)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("HotLine/Zalo:").font(.caption).foregroundColor(.secondary)
                        TextField("Điện thoại / Zalo", text: $phone)
                            .keyboardType(.phonePad)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email liên hệ:").font(.caption).foregroundColor(.secondary)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                    }
                }
            }
            .navigationTitle("Cài Đặt Đơn Vị")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        company.name = name
                        company.address = address
                        company.phone = phone
                        company.email = email
                        company.bankAccount = ""
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Lưu")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                }
            }
            .onAppear {
                name = company.name.isEmpty ? "CÔNG TY GIẢI PHÁP CÔNG NGHỆ QUỐC HUY" : company.name
                address = company.address
                phone = company.phone.isEmpty ? "0909080119" : company.phone
                email = company.email.isEmpty ? "Dahua.tuanhuy@gmail.com" : company.email
            }
        }
    }
}

// MARK: - Product Library Modal View (Quản lý kho sản phẩm)
struct ProductLibraryModalView: View {
    @ObservedObject var invoiceMgr: InvoiceManager
    let onSelectProduct: (PresetProduct) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var newModel: String = ""
    @State private var newName: String = ""
    @State private var newUnit: String = "Cái"
    @State private var newPriceText: String = ""

    var body: some View {
        NavigationView {
            VStack {
                // Add New Product Form
                VStack(spacing: 8) {
                    HStack {
                        TextField("Model (VD: DH-IPC-HDW1230T)", text: $newModel)
                            .padding(6)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)

                        TextField("Tên SP *", text: $newName)
                            .padding(6)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)
                    }

                    HStack {
                        TextField("ĐVT", text: $newUnit)
                            .frame(width: 60)
                            .padding(6)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)

                        TextField("Đơn giá (VD: 1.250.000)", text: $newPriceText)
                            .keyboardType(.numbersAndPunctuation)
                            .padding(6)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(6)

                        Button(action: addProduct) {
                            Text("+ Thêm SP")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.05))

                // List of products
                List {
                    ForEach(invoiceMgr.savedProducts) { product in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                    .font(.subheadline.weight(.semibold))
                                if !product.model.isEmpty {
                                    Text("Model: \(product.model)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Text(formatVndCurrency(product.price))
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.orange)

                            Button(action: {
                                onSelectProduct(product)
                                presentationMode.wrappedValue.dismiss()
                            }) {
                                Text("Chọn")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onDelete(perform: invoiceMgr.deleteProduct)
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Kho Sản Phẩm Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private func addProduct() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return }
        let price = parseVndCurrency(newPriceText)
        let prod = PresetProduct(
            model: newModel.trimmingCharacters(in: .whitespacesAndNewlines),
            name: name,
            unit: newUnit.isEmpty ? "Cái" : newUnit,
            price: price,
            taxRate: 0
        )
        invoiceMgr.addProduct(prod)
        newModel = ""
        newName = ""
        newPriceText = ""
    }
}

// MARK: - Saved Invoices Modal View (Hóa Đơn Đã Lưu có Tìm Kiếm Tên, SĐT)
struct SavedInvoicesModalView: View {
    @ObservedObject var invoiceMgr: InvoiceManager
    let onLoadInvoice: (InvoiceRecord) -> Void
    @Environment(\.presentationMode) var presentationMode

    @State private var searchText: String = ""

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df
    }()

    var filteredInvoices: [InvoiceRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return invoiceMgr.savedInvoices
        }
        return invoiceMgr.savedInvoices.filter { inv in
            inv.customerName.lowercased().contains(query) ||
            inv.customerPhone.lowercased().contains(query) ||
            inv.invoiceNo.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Tìm kiếm theo tên khách, SĐT, số HĐ...", text: $searchText)
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
                    if invoiceMgr.savedInvoices.isEmpty {
                        Text("Chưa có hóa đơn nào được lưu.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    } else if filteredInvoices.isEmpty {
                        Text("Không tìm thấy hóa đơn nào phù hợp với: \"\(searchText)\"")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(filteredInvoices) { inv in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(inv.invoiceNo)
                                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                            .foregroundColor(.orange)
                                        Spacer()
                                        Text(formatVndCurrency(inv.totalAmount))
                                            .font(.headline.weight(.heavy))
                                            .foregroundColor(.primary)
                                    }

                                    HStack {
                                        Text("Khách hàng: \(inv.customerName.isEmpty ? "Khách lẻ" : inv.customerName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(dateFormatter.string(from: inv.createdAt))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Text("\(inv.items.count) sản phẩm | \(inv.customerPhone.isEmpty ? "Không có SĐT" : inv.customerPhone)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onLoadInvoice(inv)
                                }


                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let itemToDelete = filteredInvoices[index]
                                if let actualIdx = invoiceMgr.savedInvoices.firstIndex(where: { $0.id == itemToDelete.id }) {
                                    invoiceMgr.deleteInvoice(at: IndexSet(integer: actualIdx))
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Hóa Đơn Đã Lưu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

// MARK: - Invoice Preview Modal View (Xem Trước Hóa Đơn Tùy Chọn Khổ 9:16 & 6:19)
struct InvoicePreviewModalView: View {
    let invoice: InvoiceRecord
    let company: CompanyInfo
    @Binding var selectedRatio: InvoiceAspectRatio
    let onExportJpg: () -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selector Toolbar: Khổ 9:16 & 6:19 kèm hình chữ nhật minh họa
                HStack(spacing: 12) {
                    Text("Tùy chọn khổ:")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Option 1: 9:16
                    Button(action: {
                        withAnimation { selectedRatio = .ratio9_16 }
                    }) {
                        HStack(spacing: 5) {
                            // Hình chữ nhật minh họa tỷ lệ 9:16
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(selectedRatio == .ratio9_16 ? Color.orange : Color.gray, lineWidth: 1.5)
                                    .frame(width: 13, height: 23)
                                if selectedRatio == .ratio9_16 {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.orange.opacity(0.35))
                                        .frame(width: 9, height: 19)
                                }
                            }

                            Text("9:16")
                                .font(.caption.weight(selectedRatio == .ratio9_16 ? .bold : .medium))
                                .foregroundColor(selectedRatio == .ratio9_16 ? .orange : .primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedRatio == .ratio9_16 ? Color.orange.opacity(0.12) : Color.gray.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // Option 2: 6:19
                    Button(action: {
                        withAnimation { selectedRatio = .ratio6_19 }
                    }) {
                        HStack(spacing: 5) {
                            // Hình chữ nhật minh họa tỷ lệ 6:19 (dài hơn)
                            ZStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(selectedRatio == .ratio6_19 ? Color.orange : Color.gray, lineWidth: 1.5)
                                    .frame(width: 9, height: 26)
                                if selectedRatio == .ratio6_19 {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.orange.opacity(0.35))
                                        .frame(width: 6, height: 22)
                                }
                            }

                            Text("6:19")
                                .font(.caption.weight(selectedRatio == .ratio6_19 ? .bold : .medium))
                                .foregroundColor(selectedRatio == .ratio6_19 ? .orange : .primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedRatio == .ratio6_19 ? Color.orange.opacity(0.12) : Color.gray.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)

                // Scroll Preview Paper
                ScrollView([.horizontal, .vertical]) {
                    InvoicePaperView(invoice: invoice, company: company, aspectRatio: selectedRatio)
                        .padding(16)
                }
                .background(Color.gray.opacity(0.2))

                // Bottom Action Bar
                HStack(spacing: 12) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Text("Chỉnh sửa lại")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }

                    Button(action: onExportJpg) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("LƯU ẢNH \(selectedRatio.rawValue) VÀO BỘ SƯU TẬP")
                                .font(.body.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.orange)
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color.white)
            }
            .navigationTitle("Xem Trước Hóa Đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}
