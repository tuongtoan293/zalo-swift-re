import Foundation
import CoreGraphics
import Vision

/// Nhận dạng chữ trong ảnh bằng Vision (`VNRecognizeTextRequest`, `.accurate`, có sửa theo ngôn ngữ), và trong cùng lượt
/// đọc mã QR / mã vạch (`VNDetectBarcodesRequest`, mọi symbology máy hỗ trợ): một `perform([...])` trên cùng handler.
///
/// Concurrency (Swift 6, SDK 15): `CGImage`, `NSImage` và các kiểu `VN*` không Sendable, nên toàn bộ việc giải mã và
/// nhận dạng chạy trong một hàm `nonisolated` đồng bộ ngoài main (`Task.detached`), không có closure nào viết trong ngữ cảnh
/// `@MainActor` bị Vision gọi lại trên hàng đợi nền (đã từng crash EXC_BREAKPOINT vì kiểm actor). Chỉ `[String]` (từng
/// dòng, `ScannedCode`) quay về main; ảnh nguồn đi qua lại trong `ScanSource`.
///
/// Chọn vùng: ảnh được giải mã một lần ở độ phân giải gốc (`decode`), rồi mỗi lượt quét CẮT `CGImage` theo vùng pixel
/// (`RegionMapping.pixelRect`) trước khi thu nhỏ về `maxPixelSize`, nên chữ nhỏ trong một vùng của ảnh lớn vẫn giữ chi tiết.
/// Không dùng `regionOfInterest`: nó vẫn nhận ảnh đã thu nhỏ của cả khung.
enum TextRecognizer {
    /// Ảnh nguồn đã giải mã (đúng chiều EXIF, độ phân giải gốc). `CGImage` bất biến sau khi tạo nên chia sẻ giữa các luồng
    /// được; SDK 15 chưa đánh dấu nó Sendable nên bọc lại, giống `SendableImage` của MediaLoader.
    struct ScanSource: @unchecked Sendable {
        let cgImage: CGImage
        var pixelSize: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
    }

    /// Kết quả một lượt quét: chữ theo dòng và các mã đọc được.
    struct ImageScan: Equatable, Sendable {
        var lines: [String]
        var codes: [ScannedCode]
    }

    enum Failure: Error, Equatable {
        /// Byte không giải mã được thành ảnh.
        case undecodable
    }

    /// Ngôn ngữ muốn dùng, theo thứ tự ưu tiên. Mã tiếng Việt của Vision là "vi-VT" (không phải "vi-VN").
    static let preferredLanguages = ["vi-VT", "en-US"]
    /// Cạnh dài nhất của ảnh đưa vào Vision (áp lên ảnh ĐÃ CẮT): đủ cho chữ nhỏ trong ảnh chụp màn hình.
    static let maxPixelSize = 4096
    /// Cạnh dài nhất khi giải mã ảnh nguồn: gốc cho mọi ảnh Zalo thường gặp, chỉ chặn ảnh bất thường làm tràn bộ nhớ.
    static let maxSourcePixelSize = 12_000

    /// Những ngôn ngữ trong `preferredLanguages` mà Vision trên máy này hỗ trợ (tra lúc chạy, không đoán theo SDK).
    /// Rỗng thì để Vision tự chọn mặc định.
    nonisolated static func languages(supported: [String]) -> [String] {
        preferredLanguages.filter(supported.contains)
    }

    /// `supportedRecognitionLanguages()` của mức `.accurate` trên máy đang chạy.
    nonisolated static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// Giải mã `data` ở độ phân giải gốc, xoay đúng chiều EXIF, ngoài main.
    static func decode(imageData data: Data) async throws -> ScanSource {
        try await Task.detached(priority: .userInitiated) {
            try decodeSync(imageData: data)
        }.value
    }

    nonisolated static func decodeSync(imageData data: Data) throws -> ScanSource {
        // Dùng lại bộ giải mã của MediaLoader (ImageIO, xoay theo EXIF).
        guard let image = MediaLoader.decode(data, maxPixelSize: maxSourcePixelSize),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure.undecodable }
        return ScanSource(cgImage: cgImage)
    }

    /// Quét chữ và mã trong `region` (pixel, gốc trên trái, xem `RegionMapping`) hoặc cả ảnh khi nil, ngoài main.
    static func scan(_ source: ScanSource, region: CGRect? = nil) async throws -> ImageScan {
        try await Task.detached(priority: .userInitiated) {
            try scanSync(source, region: region)
        }.value
    }

    /// Cả ảnh từ byte: giải mã rồi quét.
    static func scan(imageData data: Data) async throws -> ImageScan {
        try await Task.detached(priority: .userInitiated) {
            try scanSync(decodeSync(imageData: data))
        }.value
    }

    /// Bản đồng bộ của `scan(imageData:)`. Gọi ngoài main.
    nonisolated static func scanSync(imageData data: Data) throws -> ImageScan {
        try scanSync(decodeSync(imageData: data))
    }

    /// Cắt theo `region` (nếu có), thu về `maxPixelSize`, rồi quét. Gọi ngoài main.
    nonisolated static func scanSync(_ source: ScanSource, region: CGRect? = nil) throws -> ImageScan {
        var image = source.cgImage
        if let region {
            // `CGImage.cropping(to:)` tính theo pixel, gốc ở góc TRÊN trái: cùng hệ với `RegionMapping.pixelRect`.
            guard let cropped = image.cropping(to: region.integral) else { return ImageScan(lines: [], codes: []) }
            image = cropped
        }
        return try scanSync(fitWithin(image, maxPixelSize: maxPixelSize))
    }

    /// Thu nhỏ để cạnh dài nhất không quá `maxPixelSize` (giữ tỉ lệ); ảnh đã đủ nhỏ thì trả nguyên.
    nonisolated static func fitWithin(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Quét đồng bộ trên luồng gọi: một `perform` cho cả hai request, chạy xong mới trả về; kết quả đọc thẳng từ
    /// `request.results` (không dùng completion handler).
    nonisolated static func scanSync(_ image: CGImage) throws -> ImageScan {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        let languages = languages(supported: (try? text.supportedRecognitionLanguages()) ?? [])
        if !languages.isEmpty { text.recognitionLanguages = languages }
        let barcodes = VNDetectBarcodesRequest()
        // Mọi loại máy hỗ trợ, tra lúc chạy (macOS 15.7.9: 24 loại, revision 4).
        if let supported = try? barcodes.supportedSymbologies(), !supported.isEmpty { barcodes.symbologies = supported }
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([text, barcodes])
        let pieces = (text.results ?? []).compactMap { observation -> TextPiece? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return TextPiece(text: text, box: observation.boundingBox)
        }
        let codes = (barcodes.results ?? []).compactMap { observation -> ScannedCode? in
            guard let payload = observation.payloadStringValue else { return nil }
            return ScannedCode(symbology: observation.symbology.rawValue, payload: payload)
        }
        return ImageScan(lines: readingOrder(pieces), codes: ScannedCode.unique(codes))
    }

    /// Một cụm chữ Vision trả về và khung của nó (toạ độ chuẩn hoá 0…1, gốc ở góc dưới trái).
    struct TextPiece: Equatable, Sendable {
        var text: String
        var box: CGRect
    }

    /// Xếp các cụm theo thứ tự đọc: trên xuống, trái sang phải. Các cụm cùng hàng (tâm dọc cách nhau dưới nửa chiều cao
    /// cụm thấp hơn) gộp thành một dòng, nối bằng khoảng trắng: ví dụ nhãn và giá trị ở hai cột của hoá đơn.
    nonisolated static func readingOrder(_ pieces: [TextPiece]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[TextPiece]] = []
        for piece in sorted {
            if let last = rows.last?.last, sameRow(last, piece) {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    private nonisolated static func sameRow(_ a: TextPiece, _ b: TextPiece) -> Bool {
        abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) / 2
    }
}
