import Testing
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
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
            try TextRecognizer.recognizeLines(imageData: Data("không phải ảnh".utf8))
        }
    }

    // MARK: Nhận dạng thật (Vision)

    /// Vẽ chữ đen trên nền trắng, mã hoá PNG rồi đi đúng đường của app: byte → giải mã → Vision → bộ lọc.
    @Test func recognizesDrawnTextAndDigitsFilterFindsThePhoneNumber() async throws {
        let data = try #require(Self.png(lines: ["Mã 0901234567 Hà Nội"]))
        let start = Date()
        let lines = try await TextRecognizer.recognize(imageData: data)
        let elapsed = Date().timeIntervalSince(start)
        print("OCR: \(lines) \(lines.count) dòng trong \(String(format: "%.3f", elapsed)) s, ngôn ngữ hỗ trợ: \(TextRecognizer.supportedLanguages())")
        #expect(TextFilter.digits.apply(lines: lines) == "0901234567")
        // Có "vi-VT" thì dấu tiếng Việt phải đọc đúng.
        if TextRecognizer.supportedLanguages().contains("vi-VT") {
            #expect(TextFilter.letters.apply(lines: lines) == "Mã Hà Nội")
        }
    }

    @Test func blankImageHasNoText() async throws {
        let data = try #require(Self.png(lines: []))
        let lines = try await TextRecognizer.recognize(imageData: data)
        #expect(lines.isEmpty)
    }

    /// PNG 1200×(160 + 120/dòng), chữ Helvetica 56 pt.
    static func png(lines: [String]) -> Data? {
        let width = 1200, height = 160 + 120 * max(lines.count, 1)
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
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
