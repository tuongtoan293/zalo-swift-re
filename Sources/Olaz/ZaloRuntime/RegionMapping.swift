import CoreGraphics

/// Đổi vùng chọn trên ảnh xem trước (toạ độ view, điểm) sang vùng pixel trên ảnh gốc, cho "Trích xuất chữ và mã QR".
///
/// Hàm thuần. Ba hệ toạ độ:
/// * view: điểm SwiftUI, gốc góc TRÊN trái; ảnh nằm trong `fittedRect` (aspect-fit, căn giữa, có thể có viền hai bên);
/// * chuẩn hoá: 0…1 theo ảnh, gốc góc TRÊN trái. Vùng chọn được lưu ở hệ này nên vẫn đúng khi đổi kích thước bảng;
/// * pixel: pixel của `CGImage` gốc, gốc góc TRÊN trái, đúng hệ của `CGImage.cropping(to:)`.
/// Cả ba cùng gốc trên trái nên không lật trục y. (Chỉ Vision dùng gốc dưới trái, và nó chỉ chạy trên ảnh đã cắt.)
/// Ảnh retina không cần xử lý riêng: tỉ lệ đổi lấy từ số pixel thật của ảnh chia cho khung hiển thị, không từ
/// `backingScaleFactor` của màn hình.
enum RegionMapping {
    /// Vùng nhỏ hơn thế này (điểm trên màn hình, theo mỗi chiều) coi như bấm nhầm, bỏ qua.
    static let minimumSelection: CGFloat = 8

    /// Khung ảnh `imagePixels` khi vừa khung (aspect fit) trong `viewSize`, căn giữa.
    static func fittedRect(imagePixels: CGSize, in viewSize: CGSize) -> CGRect {
        guard imagePixels.width > 0, imagePixels.height > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / imagePixels.width, viewSize.height / imagePixels.height)
        let size = CGSize(width: imagePixels.width * scale, height: imagePixels.height * scale)
        return CGRect(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Hình chữ nhật từ hai điểm kéo (kéo theo hướng nào cũng được).
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Vùng chọn (view) → chuẩn hoá. Phần tràn ra ngoài ảnh bị kẹp lại; nil khi phần còn lại nhỏ hơn `minimumSelection`.
    static func normalized(selection: CGRect, fitted: CGRect) -> CGRect? {
        guard fitted.width > 0, fitted.height > 0 else { return nil }
        let clamped = selection.standardized.intersection(fitted)
        guard !clamped.isNull, clamped.width >= minimumSelection, clamped.height >= minimumSelection else { return nil }
        return CGRect(x: (clamped.minX - fitted.minX) / fitted.width, y: (clamped.minY - fitted.minY) / fitted.height,
                      width: clamped.width / fitted.width, height: clamped.height / fitted.height)
    }

    /// Chuẩn hoá → view, để vẽ khung chọn trên ảnh xem trước.
    static func viewRect(normalized: CGRect, fitted: CGRect) -> CGRect {
        CGRect(x: fitted.minX + normalized.minX * fitted.width, y: fitted.minY + normalized.minY * fitted.height,
               width: normalized.width * fitted.width, height: normalized.height * fitted.height)
    }

    /// Chuẩn hoá → pixel nguyên, kẹp trong ảnh, ít nhất 1×1. Nil nếu vùng nằm ngoài ảnh.
    static func pixelRect(normalized: CGRect, imagePixels: CGSize) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: imagePixels)
        let box = normalized.standardized
        // Làm tròn từng mép (không dùng `integral`, vốn nới 1 px khi sai số dấu phẩy động làm 200 thành 200.0000001).
        let x0 = (box.minX * imagePixels.width).rounded(), x1 = (box.maxX * imagePixels.width).rounded()
        let y0 = (box.minY * imagePixels.height).rounded(), y1 = (box.maxY * imagePixels.height).rounded()
        let clamped = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return clamped
    }

    /// Cả đường: vùng chọn trên view `viewSize` (ảnh aspect-fit bên trong) → vùng pixel trên ảnh `imagePixels`.
    static func pixelRect(selection: CGRect, viewSize: CGSize, imagePixels: CGSize) -> CGRect? {
        let fitted = fittedRect(imagePixels: imagePixels, in: viewSize)
        return normalized(selection: selection, fitted: fitted).flatMap { pixelRect(normalized: $0, imagePixels: imagePixels) }
    }
}
