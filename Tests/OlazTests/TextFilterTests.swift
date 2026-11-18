import Testing
@testable import Olaz

@Suite struct TextFilterTests {
    // MARK: Chỉ số

    @Test func digitsDropsLabelAndKeepsGroups() {
        #expect(TextFilter.digits.apply("SĐT: 0901 234 567") == "0901 234 567")
    }

    @Test func digitsCollapsesSpacesAndDropsEmptyLines() {
        let text = "Hóa đơn\n  Tổng:   1.500.000đ  \n\nMã   KH 42\nCảm ơn!"
        #expect(TextFilter.digits.apply(text) == "1 500 000\n42")
    }

    @Test func digitsSeparatesWhatPunctuationSeparated() {
        #expect(TextFilter.digits.apply("Ngày 12/05/2024") == "12 05 2024")
    }

    @Test func digitsKeepsOtherDecimalScriptsButNotFractionsOrSuperscripts() {
        #expect(TextFilter.digits.apply("٣٤ ５ ½ x² Ⅻ") == "٣٤ ５")
    }

    @Test func digitsOfTextWithoutDigitsIsEmpty() {
        #expect(TextFilter.digits.apply("Không có số nào") == "")
    }

    // MARK: Chỉ chữ

    @Test func lettersKeepsVietnameseDiacritics() {
        #expect(TextFilter.letters.apply("Mã 0901234567 Hà Nội, Việt Nam!") == "Mã Hà Nội Việt Nam")
    }

    @Test func lettersKeepsDecomposedVietnamese() {
        // "ệ" viết tách: e + dấu mũ + dấu nặng, vẫn là một Character chữ cái.
        let decomposed = "Vi\u{0065}\u{0302}\u{0323}t"
        #expect(TextFilter.letters.apply(decomposed) == decomposed)
    }

    @Test func lettersSplitsWordsAtRemovedDigits() {
        #expect(TextFilter.letters.apply("abc123def") == "abc def")
    }

    // MARK: Cả số và chữ

    @Test func alphanumericDropsPunctuationAndSymbols() {
        #expect(TextFilter.alphanumeric.apply("Giá: 50.000₫ (giảm 10%) — còn #3") == "Giá 50 000 giảm 10 còn 3")
    }

    @Test func alphanumericKeepsLineStructure() {
        #expect(TextFilter.alphanumeric.apply(lines: ["  Mã 0901234567 ", "---", "Hà Nội"]) == "Mã 0901234567\nHà Nội")
    }

    @Test func crlfAndUnicodeLineBreaksSplitLines() {
        #expect(TextFilter.alphanumeric.apply("a\r\nb\u{2028}c") == "a\nb\nc")
    }

    // MARK: Picker

    @Test func titlesAreVietnameseInPickerOrder() {
        #expect(TextFilter.allCases.map(\.title) == ["Chỉ số", "Chỉ chữ", "Cả số và chữ"])
    }
}
