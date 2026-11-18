import Testing
@testable import Olaz

@Suite struct TextExtractionModeTests {
    @Test func onlyWholeImageScansOnOpen() {
        #expect(TextExtractionMode.wholeImage.scansOnOpen)
        #expect(!TextExtractionMode.region.scansOnOpen)
    }

    @Test func menuOrderTitlesAndSymbols() {
        #expect(TextExtractionMode.allCases == [.wholeImage, .region])
        #expect(TextExtractionMode.allCases.map(\.menuTitle) == ["Trích xuất cả ảnh", "Trích xuất vùng chọn"])
        #expect(TextExtractionMode.allCases.map(\.symbol) == ["text.viewfinder", "crop"])
    }

    @Test func viewerHelpTellsTheTwoButtonsApart() {
        #expect(TextExtractionMode.wholeImage.help != TextExtractionMode.region.help)
        #expect(TextExtractionMode.region.help.contains("vùng"))
    }

    @Test func requestDefaultsToWholeImage() {
        let request = TextExtractionRequest(conversationId: "c", messageId: "m", url: nil, encrypted: false)
        #expect(request.mode == .wholeImage)
    }
}
