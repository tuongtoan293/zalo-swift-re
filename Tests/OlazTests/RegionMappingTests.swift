import Testing
import CoreGraphics
@testable import Olaz

@Suite struct RegionMappingTests {
    // MARK: Aspect fit

    @Test func wideImageIsLetterboxedTopAndBottom() {
        // 4000×1000 trong 800×600: rộng vừa khít, cao 200, căn giữa dọc.
        let fitted = RegionMapping.fittedRect(imagePixels: CGSize(width: 4000, height: 1000), in: CGSize(width: 800, height: 600))
        #expect(fitted == CGRect(x: 0, y: 200, width: 800, height: 200))
    }

    @Test func tallImageIsPillarboxedLeftAndRight() {
        // 1000×3000 trong 800×600: cao vừa khít, rộng 200, căn giữa ngang.
        let fitted = RegionMapping.fittedRect(imagePixels: CGSize(width: 1000, height: 3000), in: CGSize(width: 800, height: 600))
        #expect(fitted == CGRect(x: 300, y: 0, width: 200, height: 600))
    }

    @Test func selectionInLandscapeMapsThroughTheVerticalOffset() {
        // Ảnh 4000×1000 ở y 200…400 của view: điểm (100, 250) là pixel (500, 250); 5 px ảnh mỗi điểm.
        let pixels = RegionMapping.pixelRect(selection: CGRect(x: 100, y: 250, width: 200, height: 100),
                                             viewSize: CGSize(width: 800, height: 600), imagePixels: CGSize(width: 4000, height: 1000))
        #expect(pixels == CGRect(x: 500, y: 250, width: 1000, height: 500))
    }

    @Test func selectionInPortraitMapsThroughTheHorizontalOffset() {
        let pixels = RegionMapping.pixelRect(selection: CGRect(x: 350, y: 60, width: 100, height: 120),
                                             viewSize: CGSize(width: 800, height: 600), imagePixels: CGSize(width: 1000, height: 3000))
        #expect(pixels == CGRect(x: 250, y: 300, width: 500, height: 600))
    }

    @Test func yAxisStaysTopLeftAsCGImageCroppingExpects() {
        // Vùng sát mép trên của view phải ra pixel hàng 0 (không lật trục y).
        let pixels = RegionMapping.pixelRect(selection: CGRect(x: 0, y: 0, width: 50, height: 50),
                                             viewSize: CGSize(width: 400, height: 300), imagePixels: CGSize(width: 800, height: 600))
        #expect(pixels == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    // MARK: Retina

    @Test func retinaImageUsesRealPixelsNotPoints() {
        // Ảnh chụp màn hình retina 2880×1800 hiện trong 1440×900 điểm: 2 pixel mỗi điểm, không phụ thuộc backingScaleFactor.
        let pixels = RegionMapping.pixelRect(selection: CGRect(x: 10, y: 20, width: 30, height: 40),
                                             viewSize: CGSize(width: 1440, height: 900), imagePixels: CGSize(width: 2880, height: 1800))
        #expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 80))
    }

    // MARK: Kẹp, vùng nhỏ

    @Test func selectionSpillingOutOfTheImageIsClamped() {
        // Ảnh 4000×1000 ở y 200…400: kéo từ (-50, 100) tới (300, 500) chỉ còn x 0…300, y 200…400.
        let start = CGPoint(x: 300, y: 500), end = CGPoint(x: -50, y: 100)
        let pixels = RegionMapping.pixelRect(selection: RegionMapping.rect(from: start, to: end),
                                             viewSize: CGSize(width: 800, height: 600), imagePixels: CGSize(width: 4000, height: 1000))
        #expect(pixels == CGRect(x: 0, y: 0, width: 1500, height: 1000))
    }

    @Test func selectionEntirelyOnTheLetterboxIsIgnored() {
        #expect(RegionMapping.pixelRect(selection: CGRect(x: 100, y: 20, width: 200, height: 150),
                                        viewSize: CGSize(width: 800, height: 600), imagePixels: CGSize(width: 4000, height: 1000)) == nil)
    }

    @Test func tinySelectionIsIgnored() {
        let fitted = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(RegionMapping.normalized(selection: CGRect(x: 10, y: 10, width: 7.9, height: 50), fitted: fitted) == nil)
        #expect(RegionMapping.normalized(selection: CGRect(x: 10, y: 10, width: 50, height: 7), fitted: fitted) == nil)
        #expect(RegionMapping.normalized(selection: CGRect(x: 10, y: 10, width: 8, height: 8), fitted: fitted) != nil)
        // 8×8 nhưng phần nằm trên ảnh chỉ còn 4 điểm.
        #expect(RegionMapping.normalized(selection: CGRect(x: -4, y: 10, width: 8, height: 8), fitted: fitted) == nil)
    }

    @Test func normalizedSurvivesAResizeOfThePreview() {
        let pixels = CGSize(width: 3000, height: 2000)
        let small = RegionMapping.fittedRect(imagePixels: pixels, in: CGSize(width: 300, height: 300))
        let normalized = try! #require(RegionMapping.normalized(selection: CGRect(x: 30, y: 80, width: 150, height: 60), fitted: small))
        let large = RegionMapping.fittedRect(imagePixels: pixels, in: CGSize(width: 900, height: 900))
        #expect(RegionMapping.viewRect(normalized: normalized, fitted: large) == CGRect(x: 90, y: 240, width: 450, height: 180))
        #expect(RegionMapping.pixelRect(normalized: normalized, imagePixels: pixels) == CGRect(x: 300, y: 300, width: 1500, height: 600))
    }
}
