import SwiftUI
import UIKit
import Photos

// MARK: - Aspect Ratio Enum for Invoice
enum InvoiceAspectRatio: String, CaseIterable, Identifiable {
    case ratio9_16 = "9:16"
    case ratio6_19 = "6:19"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ratio9_16:
            return "Khổ 9:16 (Màn hình điện thoại / Zalo)"
        case .ratio6_19:
            return "Khổ 6:19 (Cuộn dài / Bill siêu thị)"
        }
    }

    var shortName: String {
        switch self {
        case .ratio9_16:
            return "Khổ 9:16"
        case .ratio6_19:
            return "Khổ 6:19"
        }
    }

    // Canvas width & height in points
    // Phone screen standard logic width: 390 pt (iPhone standard)
    var canvasWidth: CGFloat {
        switch self {
        case .ratio9_16:
            return 390.0
        case .ratio6_19:
            return 390.0
        }
    }

    func canvasHeight(itemsCount: Int) -> CGFloat {
        switch self {
        case .ratio9_16:
            // 9:16 standard smartphone screen: 390 * 16 / 9 ~ 693.3 pt
            // If items exceed standard bounds, expand dynamically while maintaining readable spacing
            let standardHeight = 390.0 * 16.0 / 9.0 // ~693.3
            let neededHeight: CGFloat = 340.0 + CGFloat(itemsCount * 28)
            return max(standardHeight, neededHeight)
        case .ratio6_19:
            // 6:19 tall bill scroll format: 390 * 19 / 6 = 1235.0 pt
            let standardHeight = 390.0 * 19.0 / 6.0 // 1235.0
            let neededHeight: CGFloat = 380.0 + CGFloat(itemsCount * 32)
            return max(standardHeight, neededHeight)
        }
    }
}

// MARK: - Photo Library Saver Helper (Sử dụng UIImageWriteToSavedPhotosAlbum an toàn tuyệt đối, không crash)
class PhotoLibrarySaver: NSObject {
    static let shared = PhotoLibrarySaver()
    private var completionHandler: ((Bool, String?) -> Void)?

    func saveImageToAlbum(_ image: UIImage, completion: @escaping (Bool, String?) -> Void) {
        self.completionHandler = completion

        // Kiểm tra quyền Photo Library trước khi ghi
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .restricted || status == .denied {
            completion(false, "Vui lòng vào Cài đặt > Quyền riêng tư > Ảnh để cấp quyền lưu ảnh.")
            return
        }

        // Gọi UIKit API lưu ảnh vào Camera Roll với selector callback
        UIImageWriteToSavedPhotosAlbum(
            image,
            self,
            #selector(image(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                self?.completionHandler?(false, error.localizedDescription)
            } else {
                self?.completionHandler?(true, nil)
            }
            self?.completionHandler = nil
        }
    }
}

// MARK: - Invoice Paper View (Dàn trang chuẩn màn hình điện thoại 390pt)
struct InvoicePaperView: View {
    let invoice: InvoiceRecord
    let company: CompanyInfo
    var aspectRatio: InvoiceAspectRatio = .ratio9_16

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"
        return df
    }()

    var is916: Bool { aspectRatio == .ratio9_16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. Header Công Ty
            VStack(alignment: .leading, spacing: is916 ? 2 : 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(company.name.isEmpty ? "CÔNG TY GIẢI PHÁP CÔNG NGHỆ QUỐC HUY" : company.name)
                            .font(.system(size: is916 ? 11.5 : 13, weight: .bold))
                            .foregroundColor(.orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !company.address.isEmpty {
                            Text("Đ/c: \(company.address)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.gray)
                                .lineLimit(2)
                        }

                        Text("Hotline/Zalo: \(company.phone.isEmpty ? "0909080119" : company.phone)")
                            .font(.system(size: is916 ? 9.5 : 10.5, weight: .semibold))
                            .foregroundColor(.primary)

                        if !company.email.isEmpty {
                            Text("Email: \(company.email)")
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                        }
                    }

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ĐƠN VỊ LẮP ĐẶT")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.orange)

                        Image(systemName: "video.badge.checkmark")
                            .font(.system(size: is916 ? 20 : 24))
                            .foregroundColor(.orange)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(.horizontal, is916 ? 12 : 16)
            .padding(.top, is916 ? 12 : 18)

            // Đường gạch cam ngăn cách
            Rectangle()
                .fill(Color.orange.opacity(0.8))
                .frame(height: 1.5)
                .padding(.horizontal, is916 ? 12 : 16)
                .padding(.vertical, is916 ? 6 : 10)

            // 2. Tiêu Đề Hóa Đơn
            VStack(spacing: 2) {
                Text("HÓA ĐƠN BÁN HÀNG")
                    .font(.system(size: is916 ? 16 : 19, weight: .heavy))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Số: \(invoice.invoiceNo)")
                    .font(.system(size: is916 ? 9.5 : 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, is916 ? 6 : 10)

            // 3. Thông Tin Khách Hàng & Hóa Đơn
            if is916 {
                // Khổ 9:16 trên điện thoại: Xếp dạng thẻ bo góc nhỏ gọn
                VStack(spacing: 3) {
                    HStack {
                        Text("Khách hàng:")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(invoice.customerName.isEmpty ? "Khách vãng lai" : invoice.customerName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Ngày:")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Text(dateFormatter.string(from: invoice.date))
                            .font(.system(size: 9.5, weight: .semibold))
                    }

                    HStack {
                        Text("Điện thoại:")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(invoice.customerPhone.isEmpty ? "—" : invoice.customerPhone)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Bảo hành:")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        Text("\(invoice.warrantyMonths) tháng")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.orange)
                    }

                    if !invoice.customerAddress.isEmpty {
                        HStack(alignment: .top) {
                            Text("Địa chỉ:")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(invoice.customerAddress)
                                .font(.system(size: 9.5))
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.06))
                .cornerRadius(6)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            } else {
                // Khổ 6:19 dài: 2 Cột thông thoáng
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Thông tin khách hàng")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)

                        HStack {
                            Text("Khách:").foregroundColor(.secondary).font(.system(size: 9.5))
                            Text(invoice.customerName.isEmpty ? "Khách vãng lai" : invoice.customerName)
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        HStack {
                            Text("SĐT:").foregroundColor(.secondary).font(.system(size: 9.5))
                            Text(invoice.customerPhone.isEmpty ? "—" : invoice.customerPhone)
                                .font(.system(size: 9.5))
                        }
                        if !invoice.customerAddress.isEmpty {
                            HStack(alignment: .top) {
                                Text("Đ/c:").foregroundColor(.secondary).font(.system(size: 9.5))
                                Text(invoice.customerAddress).font(.system(size: 9.5)).lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Thông tin HĐ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)

                        HStack {
                            Text("Ngày:").foregroundColor(.secondary).font(.system(size: 9.5))
                            Text(dateFormatter.string(from: invoice.date)).font(.system(size: 9.5))
                        }
                        HStack {
                            Text("Bảo hành:").foregroundColor(.secondary).font(.system(size: 9.5))
                            Text("\(invoice.warrantyMonths) tháng").font(.system(size: 9.5, weight: .semibold))
                        }
                    }
                    .frame(width: 130, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            // 4. Bảng Sản Phẩm
            // Bố cục Header: Dành cho màn hình điện thoại chiều rộng 390pt
            HStack(spacing: 0) {
                Text("STT").frame(width: 24, alignment: .center)
                Text("Tên thiết bị / Model").frame(maxWidth: .infinity, alignment: .leading)
                Text("SL").frame(width: 28, alignment: .center)
                Text("Đơn giá").frame(width: 66, alignment: .trailing)
                Text("Thành tiền").frame(width: 76, alignment: .trailing)
            }
            .font(.system(size: is916 ? 8.5 : 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 4)
            .padding(.horizontal, is916 ? 10 : 12)
            .background(Color.orange)

            // Dòng Sản Phẩm
            VStack(spacing: 0) {
                ForEach(0..<invoice.items.count, id: \.self) { index in
                    let item = invoice.items[index]
                    HStack(spacing: 0) {
                        Text("\(index + 1)")
                            .frame(width: 24, alignment: .center)
                            .font(.system(size: 8.5))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: is916 ? 8.5 : 9, weight: .semibold))
                                .lineLimit(2)
                            if !item.model.isEmpty {
                                Text("Mã: \(item.model)")
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(item.quantity)")
                            .frame(width: 28, alignment: .center)
                            .font(.system(size: 8.5, weight: .bold))

                        Text(formatVndCurrency(item.price))
                            .frame(width: 66, alignment: .trailing)
                            .font(.system(size: 8))

                        Text(formatVndCurrency(item.total))
                            .frame(width: 76, alignment: .trailing)
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .padding(.vertical, is916 ? 3.5 : 5)
                    .padding(.horizontal, is916 ? 10 : 12)
                    .background(index % 2 == 0 ? Color.white : Color.gray.opacity(0.08))

                    Divider().padding(.horizontal, is916 ? 10 : 12)
                }
            }

            // 5. Tổng Tiền & Ghi Chú
            VStack(spacing: 3) {
                HStack {
                    Spacer()
                    Text("Tiền hàng:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(formatVndCurrency(invoice.subtotal))
                        .font(.system(size: 9.5, weight: .medium))
                        .frame(width: 85, alignment: .trailing)
                }

                if invoice.totalTax > 0 {
                    HStack {
                        Spacer()
                        Text("Thuế VAT:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(formatVndCurrency(invoice.totalTax))
                            .font(.system(size: 9.5, weight: .medium))
                            .frame(width: 85, alignment: .trailing)
                    }
                }

                HStack {
                    Spacer()
                    Text("TỔNG THANH TOÁN:")
                        .font(.system(size: is916 ? 10.5 : 11.5, weight: .bold))
                        .foregroundColor(.orange)
                    Text(formatVndCurrency(invoice.totalAmount))
                        .font(.system(size: is916 ? 12.5 : 13.5, weight: .heavy))
                        .foregroundColor(.orange)
                        .frame(width: 105, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(5)
            }
            .padding(.horizontal, is916 ? 12 : 16)
            .padding(.top, 6)

            // Ghi chú nếu có
            if !invoice.notes.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ghi chú:")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.orange)
                    Text(invoice.notes)
                        .font(.system(size: 8))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, is916 ? 12 : 16)
                .padding(.top, 4)
            }

            if !is916 {
                Spacer(minLength: 16)
            }

            // 6. Chữ Ký
            HStack(alignment: .top) {
                VStack(spacing: is916 ? 20 : 30) {
                    Text("NGƯỜI MUA HÀNG")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("(Ký, ghi rõ họ tên)")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: is916 ? 20 : 30) {
                    Text("NGƯỜI BÁN HÀNG")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("(Ký, ghi rõ họ tên)")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, is916 ? 12 : 16)
            .padding(.top, is916 ? 14 : 22)
            .padding(.bottom, is916 ? 16 : 24)
        }
        .frame(width: aspectRatio.canvasWidth)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - JPG Image Generator from View (Hỗ trợ ImageRenderer iOS 16+ và UIHostingController kèm Window trên iOS 15)
extension View {
    @MainActor
    func renderAsImage(targetSize: CGSize = CGSize(width: 390, height: 693.3)) -> UIImage? {
        // 1. Đối với iOS 16+, dùng ImageRenderer (Chính chủ Apple, xuất ảnh sắc nét 100%, không bao giờ bị trắng)
        if #available(iOS 16.0, *) {
            let wrappedView = self.frame(width: targetSize.width, height: targetSize.height)
            let renderer = ImageRenderer(content: wrappedView)
            renderer.proposedSize = ProposedViewSize(targetSize)
            renderer.scale = 2.0
            if let img = renderer.uiImage {
                return img
            }
        }

        // 2. Dự phòng chuẩn UIKit (iOS 15): Gắn vào UIWindow tạm thời để hệ thống kích hoạt render layout đầy đủ
        let controller = UIHostingController(rootView: self.edgesIgnoringSafeArea(.all))
        guard let view = controller.view else { return nil }

        view.frame = CGRect(origin: .zero, size: targetSize)
        view.backgroundColor = .white

        // Tìm keyWindow hiện tại hoặc tạo cửa sổ ảo để view có môi trường render thật
        let currentWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        let tempWindow = currentWindow ?? UIWindow(frame: CGRect(origin: .zero, size: targetSize))
        tempWindow.addSubview(view)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let capturedImage = renderer.image { ctx in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }

        view.removeFromSuperview()
        return capturedImage
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
