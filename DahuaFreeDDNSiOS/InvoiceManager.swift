import Foundation
import SwiftUI
import UIKit

// MARK: - Models
struct InvoiceItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var model: String
    var name: String
    var unit: String
    var quantity: Int
    var price: Double
    var taxRate: Double = 0.0
    var note: String = ""

    var subtotal: Double {
        return Double(quantity) * price
    }

    var taxAmount: Double {
        return subtotal * (taxRate / 100.0)
    }

    var total: Double {
        return subtotal + taxAmount
    }
}

struct PresetProduct: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var model: String
    var name: String
    var unit: String
    var price: Double
    var taxRate: Double = 0.0
}

struct CompanyInfo: Codable, Equatable {
    var name: String = "CÔNG TY GIẢI PHÁP CÔNG NGHỆ QUỐC HUY"
    var address: String = ""
    var phone: String = "0909080119"
    var email: String = "Dahua.tuanhuy@gmail.com"
    var bankAccount: String = ""
}

struct InvoiceRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var invoiceNo: String
    var date: Date
    var warrantyMonths: Int
    var customerName: String
    var customerPhone: String
    var customerAddress: String
    var googleLocation: String = ""
    var googleLocationUrl: String = ""
    var items: [InvoiceItem]
    var notes: String
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, invoiceNo, date, warrantyMonths, customerName, customerPhone, customerAddress
        case googleLocation, googleLocationUrl, items, notes, createdAt
    }

    init(
        id: UUID = UUID(),
        invoiceNo: String,
        date: Date,
        warrantyMonths: Int,
        customerName: String,
        customerPhone: String,
        customerAddress: String,
        googleLocation: String = "",
        googleLocationUrl: String = "",
        items: [InvoiceItem],
        notes: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.invoiceNo = invoiceNo
        self.date = date
        self.warrantyMonths = warrantyMonths
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.customerAddress = customerAddress
        self.googleLocation = googleLocation
        self.googleLocationUrl = googleLocationUrl
        self.items = items
        self.notes = notes
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        invoiceNo = try container.decode(String.self, forKey: .invoiceNo)
        date = try container.decode(Date.self, forKey: .date)
        warrantyMonths = try container.decode(Int.self, forKey: .warrantyMonths)
        customerName = try container.decode(String.self, forKey: .customerName)
        customerPhone = try container.decode(String.self, forKey: .customerPhone)
        customerAddress = try container.decode(String.self, forKey: .customerAddress)
        googleLocation = try container.decodeIfPresent(String.self, forKey: .googleLocation) ?? ""
        googleLocationUrl = try container.decodeIfPresent(String.self, forKey: .googleLocationUrl) ?? ""
        items = try container.decode([InvoiceItem].self, forKey: .items)
        notes = try container.decode(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var subtotal: Double {
        items.reduce(0) { $0 + $1.subtotal }
    }

    var totalTax: Double {
        items.reduce(0) { $0 + $1.taxAmount }
    }

    var totalAmount: Double {
        items.reduce(0) { $0 + $1.total }
    }
}

// MARK: - Camera Installation Record Models (Lịch Sử Lắp Camera)
struct InstalledCameraItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var ip: String
    var serialNo: String
    var model: String
    var mac: String
    var brand: String
}

struct CameraInstallRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var customerName: String
    var customerPhone: String
    var date: Date
    var googleLocation: String
    var googleLocationUrl: String
    var cameras: [InstalledCameraItem]
    var notes: String = ""
    var createdAt: Date = Date()
}

// MARK: - Invoice Manager (Local Persistence via UserDefaults)
class InvoiceManager: ObservableObject {
    static let shared = InvoiceManager()

    @Published var companyInfo: CompanyInfo {
        didSet { saveCompanyInfo() }
    }

    @Published var savedProducts: [PresetProduct] = [] {
        didSet { saveProducts() }
    }

    @Published var savedInvoices: [InvoiceRecord] = [] {
        didSet { saveInvoices() }
    }

    @Published var savedInstallRecords: [CameraInstallRecord] = [] {
        didSet { saveInstallRecords() }
    }

    private let companyKey = "cctv_company_info"
    private let productsKey = "cctv_saved_products"
    private let invoicesKey = "cctv_saved_invoices"
    private let installRecordsKey = "cctv_saved_install_records"

    init() {
        // Load company info
        if let data = UserDefaults.standard.data(forKey: companyKey),
           let decoded = try? JSONDecoder().decode(CompanyInfo.self, from: data),
           decoded.name != "CÔNG TY TNHH GIẢI PHÁP CCTV VIỆT NAM" {
            self.companyInfo = decoded
        } else {
            self.companyInfo = CompanyInfo()
            saveCompanyInfo()
        }

        // Load products
        if let data = UserDefaults.standard.data(forKey: productsKey),
           let decoded = try? JSONDecoder().decode([PresetProduct].self, from: data) {
            self.savedProducts = decoded
        } else {
            // Default CCTV products for instant load
            self.savedProducts = [
                PresetProduct(model: "DH-IPC-HDW1230T-A-S5", name: "Camera Dome 2.0MP có mic", unit: "Cái", price: 1710000, taxRate: 0),
                PresetProduct(model: "NVR-N110-8A0E", name: "Đầu ghi hình NVR 10 kênh", unit: "Cái", price: 1279000, taxRate: 0),
                PresetProduct(model: "DH-PFM320-020EN", name: "Nguồn Dahua 12V-2A", unit: "Cái", price: 120000, taxRate: 0),
                PresetProduct(model: "SEAGATE-SKYHAWK-10TB", name: "Ổ cứng chuyên dụng Seagate SkyHawk 10TB", unit: "Cái", price: 6500000, taxRate: 0),
                PresetProduct(model: "IMOU-A22EP", name: "Camera Wi-Fi Imou Ranger 2 2.0MP", unit: "Cái", price: 550000, taxRate: 0),
                PresetProduct(model: "IMOU-F22FP", name: "Camera ngoài trời Imou Bullet 2E có màu ban đêm", unit: "Cái", price: 790000, taxRate: 0),
                PresetProduct(model: "BALUN-5MP", name: "Bộ chuyển đổi Video Balun 5.0MP", unit: "Cặp", price: 35000, taxRate: 0),
                PresetProduct(model: "BOX-CHONGNUOC", name: "Hộp kỹ thuật chống nước 12x12", unit: "Cái", price: 15000, taxRate: 0)
            ]
            saveProducts()
        }

        // Load invoices
        if let data = UserDefaults.standard.data(forKey: invoicesKey),
           let decoded = try? JSONDecoder().decode([InvoiceRecord].self, from: data) {
            self.savedInvoices = decoded
        }

        // Load camera install records
        if let data = UserDefaults.standard.data(forKey: installRecordsKey),
           let decoded = try? JSONDecoder().decode([CameraInstallRecord].self, from: data) {
            self.savedInstallRecords = decoded
        }
    }

    func saveCompanyInfo() {
        if let encoded = try? JSONEncoder().encode(companyInfo) {
            UserDefaults.standard.set(encoded, forKey: companyKey)
        }
    }

    func saveProducts() {
        if let encoded = try? JSONEncoder().encode(savedProducts) {
            UserDefaults.standard.set(encoded, forKey: productsKey)
        }
    }

    func saveInvoices() {
        if let encoded = try? JSONEncoder().encode(savedInvoices) {
            UserDefaults.standard.set(encoded, forKey: invoicesKey)
        }
    }

    func saveInstallRecords() {
        if let encoded = try? JSONEncoder().encode(savedInstallRecords) {
            UserDefaults.standard.set(encoded, forKey: installRecordsKey)
        }
    }

    func addProduct(_ product: PresetProduct) {
        savedProducts.insert(product, at: 0)
    }

    func updateProduct(_ product: PresetProduct) {
        if let idx = savedProducts.firstIndex(where: { $0.id == product.id }) {
            savedProducts[idx] = product
        }
    }

    func deleteProduct(at indexSet: IndexSet) {
        savedProducts.remove(atOffsets: indexSet)
    }

    func addInvoice(_ invoice: InvoiceRecord) {
        // Không lưu trùng hóa đơn: kiểm tra theo ID hoặc Mã số hóa đơn (invoiceNo)
        if let idx = savedInvoices.firstIndex(where: { $0.id == invoice.id || $0.invoiceNo == invoice.invoiceNo }) {
            savedInvoices[idx] = invoice
        } else {
            savedInvoices.insert(invoice, at: 0)
        }
    }

    func deleteInvoice(at indexSet: IndexSet) {
        savedInvoices.remove(atOffsets: indexSet)
    }

    func addInstallRecord(_ record: CameraInstallRecord) {
        if let idx = savedInstallRecords.firstIndex(where: { $0.id == record.id }) {
            savedInstallRecords[idx] = record
        } else {
            savedInstallRecords.insert(record, at: 0)
        }
    }

    func deleteInstallRecord(at indexSet: IndexSet) {
        savedInstallRecords.remove(atOffsets: indexSet)
    }
}

// MARK: - Number Formatter Helper
func formatVndCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.decimalSeparator = ","
    formatter.maximumFractionDigits = 0
    let str = formatter.string(from: NSNumber(value: amount)) ?? "0"
    return "\(str)đ"
}

func parseVndCurrency(_ text: String) -> Double {
    let cleaned = text.replacingOccurrences(of: ".", with: "")
                      .replacingOccurrences(of: "đ", with: "")
                      .replacingOccurrences(of: " ", with: "")
                      .replacingOccurrences(of: ",", with: ".")
    return Double(cleaned) ?? 0.0
}
