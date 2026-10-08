import SwiftUI
import UIKit

// MARK: - Invoice Bill View (To Render and Export as Image)
struct InvoicePaperView: View {
    let invoice: InvoiceRecord
    let company: CompanyInfo

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Company Info & Title
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)

                    Text("Địa chỉ: \(company.address)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)

                    Text("Hotline/Zalo: \(company.phone)")
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)

                    Image(systemName: "video.badge.checkmark")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Divider()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            // Title
            VStack(spacing: 4) {
                Text("HÓA ĐƠN BÁN HÀNG")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.orange)
                    .tracking(1.5)

                Rectangle()
                    .fill(Color.orange)
                    .frame(height: 2)
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)

            // Invoice & Customer Info 2-Column Grid
            HStack(alignment: .top, spacing: 16) {
                // Left: Thông tin hóa đơn
                VStack(alignment: .leading, spacing: 5) {
                    Text("Thông tin hóa đơn")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)

                    HStack {
                        Text("Số hóa đơn:").foregroundColor(.secondary).font(.system(size: 11))
                        Text(invoice.invoiceNo).font(.system(size: 11, weight: .bold))
                    }
                    HStack {
                        Text("Ngày lập:").foregroundColor(.secondary).font(.system(size: 11))
                        Text(dateFormatter.string(from: invoice.date)).font(.system(size: 11))
                    }
                    HStack {
                        Text("Bảo hành:").foregroundColor(.secondary).font(.system(size: 11))
                        Text("\(invoice.warrantyMonths) tháng").font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: Thông tin khách hàng
                VStack(alignment: .leading, spacing: 5) {
                    Text("Thông tin khách hàng")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.orange)

                    HStack {
                        Text("Khách hàng:").foregroundColor(.secondary).font(.system(size: 11))
                        Text(invoice.customerName.isEmpty ? "Khách vãng lai" : invoice.customerName)
                            .font(.system(size: 11, weight: .bold))
                    }
                    HStack {
                        Text("Điện thoại:").foregroundColor(.secondary).font(.system(size: 11))
                        Text(invoice.customerPhone.isEmpty ? "—" : invoice.customerPhone)
                            .font(.system(size: 11))
                    }
                    HStack(alignment: .top) {
                        Text("Địa chỉ:").foregroundColor(.secondary).font(.system(size: 11))
                        Text(invoice.customerAddress.isEmpty ? "—" : invoice.customerAddress)
                            .font(.system(size: 11))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // Items Table Header
            HStack(spacing: 0) {
                Text("STT").frame(width: 32, alignment: .center)
                Text("Model").frame(width: 110, alignment: .leading)
                Text("Tên sản phẩm").frame(maxWidth: .infinity, alignment: .leading)
                Text("ĐVT").frame(width: 36, alignment: .center)
                Text("SL").frame(width: 32, alignment: .center)
                Text("Đơn giá").frame(width: 80, alignment: .trailing)
                Text("Thành tiền").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(Color.orange)

            // Table Rows
            VStack(spacing: 0) {
                ForEach(0..<invoice.items.count, id: \.self) { index in
                    let item = invoice.items[index]
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .frame(width: 32, alignment: .center)
                            .font(.system(size: 10))

                        Text(item.model.isEmpty ? "—" : item.model)
                            .frame(width: 110, alignment: .leading)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(2)

                        Text(item.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)

                        Text(item.unit)
                            .frame(width: 36, alignment: .center)
                            .font(.system(size: 10))

                        Text("\(item.quantity)")
                            .frame(width: 32, alignment: .center)
                            .font(.system(size: 10, weight: .semibold))

                        Text(formatVndCurrency(item.price))
                            .frame(width: 80, alignment: .trailing)
                            .font(.system(size: 10))

                        Text(formatVndCurrency(item.total))
                            .frame(width: 90, alignment: .trailing)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.vertical, 6)
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(formatVndCurrency(invoice.subtotal))
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 110, alignment: .trailing)
                }

                if invoice.totalTax > 0 {
                    HStack {
                        Spacer()
                        Text("Tiền thuế VAT:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatVndCurrency(invoice.totalTax))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 110, alignment: .trailing)
                    }
                }

                HStack {
                    Spacer()
                    Text("TỔNG THANH TOÁN:")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)
                    Text(formatVndCurrency(invoice.totalAmount))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(.orange)
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Notes Section
            if !invoice.notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ghi chú:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text(invoice.notes)
                        .font(.system(size: 10))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            // Signatures Section
            HStack(alignment: .top) {
                VStack(spacing: 35) {
                    Text("NGƯỜI MUA HÀNG")
                        .font(.system(size: 11, weight: .bold))
                    Text("(Ký, ghi rõ họ tên)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 35) {
                    Text("NGƯỜI BÁN HÀNG")
                        .font(.system(size: 11, weight: .bold))
                    Text("(Ký, ghi rõ họ tên)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 25)
        }
        .frame(width: 595) // Standard A4 width at 72 dpi
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
