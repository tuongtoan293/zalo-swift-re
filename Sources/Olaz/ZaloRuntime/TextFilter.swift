import Foundation

/// Bộ lọc của "Trích xuất chữ": giữ lại phần nào của văn bản nhận dạng được từ ảnh.
///
/// Hàm thuần, không phụ thuộc giao diện hay Vision. Quy tắc chung cho cả ba bộ lọc:
/// * Ký tự bị loại được thay bằng một khoảng trắng, để hai cụm hai bên không dính vào nhau
///   ("12/05/2024" → "12 05 2024" chứ không thành "12052024").
/// * Giữ cấu trúc dòng; trong mỗi dòng gộp các khoảng trắng liền nhau thành một và cắt hai đầu; bỏ dòng rỗng.
enum TextFilter: String, CaseIterable, Identifiable, Sendable {
    /// Chỉ chữ số thập phân Unicode (general category Nd).
    case digits
    /// Chỉ chữ cái (`Character.isLetter`), kể cả tiếng Việt có dấu.
    case letters
    /// Chữ cái và chữ số; bỏ dấu câu, ký hiệu.
    case alphanumeric

    var id: String { rawValue }

    /// Tên trên picker.
    var title: String {
        switch self {
        case .digits: "Chỉ số"
        case .letters: "Chỉ chữ"
        case .alphanumeric: "Cả số và chữ"
        }
    }

    /// Lọc `text` (các dòng cách nhau bởi xuống dòng).
    func apply(_ text: String) -> String {
        apply(lines: text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init))
    }

    /// Lọc từng dòng rồi nối lại bằng "\n"; dòng không còn gì sau khi lọc thì bỏ.
    func apply(lines: [String]) -> String {
        lines.compactMap(filterLine).joined(separator: "\n")
    }

    private func filterLine(_ line: String) -> String? {
        var words: [String] = []
        var current = ""
        for character in line {
            if keeps(character) {
                current.append(character)
            } else if !current.isEmpty {
                // Khoảng trắng hay ký tự bị loại đều là chỗ ngắt.
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private func keeps(_ character: Character) -> Bool {
        switch self {
        case .digits: Self.isDecimalDigit(character)
        case .letters: character.isLetter
        case .alphanumeric: character.isLetter || Self.isDecimalDigit(character)
        }
    }

    /// Chữ số thập phân Unicode: mọi scalar thuộc Nd ("0"–"9", "٣", "５"…). Không tính "½", "²", "Ⅻ".
    static func isDecimalDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .decimalNumber }
    }
}
