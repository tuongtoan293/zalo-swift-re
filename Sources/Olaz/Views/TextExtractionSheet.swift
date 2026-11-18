import SwiftUI
import AppKit

// "Trích xuất chữ và mã QR": nhận dạng chữ và đọc mã QR / mã vạch trong ảnh của tin nhắn, một lượt Vision
// (TextRecognizer.swift). Chữ lọc theo "Chỉ số", "Chỉ chữ" hoặc "Cả số và chữ" (TextFilter.swift); nội dung mã giữ nguyên.
// Mở từ menu chuột phải của bong bóng ảnh (qua `engine.textExtraction`, trình bày ở `messageActionPresenter`) và từ nút
// trên thanh trên cùng của trình xem ảnh.

/// Bảng kết quả: các mã đọc được (sao chép, mở link http/https khi người dùng bấm), rồi chữ với picker bộ lọc và "Sao chép".
struct TextExtractionSheet: View {
    let request: TextExtractionRequest

    static let title = "Trích xuất chữ và mã QR"

    enum Phase: Equatable {
        case recognizing
        /// Chữ (chưa lọc, theo thứ tự đọc) và các mã đọc được.
        case done(TextRecognizer.ImageScan)
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
    /// Mã vừa được sao chép (nút của nó đổi thành dấu tích).
    @State private var copiedCode: ScannedCode.ID?

    private var scan: TextRecognizer.ImageScan? {
        if case .done(let scan) = phase { return scan }
        return nil
    }

    private var lines: [String] { scan?.lines ?? [] }
    private var codes: [ScannedCode] { scan?.codes ?? [] }
    /// Bộ lọc chỉ áp lên chữ, không bao giờ lên nội dung mã.
    private var output: String { filter.apply(lines: lines) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: Self.title) { dismiss() }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 480, height: 500)
        .task(id: attempt) { await recognize() }
        .onChange(of: filter) { copied = false }
    }

    // MARK: Nội dung

    @ViewBuilder private var content: some View {
        switch phase {
        case .recognizing:
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Đang nhận dạng chữ và mã…").font(.system(size: 12.5)).foregroundStyle(.secondary)
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
            if lines.isEmpty && codes.isEmpty {
                ContentUnavailableView("Không tìm thấy chữ", systemImage: "text.viewfinder",
                                       description: Text("Ảnh này không có chữ hay mã QR nào nhận dạng được."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !codes.isEmpty { codesSection }
                        if !lines.isEmpty { textSection }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Mã QR / mã vạch

    private var codesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Mã QR / mã vạch")
            ForEach(codes) { codeRow($0) }
        }
    }

    private func codeRow(_ code: ScannedCode) -> some View {
        let url = code.openableURL
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(code.kindName, systemImage: code.symbology.hasSuffix("QR") ? "qrcode" : "barcode")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                Button(copiedCode == code.id ? "Đã sao chép" : "Sao chép",
                       systemImage: copiedCode == code.id ? "checkmark" : "doc.on.doc") { copy(code) }
                    .olazGlassButtonStyle()
                    .controlSize(.small)
                if let url, let host = code.openableHost {
                    // Không bao giờ tự mở: chỉ khi người dùng bấm, và host thật hiện ngay trên nút.
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Mở \(host)", systemImage: "arrow.up.forward.app")
                    }
                    .olazGlassButtonStyle()
                    .controlSize(.small)
                    .help("Mở \(url.absoluteString) trong trình duyệt")
                }
            }
            Text(code.payload)
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let host = code.openableHost {
                Label("Liên kết tới \(host). Chỉ mở nếu bạn tin người gửi.", systemImage: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
        .accessibilityElement(children: .contain)
    }

    // MARK: Chữ

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Chữ")
            Picker("Bộ lọc", selection: $filter) {
                ForEach(TextFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if output.isEmpty {
                Text(emptyHint)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Text(output)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Bộ lọc đang chọn không giữ lại gì (ảnh có chữ, nếu không thì mục này đã không hiện).
    private var emptyHint: String {
        switch filter {
        case .digits: "Ảnh có chữ nhưng không có số nào. Hãy thử bộ lọc khác."
        case .letters: "Ảnh có chữ số nhưng không có chữ cái nào. Hãy thử bộ lọc khác."
        case .alphanumeric: "Ảnh chỉ có ký hiệu, không có chữ hay số."
        }
    }

    private var footer: some View {
        HStack {
            Text(summary).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
            Button("Đóng") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(copied ? "Đã sao chép" : "Sao chép chữ", systemImage: copied ? "checkmark" : "doc.on.doc") { copy() }
                .olazGlassProminentButtonStyle()
                .disabled(output.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var summary: String {
        var parts: [String] = []
        if !codes.isEmpty { parts.append("\(codes.count) mã") }
        if !output.isEmpty {
            parts.append("\(output.split(separator: "\n").count) dòng")
            parts.append("\(output.count) ký tự")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Hành động

    private func recognize() async {
        phase = .recognizing
        copied = false
        copiedCode = nil
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
            let scan = try await TextRecognizer.scan(imageData: data)
            guard !Task.isCancelled else { return }
            // Chỉ ghi số đo và loại mã, không ghi nội dung chữ hay nội dung mã.
            let kinds = scan.codes.map(\.kindName).joined(separator: ",")
            EngineLog.shared.write("ocr \(data.count)B → \(scan.lines.count) dòng, \(scan.codes.count) mã [\(kinds)], "
                                   + "\(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            phase = .done(scan)
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

    private func copy(_ code: ScannedCode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.payload, forType: .string)
        copiedCode = code.id
    }
}
