import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import Olaz

/// Quét theo vùng trên một ảnh lớn tự sinh 4000×3000: vài dòng chữ rải rác và một mã QR.
@Suite struct RegionScanTests {
    static let size = CGSize(width: 4000, height: 3000)
    static let qrPayload = "https://zalo.me/test-olaz"
    /// Chữ và vị trí góc trên trái (pixel, gốc trên trái).
    static let texts: [(String, CGPoint)] = [
        ("Hóa đơn số 1234", CGPoint(x: 200, y: 200)),
        ("Mã 0901234567 Hà Nội", CGPoint(x: 2300, y: 900)),
        ("Tổng cộng 150000", CGPoint(x: 300, y: 1700)),
        ("Cảm ơn quý khách", CGPoint(x: 2200, y: 2600)),
    ]
    static let qrOrigin = CGPoint(x: 600, y: 2300)

    @Test func regionReturnsOnlyTheTextInsideIt() async throws {
        let source = try #require(Self.source())
        // Quanh dòng thứ hai: 2300…3700 × 860…1020.
        let scan = try await TextRecognizer.scan(source, region: CGRect(x: 2250, y: 860, width: 1400, height: 160))
        #expect(scan.lines == ["Mã 0901234567 Hà Nội"])
        #expect(scan.codes.isEmpty)
    }

    @Test func regionAroundTheQRReturnsOnlyTheCode() async throws {
        let source = try #require(Self.source())
        let side = CGFloat(try #require(Self.qrSide()))
        let scan = try await TextRecognizer.scan(source, region: CGRect(x: Self.qrOrigin.x - 40, y: Self.qrOrigin.y - 40,
                                                                        width: side + 80, height: side + 80))
        #expect(scan.codes == [ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: Self.qrPayload)])
        #expect(scan.lines.isEmpty)
    }

    @Test func regionOutsideTheImageReturnsNothing() throws {
        let source = try #require(Self.source())
        #expect(try TextRecognizer.scanSync(source, region: CGRect(x: 5000, y: 5000, width: 100, height: 100))
                == TextRecognizer.ImageScan(lines: [], codes: []))
    }

    /// Số đo cho thân commit: cả ảnh so với một vùng nhỏ (chạy tuần tự, cùng nguồn, sau một lượt khởi động Vision).
    @Test func wholeImageVersusSmallRegionTiming() throws {
        let source = try #require(Self.source())
        let region = CGRect(x: 2250, y: 860, width: 1400, height: 160)
        _ = try TextRecognizer.scanSync(source, region: region)  // khởi động mô hình
        var wholeTimes: [Double] = [], regionTimes: [Double] = []
        var whole = TextRecognizer.ImageScan(lines: [], codes: [])
        for _ in 0..<3 {
            var start = Date()
            whole = try TextRecognizer.scanSync(source)
            wholeTimes.append(Date().timeIntervalSince(start))
            start = Date()
            _ = try TextRecognizer.scanSync(source, region: region)
            regionTimes.append(Date().timeIntervalSince(start))
        }
        let format = { (values: [Double]) in values.map { String(format: "%.3f", $0) }.joined(separator: ", ") }
        print("Đo 4000x3000: cả ảnh [\(format(wholeTimes))] s, vùng 1400x160 [\(format(regionTimes))] s")
        // Cả ảnh phải thấy đủ 4 dòng và mã QR. So phần số: dấu tiếng Việt ở chữ to rải rác có thể sai một ký tự
        // (đã gặp "Tống" thay cho "Tổng").
        #expect(whole.lines.count == Self.texts.count)
        #expect(Set(whole.lines.map(TextFilter.digits.apply)) == Set(Self.texts.map { TextFilter.digits.apply($0.0) }))
        #expect(whole.codes.map(\.payload) == [Self.qrPayload])
    }

    // MARK: Ảnh mẫu

    static func qrSide() -> Int? { TextRecognizerTests.qrImage(qrPayload).map { max($0.width, $0.height) } }

    static func source() -> TextRecognizer.ScanSource? {
        let width = Int(size.width), height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 72, nil)
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        for (text, topLeft) in texts {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): black,
            ])
            // CGContext gốc dưới trái: đường chân chữ ở dưới mép trên khoảng 72 pt.
            context.textPosition = CGPoint(x: topLeft.x, y: CGFloat(height) - topLeft.y - 72)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        guard let qr = TextRecognizerTests.qrImage(qrPayload) else { return nil }
        context.draw(qr, in: CGRect(x: qrOrigin.x, y: CGFloat(height) - qrOrigin.y - CGFloat(qr.height),
                                    width: CGFloat(qr.width), height: CGFloat(qr.height)))
        return context.makeImage().map(TextRecognizer.ScanSource.init)
    }
}
