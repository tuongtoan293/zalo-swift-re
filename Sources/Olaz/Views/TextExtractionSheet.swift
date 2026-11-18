import SwiftUI
import AppKit

// "Trích xuất chữ": nhận dạng chữ trong ảnh của tin nhắn (Vision, TextRecognizer.swift) rồi lọc theo "Chỉ số", "Chỉ chữ" hoặc
// "Cả số và chữ" (TextFilter.swift). Mở từ menu chuột phải của bong bóng ảnh (qua `engine.textExtraction`, trình bày ở
// `messageActionPresenter`) và từ nút trên thanh trên cùng của trình xem ảnh.

/// Bảng kết quả: picker bộ lọc, văn bản chọn được, "Sao chép".
struct TextExtractionSheet: View {
    let request: TextExtractionRequest

    enum Phase: Equatable {
        case recognizing
        /// Các dòng nhận dạng được (chưa lọc), theo thứ tự đọc.
        case done([String])
        case failed(String)
        /// "Chặn chia sẻ" đang bật: không đọc chữ ra, giống "Copy tin nhắn" / "Copy hình ảnh".
        case blocked
    }

    @Environment(ZaloEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.recognizing
    @State private var filter = TextFilter.alphanumeric
    @State private var attempt = 0
    @State private var copied = false

    private var lines: [String] {
        if case .done(let lines) = phase { return lines }
        return []
    }

    private var output: String { filter.apply(lines: lines) }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Trích xuất chữ") { dismiss() }
            Divider()
            Picker("Bộ lọc", selection: $filter) {
                ForEach(TextFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16).padding(.vertical, 12)
            .disabled(!isDone)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 460, height: 440)
        .task(id: attempt) { await recognize() }
        .onChange(of: filter) { copied = false }
    }

    // MARK: Nội dung

    @ViewBuilder private var content: some View {
        switch phase {
        case .recognizing:
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Đang nhận dạng chữ…").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        case .blocked:
            ContentUnavailableView("Trò chuyện này đã bật Chặn chia sẻ", systemImage: "lock.shield",
                                   description: Text("Không thể trích xuất chữ từ ảnh trong trò chuyện này."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Không trích xuất được chữ", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Thử lại") { attempt += 1 }.olazGlassButtonStyle()
            }
        case .done:
            if output.isEmpty {
                ContentUnavailableView("Không tìm thấy chữ", systemImage: "text.viewfinder", description: Text(emptyHint))
            } else {
                ScrollView {
                    Text(output)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
        }
    }

    /// Ảnh không có chữ nào, hay chỉ là bộ lọc đang chọn không giữ lại gì.
    private var emptyHint: String {
        guard !lines.isEmpty else { return "Ảnh này không có chữ nào nhận dạng được." }
        switch filter {
        case .digits: return "Ảnh có chữ nhưng không có số nào. Hãy thử bộ lọc khác."
        case .letters: return "Ảnh có chữ số nhưng không có chữ cái nào. Hãy thử bộ lọc khác."
        case .alphanumeric: return "Ảnh chỉ có ký hiệu, không có chữ hay số."
        }
    }

    private var footer: some View {
        HStack {
            Text(summary).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
            Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(copied ? "Đã sao chép" : "Sao chép", systemImage: copied ? "checkmark" : "doc.on.doc") { copy() }
                .olazGlassProminentButtonStyle()
                .disabled(output.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var summary: String {
        guard !output.isEmpty else { return "" }
        let count = output.split(separator: "\n").count
        return "\(count) dòng · \(output.count) ký tự"
    }

    // MARK: Hành động

    private func recognize() async {
        phase = .recognizing
        copied = false
        if await engine.isShareBlocked(request.conversationId) {
            phase = .blocked
            return
        }
        guard let data = await engine.photoData(conversationId: request.conversationId, messageId: request.messageId,
                                                url: request.url, encrypted: request.encrypted) else {
            guard !Task.isCancelled else { return }
            phase = .failed("Không tải được hình ảnh. Hãy thử lại.")
            return
        }
        let start = Date()
        do {
            let lines = try await TextRecognizer.recognize(imageData: data)
            guard !Task.isCancelled else { return }
            // Chỉ ghi số đo, không ghi nội dung chữ.
            EngineLog.shared.write("ocr \(data.count)B → \(lines.count) dòng, \(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            phase = .done(lines)
        } catch {
            guard !Task.isCancelled else { return }
            EngineLog.shared.write("ocr \(data.count)B → lỗi \(error)")
            phase = .failed("Không đọc được hình ảnh này.")
        }
    }

    private func copy() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copied = true
    }
}
