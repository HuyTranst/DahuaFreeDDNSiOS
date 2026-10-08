import SwiftUI
import UIKit

// MARK: - Aspect Ratio Enum for Invoice
enum InvoiceAspectRatio: String, CaseIterable, Identifiable {
    case ratio9_16 = "9:16"
    case ratio6_19 = "6:19"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ratio9_16:
            return "Khổ 9:16 (Story / Zalo)"
        case .ratio6_19:
            return "Khổ 6:19 (Dài / Cuộn Bill)"
        }
    }

    var shortName: String {
        switch self {
        case .ratio9_16:
            return "Dạng 9:16"
        case .ratio6_19:
            return "Dạng 6:19"
        }
    }

    // Target width & height for export image and preview
    var paperWidth: CGFloat { 595.0 } // Standard A4 base width

    func paperHeight(itemsCount: Int) -> CGFloat {
        switch self {
        case .ratio9_16:
            // 9:16 -> width 595, height = 595 * 16 / 9 ~ 1058
            let calculated = 595.0 * 16.0 / 9.0
            let minNeeded: CGFloat = 360.0 + CGFloat(itemsCount * 30)
            return max(calculated, minNeeded)
        case .ratio6_19:
            // 6:19 -> width 595, height = 595 * 19 / 6 ~ 1884
            let calculated = 595.0 * 19.0 / 6.0
            let minNeeded: CGFloat = 400.0 + CGFloat(itemsCount * 34)
            return max(calculated, minNeeded)
        }
    }
}

// MARK: - Invoice Bill View (To Render and Export as Image)
struct InvoicePaperView: View {
    let invoice: InvoiceRecord
    let company: CompanyInfo
    var aspectRatio: InvoiceAspectRatio = .ratio9_16

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Company Info & Title
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: aspectRatio == .ratio9_16 ? 3 : 5) {
                    Text(company.name.isEmpty ? "CÔNG TY GIẢI PHÁP CÔNG NGHỆ QUỐC HUY" : company.name)
                        .font(.system(size: aspectRatio == .ratio9_16 ? 13 : 14, weight: .bold))
                        .foregroundColor(.orange)

                    if !company.address.isEmpty {
                        Text("Địa chỉ: \(company.address)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    Text("Hotline/Zalo: \(company.phone.isEmpty ? "0909080119" : company.phone)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    if !company.email.isEmpty {
                        Text("Email: \(company.email)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }

                    if !company.bankAccount.isEmpty {
                        Text("Thanh toán: \(company.bankAccount)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("ĐƠN VỊ LẮP ĐẶT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)

                    Image(systemName: "video.badge.checkmark")
                        .font(.system(size: aspectRatio == .ratio9_16 ? 24 : 28))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, aspectRatio == .ratio9_16 ? 16 : 22)

            Divider()
                .padding(.horizontal, 20)
                .padding(.vertical, aspectRatio == .ratio9_16 ? 8 : 12)

            // Title
            VStack(spacing: 3) {
                Text("HÓA ĐƠN BÁN HÀNG")
                    .font(.system(size: aspectRatio == .ratio9_16 ? 20 : 22, weight: .heavy))
                    .foregroundColor(.orange)

                Rectangle()
                    .fill(Color.orange)
                    .frame(height: 2)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, aspectRatio == .ratio9_16 ? 8 : 12)

            // Invoice & Customer Info 2-Column Grid
            HStack(alignment: .top, spacing: 16) {
                // Left: Thông tin hóa đơn
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thông tin hóa đơn")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)

                    HStack {
                        Text("Số hóa đơn:").foregroundColor(.secondary).font(.system(size: 10))
                        Text(invoice.invoiceNo).font(.system(size: 10, weight: .bold))
                    }
                    HStack {
                        Text("Ngày lập:").foregroundColor(.secondary).font(.system(size: 10))
                        Text(dateFormatter.string(from: invoice.date)).font(.system(size: 10))
                    }
                    HStack {
                        Text("Bảo hành:").foregroundColor(.secondary).font(.system(size: 10))
                        Text("\(invoice.warrantyMonths) tháng").font(.system(size: 10, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: Thông tin khách hàng
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thông tin khách hàng")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)

                    HStack {
                        Text("Khách hàng:").foregroundColor(.secondary).font(.system(size: 10))
                        Text(invoice.customerName.isEmpty ? "Khách vãng lai" : invoice.customerName)
                            .font(.system(size: 10, weight: .bold))
                    }
                    HStack {
                        Text("Điện thoại:").foregroundColor(.secondary).font(.system(size: 10))
                        Text(invoice.customerPhone.isEmpty ? "—" : invoice.customerPhone)
                            .font(.system(size: 10))
                    }
                    HStack(alignment: .top) {
                        Text("Địa chỉ:").foregroundColor(.secondary).font(.system(size: 10))
                        Text(invoice.customerAddress.isEmpty ? "—" : invoice.customerAddress)
                            .font(.system(size: 10))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, aspectRatio == .ratio9_16 ? 10 : 14)

            // Items Table Header
            HStack(spacing: 0) {
                Text("STT").frame(width: 30, alignment: .center)
                Text("Model").frame(width: 105, alignment: .leading)
                Text("Tên sản phẩm").frame(maxWidth: .infinity, alignment: .leading)
                Text("ĐVT").frame(width: 36, alignment: .center)
                Text("SL").frame(width: 32, alignment: .center)
                Text("Đơn giá").frame(width: 80, alignment: .trailing)
                Text("Thành tiền").frame(width: 88, alignment: .trailing)
            }
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 16)
            .background(Color.orange)

            // Table Rows
            VStack(spacing: 0) {
                ForEach(0..<invoice.items.count, id: \.self) { index in
                    let item = invoice.items[index]
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .frame(width: 30, alignment: .center)
                            .font(.system(size: 9.5))

                        Text(item.model.isEmpty ? "—" : item.model)
                            .frame(width: 105, alignment: .leading)
                            .font(.system(size: 8.5, design: .monospaced))
                            .lineLimit(2)

                        Text(item.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(2)

                        Text(item.unit)
                            .frame(width: 36, alignment: .center)
                            .font(.system(size: 9.5))

                        Text("\(item.quantity)")
                            .frame(width: 32, alignment: .center)
                            .font(.system(size: 9.5, weight: .semibold))

                        Text(formatVndCurrency(item.price))
                            .frame(width: 80, alignment: .trailing)
                            .font(.system(size: 9.5))

                        Text(formatVndCurrency(item.total))
                            .frame(width: 88, alignment: .trailing)
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .padding(.vertical, aspectRatio == .ratio9_16 ? 4 : 6)
                    .padding(.horizontal, 16)
                    .background(index % 2 == 0 ? Color.white : Color.gray.opacity(0.1))

                    Divider().padding(.horizontal, 16)
                }
            }

            // Total Summary Section
            VStack(spacing: 4) {
                HStack {
                    Spacer()
                    Text("Tiền hàng (chưa thuế):")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(formatVndCurrency(invoice.subtotal))
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 110, alignment: .trailing)
                }

                if invoice.totalTax > 0 {
                    HStack {
                        Spacer()
                        Text("Tiền thuế VAT:")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatVndCurrency(invoice.totalTax))
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 110, alignment: .trailing)
                    }
                }

                HStack {
                    Spacer()
                    Text("TỔNG THANH TOÁN:")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.orange)
                    Text(formatVndCurrency(invoice.totalAmount))
                        .font(.system(size: 14.5, weight: .heavy))
                        .foregroundColor(.orange)
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Notes Section
            if !invoice.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ghi chú:")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.orange)
                    Text(invoice.notes)
                        .font(.system(size: 9.5))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            // If ratio is 6:19 (tall), add a flexible space or generous padding
            if aspectRatio == .ratio6_19 {
                Spacer(minLength: 20)
            }

            // Signatures Section
            HStack(alignment: .top) {
                VStack(spacing: aspectRatio == .ratio9_16 ? 26 : 38) {
                    Text("NGƯỜI MUA HÀNG")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("(Ký, ghi rõ họ tên)")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: aspectRatio == .ratio9_16 ? 26 : 38) {
                    Text("NGƯỜI BÁN HÀNG")
                        .font(.system(size: 10.5, weight: .bold))
                    Text("(Ký, ghi rõ họ tên)")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, aspectRatio == .ratio9_16 ? 18 : 26)
            .padding(.bottom, aspectRatio == .ratio9_16 ? 20 : 28)
        }
        .frame(width: aspectRatio.paperWidth)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - JPG Image Generator from View
extension View {
    func renderAsImage(targetSize: CGSize = CGSize(width: 595, height: 842)) -> UIImage? {
        let controller = UIHostingController(rootView: self.edgesIgnoringSafeArea(.all))
        guard let view = controller.view else { return nil }

        view.bounds = CGRect(origin: .zero, size: targetSize)
        view.backgroundColor = .white

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }
}

// MARK: - Image Share Activity Sheet
struct ShareSheet: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIActivityViewController
    let activityItems: [Any]

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheet>) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheet>) {}
}
