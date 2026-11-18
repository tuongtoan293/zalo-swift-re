import Foundation
import CoreGraphics
import Vision

/// Nhận dạng chữ trong ảnh bằng Vision (`VNRecognizeTextRequest`, `.accurate`, có sửa theo ngôn ngữ), và trong cùng lượt
/// đọc mã QR / mã vạch (`VNDetectBarcodesRequest`, mọi symbology máy hỗ trợ): một `perform([...])` trên cùng handler.
///
/// Concurrency (Swift 6, SDK 15): `CGImage`, `NSImage` và các kiểu `VN*` không Sendable, nên toàn bộ việc giải mã và
/// nhận dạng chạy trong một hàm `nonisolated` đồng bộ ngoài main (`Task.detached`), không có closure nào viết trong ngữ cảnh
/// `@MainActor` bị Vision gọi lại trên hàng đợi nền (đã từng crash EXC_BREAKPOINT vì kiểm actor). Chỉ `[String]` (từng
/// dòng, `ScannedCode`) quay về main.
enum TextRecognizer {
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
    /// Cạnh dài nhất khi giải mã: đủ cho chữ nhỏ trong ảnh chụp màn hình, không giải mã ảnh 48 MP nguyên cỡ.
    static let maxPixelSize = 4096

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

    /// Giải mã `data` (xoay đúng chiều EXIF, thu về `maxPixelSize`) rồi quét chữ và mã, ngoài main.
    static func scan(imageData data: Data) async throws -> ImageScan {
        try await Task.detached(priority: .userInitiated) {
            try scanSync(imageData: data)
        }.value
    }

    /// Bản đồng bộ của `scan(imageData:)`. Gọi ngoài main.
    nonisolated static func scanSync(imageData data: Data) throws -> ImageScan {
        // Dùng lại bộ giải mã của MediaLoader: xoay theo EXIF, thu nhỏ bằng ImageIO.
        guard let image = MediaLoader.decode(data, maxPixelSize: maxPixelSize),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure.undecodable }
        return try scanSync(cgImage)
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
