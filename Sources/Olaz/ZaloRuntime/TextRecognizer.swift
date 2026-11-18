import Foundation
import CoreGraphics
import Vision

/// Nhận dạng chữ trong ảnh bằng Vision (`VNRecognizeTextRequest`, `.accurate`, có sửa theo ngôn ngữ).
///
/// Concurrency (Swift 6, SDK 15): `CGImage`, `NSImage` và các kiểu `VN*` không Sendable, nên toàn bộ việc giải mã và
/// nhận dạng chạy trong một hàm `nonisolated` đồng bộ ngoài main (`Task.detached`), không có closure nào viết trong ngữ cảnh
/// `@MainActor` bị Vision gọi lại trên hàng đợi nền (đã từng crash EXC_BREAKPOINT vì kiểm actor). Chỉ `[String]` (từng
/// dòng) quay về main.
enum TextRecognizer {
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

    /// Giải mã `data` (xoay đúng chiều EXIF, thu về `maxPixelSize`) rồi nhận dạng, ngoài main. Trả các dòng theo thứ tự đọc.
    static func recognize(imageData data: Data) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try recognizeLines(imageData: data)
        }.value
    }

    /// Bản đồng bộ của `recognize(imageData:)`. Gọi ngoài main.
    nonisolated static func recognizeLines(imageData data: Data) throws -> [String] {
        // Dùng lại bộ giải mã của MediaLoader: xoay theo EXIF, thu nhỏ bằng ImageIO.
        guard let image = MediaLoader.decode(data, maxPixelSize: maxPixelSize),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure.undecodable }
        return try recognizeLines(in: cgImage)
    }

    /// Nhận dạng đồng bộ trên luồng gọi: `perform` chạy xong mới trả về, kết quả đọc thẳng từ `request.results`
    /// (không dùng completion handler).
    nonisolated static func recognizeLines(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let languages = languages(supported: (try? request.supportedRecognitionLanguages()) ?? [])
        if !languages.isEmpty { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        let pieces = (request.results ?? []).compactMap { observation -> TextPiece? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return TextPiece(text: text, box: observation.boundingBox)
        }
        return readingOrder(pieces)
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
