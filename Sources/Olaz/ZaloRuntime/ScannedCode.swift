import Foundation

/// Một mã QR / mã vạch đọc được trong ảnh. Chỉ giữ chuỗi: loại mã (rawValue của `VNBarcodeSymbology`) và nội dung,
/// nên Sendable và không kéo kiểu Vision ra khỏi luồng quét.
struct ScannedCode: Hashable, Identifiable, Sendable {
    /// rawValue của `VNBarcodeSymbology`, ví dụ "VNBarcodeSymbologyQR".
    var symbology: String
    var payload: String

    var id: String { symbology + "\u{0}" + payload }

    /// Tên loại mã để hiện: "Mã QR", "Aztec", "EAN-13", "Code 128"…
    var kindName: String { Self.kindName(symbology: symbology) }

    /// Khử trùng lặp theo cặp (loại, nội dung), giữ thứ tự gặp đầu tiên (Vision có thể báo cùng một mã nhiều lần).
    static func unique(_ codes: [ScannedCode]) -> [ScannedCode] {
        var seen = Set<ScannedCode>()
        return codes.filter { seen.insert($0).inserted }
    }

    static func kindName(symbology: String) -> String {
        let name = symbology.hasPrefix("VNBarcodeSymbology") ? String(symbology.dropFirst("VNBarcodeSymbology".count)) : symbology
        switch name {
        case "QR": return "Mã QR"
        case "MicroQR": return "Micro QR"
        case "EAN13": return "EAN-13"
        case "EAN8": return "EAN-8"
        case "UPCE": return "UPC-E"
        case "ITF14": return "ITF-14"
        case "I2of5", "I2of5Checksum": return "ITF"
        case "Code128": return "Code 128"
        case "Code93", "Code93i": return "Code 93"
        case "Code39", "Code39Checksum", "Code39FullASCII", "Code39FullASCIIChecksum": return "Code 39"
        case "MicroPDF417": return "MicroPDF417"
        case "GS1DataBar", "GS1DataBarExpanded", "GS1DataBarLimited": return "GS1 DataBar"
        case "MSIPlessey": return "MSI Plessey"
        case "": return "Mã vạch"
        default: return name
        }
    }

    /// Liên kết được phép mở bằng nút "Mở": chỉ http/https, có host, không có khoảng trắng hay ký tự điều khiển.
    /// Mọi scheme khác (javascript:, file:, zalo:, data:…) và chuỗi thường trả nil, chỉ cho sao chép. Không bao giờ tự mở.
    static func openableURL(_ payload: String) -> URL? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = components.url else { return nil }
        return url
    }

    var openableURL: URL? { Self.openableURL(payload) }

    /// Host hiện cạnh nút "Mở" để người dùng thấy trước sẽ đi đâu (QR trong ảnh người lạ gửi có thể là link lừa đảo).
    /// Lấy từ URL đã phân tích, nên "https://zalo.me@evil.example" hiện "evil.example" chứ không phải "zalo.me".
    var openableHost: String? { openableURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.host?.lowercased() } }
}
