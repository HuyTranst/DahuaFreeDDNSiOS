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
    var items: [InvoiceItem]
    var notes: String
    var createdAt: Date = Date()

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

    private let companyKey = "cctv_company_info"
    private let productsKey = "cctv_saved_products"
    private let invoicesKey = "cctv_saved_invoices"

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

    func addProduct(_ product: PresetProduct) {
        savedProducts.insert(product, at: 0)
    }

    func deleteProduct(at indexSet: IndexSet) {
        savedProducts.remove(atOffsets: indexSet)
    }

    func addInvoice(_ invoice: InvoiceRecord) {
        if let idx = savedInvoices.firstIndex(where: { $0.id == invoice.id }) {
            savedInvoices[idx] = invoice
        } else {
            savedInvoices.insert(invoice, at: 0)
        }
    }

    func deleteInvoice(at indexSet: IndexSet) {
        savedInvoices.remove(atOffsets: indexSet)
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
