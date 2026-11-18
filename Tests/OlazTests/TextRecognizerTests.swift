import Testing
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
@testable import Olaz

@Suite struct TextRecognizerTests {
    // MARK: Ngôn ngữ

    @Test func languagesKeepPreferredOrderAndOnlySupportedOnes() {
        #expect(TextRecognizer.languages(supported: ["en-US", "fr-FR", "vi-VT"]) == ["vi-VT", "en-US"])
        #expect(TextRecognizer.languages(supported: ["en-US"]) == ["en-US"])
        #expect(TextRecognizer.languages(supported: []) == [])
    }

    // MARK: Thứ tự đọc

    @Test func readingOrderGoesTopDownAndMergesARow() {
        let pieces = [
            TextRecognizer.TextPiece(text: "150.000", box: CGRect(x: 0.7, y: 0.50, width: 0.2, height: 0.05)),
            TextRecognizer.TextPiece(text: "Hóa đơn", box: CGRect(x: 0.1, y: 0.80, width: 0.3, height: 0.06)),
            TextRecognizer.TextPiece(text: "Tổng", box: CGRect(x: 0.1, y: 0.51, width: 0.2, height: 0.05)),
            TextRecognizer.TextPiece(text: "Cảm ơn", box: CGRect(x: 0.1, y: 0.20, width: 0.2, height: 0.05)),
        ]
        #expect(TextRecognizer.readingOrder(pieces) == ["Hóa đơn", "Tổng 150.000", "Cảm ơn"])
    }

    @Test func undecodableBytesThrow() {
        #expect(throws: TextRecognizer.Failure.undecodable) {
            try TextRecognizer.scanSync(imageData: Data("không phải ảnh".utf8))
        }
    }

    // MARK: Nhận dạng thật (Vision)

    /// Vẽ chữ đen trên nền trắng, mã hoá PNG rồi đi đúng đường của app: byte → giải mã → Vision → bộ lọc.
    @Test func recognizesDrawnTextAndDigitsFilterFindsThePhoneNumber() async throws {
        let data = try #require(Self.png(lines: ["Mã 0901234567 Hà Nội"]))
        let start = Date()
        let scan = try await TextRecognizer.scan(imageData: data)
        let elapsed = Date().timeIntervalSince(start)
        let lines = scan.lines
        #expect(scan.codes.isEmpty)
        print("OCR: \(lines) \(lines.count) dòng trong \(String(format: "%.3f", elapsed)) s, ngôn ngữ hỗ trợ: \(TextRecognizer.supportedLanguages())")
        #expect(TextFilter.digits.apply(lines: lines) == "0901234567")
        // Có "vi-VT" thì dấu tiếng Việt phải đọc đúng.
        if TextRecognizer.supportedLanguages().contains("vi-VT") {
            #expect(TextFilter.letters.apply(lines: lines) == "Mã Hà Nội")
        }
    }

    @Test func blankImageHasNoText() async throws {
        let data = try #require(Self.png(lines: []))
        let scan = try await TextRecognizer.scan(imageData: data)
        #expect(scan == TextRecognizer.ImageScan(lines: [], codes: []))
    }

    /// QR (CIFilter.qrCodeGenerator) đặt cạnh một dòng chữ: một lượt quét phải ra cả mã lẫn chữ.
    @Test func scansQRCodeAndTextInOnePass() async throws {
        let payload = "https://zalo.me/test-olaz"
        let data = try #require(Self.png(lines: ["Mã 0901234567 Hà Nội"], qr: payload))
        let start = Date()
        let scan = try await TextRecognizer.scan(imageData: data)
        let elapsed = Date().timeIntervalSince(start)
        print("QR+OCR: \(scan.codes.map(\.kindName)) \(scan.lines) trong \(String(format: "%.3f", elapsed)) s")
        #expect(scan.codes == [ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: payload)])
        #expect(scan.codes.first?.kindName == "Mã QR")
        #expect(scan.codes.first?.openableHost == "zalo.me")
        #expect(TextFilter.digits.apply(lines: scan.lines) == "0901234567")
    }

    /// PNG (1200 + cột QR)×(160 + 120/dòng, đủ cao cho QR), chữ Helvetica 56 pt; QR mỗi module 10 px, đặt bên phải.
    static func png(lines: [String], qr: String? = nil) -> Data? {
        let code = qr.flatMap(qrImage)
        let qrSide = code.map { max($0.width, $0.height) } ?? 0
        let width = 1200 + (code == nil ? 0 : qrSide + 80)
        let height = max(160 + 120 * max(lines.count, 1), qrSide + 80)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        for (index, text) in lines.enumerated() {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): black,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 60, y: CGFloat(height - 120 - 120 * index))
            CTLineDraw(line, context)
        }
        if let code {
            context.draw(code, in: CGRect(x: 1200, y: (height - qrSide) / 2, width: code.width, height: code.height))
        }
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Mã QR đen trắng, mỗi module 10 px.
    static func qrImage(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
