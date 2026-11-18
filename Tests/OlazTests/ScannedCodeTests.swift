import Testing
@testable import Olaz

@Suite struct ScannedCodeTests {
    // MARK: Nút "Mở"

    @Test func httpAndHttpsAreOpenable() {
        #expect(ScannedCode.openableURL("https://zalo.me/g/abc")?.absoluteString == "https://zalo.me/g/abc")
        #expect(ScannedCode.openableURL("http://example.com") != nil)
        #expect(ScannedCode.openableURL("  HTTPS://Zalo.me/x \n") != nil)
    }

    @Test func otherSchemesAndPlainTextAreNotOpenable() {
        for payload in ["javascript:alert(1)", "JavaScript://zalo.me/%0aalert(1)", "file:///etc/passwd", "zalo://chat?uid=1",
                        "data:text/html,<b>x</b>", "mailto:a@b.c", "tel:0901234567", "zalo.me/test", "Mã 0901234567",
                        "https://", "https:///path", "https://zalo.me/a b", "https://zalo.me/\u{202E}gpj", ""] {
            #expect(ScannedCode.openableURL(payload) == nil, "\(payload)")
        }
    }

    @Test func hostShownIsTheRealHost() {
        #expect(ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: "https://Zalo.me/test-olaz").openableHost == "zalo.me")
        #expect(ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: "https://zalo.me@evil.example/login").openableHost == "evil.example")
        #expect(ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: "zalo://x").openableHost == nil)
    }

    // MARK: Khử trùng lặp, tên loại

    @Test func uniqueDropsRepeatsOfTheSameKindAndPayloadOnly() {
        let qr = ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: "A")
        let aztec = ScannedCode(symbology: "VNBarcodeSymbologyAztec", payload: "A")
        let qrB = ScannedCode(symbology: "VNBarcodeSymbologyQR", payload: "B")
        #expect(ScannedCode.unique([qr, aztec, qr, qrB, aztec]) == [qr, aztec, qrB])
    }

    @Test func kindNames() {
        #expect(ScannedCode.kindName(symbology: "VNBarcodeSymbologyQR") == "Mã QR")
        #expect(ScannedCode.kindName(symbology: "VNBarcodeSymbologyEAN13") == "EAN-13")
        #expect(ScannedCode.kindName(symbology: "VNBarcodeSymbologyCode128") == "Code 128")
        #expect(ScannedCode.kindName(symbology: "VNBarcodeSymbologyDataMatrix") == "DataMatrix")
        #expect(ScannedCode.kindName(symbology: "VNBarcodeSymbologyNewThing") == "NewThing")
    }
}
