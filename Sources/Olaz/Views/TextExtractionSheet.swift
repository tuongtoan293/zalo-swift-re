import SwiftUI
import AppKit

// "Trích xuất chữ và mã QR": nhận dạng chữ và đọc mã QR / mã vạch trong ảnh của tin nhắn, một lượt Vision
// (TextRecognizer.swift). Chữ lọc theo "Chỉ số", "Chỉ chữ" hoặc "Cả số và chữ" (TextFilter.swift); nội dung mã giữ nguyên.
// Mở từ menu chuột phải của bong bóng ảnh (qua `engine.textExtraction`, trình bày ở `messageActionPresenter`) và từ nút
// trên thanh trên cùng của trình xem ảnh.
//
// Mở bảng KHÔNG tự nhận dạng: ảnh hiện vừa khung ở trên, người dùng kéo chọn một vùng (thả chuột là nhận dạng vùng đó) hoặc
// bấm "Nhận dạng cả ảnh". Vùng được cắt từ ảnh gốc (RegionMapping.swift) nên ảnh to không phải quét cả ảnh.

/// Bảng: ảnh xem trước để chọn vùng; dưới là các mã đọc được (sao chép, mở link http/https khi người dùng bấm) và chữ với
/// picker bộ lọc.
struct TextExtractionSheet: View {
    let request: TextExtractionRequest

    static let title = "Trích xuất chữ và mã QR"

    /// Nạp ảnh nguồn (một lần mỗi lần mở / thử lại).
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
        /// "Chặn chia sẻ" đang bật: không đọc chữ ra, giống "Copy tin nhắn" / "Copy hình ảnh".
        case blocked
    }

    /// Một lượt nhận dạng: cả ảnh (`region == nil`) hoặc một vùng (chuẩn hoá 0…1, gốc trên trái).
    /// `id` tăng mỗi lượt nên chọn lại đúng vùng cũ vẫn là lượt mới.
    struct ScanTarget: Equatable {
        let id: Int
        let region: CGRect?
    }

    enum ScanState: Equatable {
        case idle
        case scanning
        /// Chữ (chưa lọc, theo thứ tự đọc) và các mã đọc được.
        case done(TextRecognizer.ImageScan)
        case failed(String)
    }

    @Environment(ZaloEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var loadState = LoadState.loading
    @State private var attempt = 0
    @State private var source: TextRecognizer.ScanSource?
    @State private var preview: NSImage?
    /// Vùng đã chọn (chuẩn hoá), vẫn đúng khi đổi kích thước bảng.
    @State private var selection: CGRect?
    /// Khung đang kéo, toạ độ view.
    @State private var draft: CGRect?
    @State private var target: ScanTarget?
    @State private var scanCounter = 0
    @State private var scanState = ScanState.idle
    @State private var filter = TextFilter.alphanumeric
    @State private var copied = false
    /// Mã vừa được sao chép (nút của nó đổi thành dấu tích).
    @State private var copiedCode: ScannedCode.ID?

    private var scan: TextRecognizer.ImageScan? {
        if case .done(let scan) = scanState { return scan }
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
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 640, maxWidth: .infinity, minHeight: 600, idealHeight: 760, maxHeight: .infinity)
        .task(id: attempt) { await load() }
        .task(id: target) { await runScan() }
        .onChange(of: filter) { copied = false }
    }

    @ViewBuilder private var main: some View {
        switch loadState {
        case .loading:
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Đang tải hình ảnh…").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        case .blocked:
            ContentUnavailableView("Trò chuyện này đã bật Chặn chia sẻ", systemImage: "lock.shield",
                                   description: Text("Không thể trích xuất chữ từ ảnh trong trò chuyện này."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Không mở được hình ảnh", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Thử lại") { attempt += 1 }.olazGlassButtonStyle()
            }
        case .ready:
            if let preview, let source {
                VSplitView {
                    previewPane(preview, pixels: source.pixelSize)
                        .frame(minHeight: 220, idealHeight: 380, maxHeight: .infinity)
                    results
                        .frame(minHeight: 160, idealHeight: 280, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: Ảnh xem trước, chọn vùng

    private func previewPane(_ image: NSImage, pixels: CGSize) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let fitted = RegionMapping.fittedRect(imagePixels: pixels, in: geo.size)
                selectableImage(image, fitted: fitted)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            HStack(spacing: 8) {
                Text(previewHint(pixels: pixels))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selection != nil {
                    Button("Bỏ chọn", systemImage: "xmark") { clearSelection() }
                        .olazGlassButtonStyle()
                        .controlSize(.small)
                }
                Button(target == nil ? "Nhận dạng cả ảnh" : "Cả ảnh", systemImage: "text.viewfinder") { scanWholeImage() }
                    .olazGlassButtonStyle()
                    .controlSize(.small)
                    .disabled(target != nil && target?.region == nil && scanState != .idle)
            }
        }
        .padding(12)
    }

    private func selectableImage(_ image: NSImage, fitted: CGRect) -> some View {
        // Khung đang kéo (kẹp trong ảnh), không thì vùng đã chọn.
        let dragged = draft.map { $0.intersection(fitted) }.flatMap { $0.isNull ? nil : $0 }
        let shown = dragged ?? selection.map { RegionMapping.viewRect(normalized: $0, fitted: fitted) }
        return ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: fitted.width, height: fitted.height)
                .offset(x: fitted.minX, y: fitted.minY)
            if let shown {
                // Vùng ngoài khung tối đi: lấp cả ảnh trừ khung (even-odd).
                Path { path in
                    path.addRect(fitted)
                    path.addRect(shown)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                Path { $0.addRect(shown) }
                    .stroke(.tint, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .pointerStyle(.rectSelection)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in draft = RegionMapping.rect(from: value.startLocation, to: value.location) }
                .onEnded { value in
                    draft = nil
                    // Dưới 8×8 pt (sau khi kẹp vào ảnh) coi như bấm nhầm: giữ nguyên vùng và kết quả cũ.
                    guard let region = RegionMapping.normalized(selection: RegionMapping.rect(from: value.startLocation, to: value.location),
                                                                fitted: fitted) else { return }
                    selection = region
                    startScan(region: region)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Ảnh xem trước")
        .accessibilityHint("Kéo để chọn vùng cần trích xuất")
    }

    private func previewHint(pixels: CGSize) -> String {
        if let selection, let rect = RegionMapping.pixelRect(normalized: selection, imagePixels: pixels) {
            return "Vùng \(Int(rect.width))×\(Int(rect.height)) px · kéo lại để chọn vùng khác"
        }
        if target != nil { return "Cả ảnh \(Int(pixels.width))×\(Int(pixels.height)) px · kéo để chọn một vùng" }
        return "Kéo để chọn vùng cần trích xuất"
    }

    // MARK: Kết quả

    @ViewBuilder private var results: some View {
        switch scanState {
        case .idle:
            Text("Chọn một vùng trên ảnh, hoặc bấm “Nhận dạng cả ảnh”.")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .scanning:
            VStack(spacing: 10) {
                ProgressView().controlSize(.regular)
                Text("Đang nhận dạng chữ và mã…").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Không trích xuất được chữ", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Thử lại") { startScan(region: target?.region) }.olazGlassButtonStyle()
            }
        case .done:
            if lines.isEmpty && codes.isEmpty {
                ContentUnavailableView("Không tìm thấy chữ", systemImage: "text.viewfinder",
                                       description: Text(selection == nil ? "Ảnh này không có chữ hay mã QR nào nhận dạng được."
                                                                          : "Vùng đã chọn không có chữ hay mã QR nào. Hãy thử chọn vùng khác."))
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

    /// Bộ lọc đang chọn không giữ lại gì (có chữ, nếu không thì mục này đã không hiện).
    private var emptyHint: String {
        switch filter {
        case .digits: "Có chữ nhưng không có số nào. Hãy thử bộ lọc khác."
        case .letters: "Có chữ số nhưng không có chữ cái nào. Hãy thử bộ lọc khác."
        case .alphanumeric: "Chỉ có ký hiệu, không có chữ hay số."
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

    /// Nạp ảnh qua `photoData` (cùng đường "Copy hình ảnh") và giải mã ở độ phân giải gốc, ngoài main. Không nhận dạng.
    private func load() async {
        loadState = .loading
        source = nil
        preview = nil
        clearSelection()
        if await engine.isShareBlocked(request.conversationId) {
            loadState = .blocked
            return
        }
        guard let data = await engine.photoData(conversationId: request.conversationId, messageId: request.messageId,
                                                url: request.url, encrypted: request.encrypted) else {
            guard !Task.isCancelled else { return }
            loadState = .failed("Không tải được hình ảnh. Hãy thử lại.")
            return
        }
        do {
            let decoded = try await TextRecognizer.decode(imageData: data)
            guard !Task.isCancelled else { return }
            source = decoded
            // `size: .zero`: NSImage lấy kích thước pixel của CGImage.
            preview = NSImage(cgImage: decoded.cgImage, size: .zero)
            loadState = .ready
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed("Không đọc được hình ảnh này.")
        }
    }

    private func startScan(region: CGRect?) {
        scanCounter += 1
        // Đổi `target` làm `.task(id:)` huỷ lượt đang chạy và bắt đầu lượt mới.
        target = ScanTarget(id: scanCounter, region: region)
    }

    private func scanWholeImage() {
        selection = nil
        startScan(region: nil)
    }

    private func clearSelection() {
        selection = nil
        draft = nil
        target = nil
        scanState = .idle
        copied = false
        copiedCode = nil
    }

    /// Chạy lượt `target`. Lượt bị thay (kéo vùng khác, bỏ chọn, đóng bảng) bị huỷ qua `.task(id:)`; Vision không dừng giữa
    /// chừng được nhưng kết quả của lượt cũ bị bỏ, không ghi đè kết quả mới.
    private func runScan() async {
        guard let target, let source else {
            scanState = .idle
            return
        }
        scanState = .scanning
        copied = false
        copiedCode = nil
        var pixels: CGRect?
        if let region = target.region {
            guard let rect = RegionMapping.pixelRect(normalized: region, imagePixels: source.pixelSize) else {
                scanState = .done(TextRecognizer.ImageScan(lines: [], codes: []))
                return
            }
            pixels = rect
        }
        let start = Date()
        do {
            let result = try await TextRecognizer.scan(source, region: pixels)
            guard !Task.isCancelled, self.target == target else { return }
            // Chỉ ghi số đo và loại mã, không ghi nội dung chữ hay nội dung mã.
            let area = pixels.map { "vùng \(Int($0.width))x\(Int($0.height))" } ?? "cả ảnh \(source.cgImage.width)x\(source.cgImage.height)"
            let kinds = result.codes.map(\.kindName).joined(separator: ",")
            EngineLog.shared.write("ocr \(area) → \(result.lines.count) dòng, \(result.codes.count) mã [\(kinds)], "
                                   + "\(String(format: "%.2f", Date().timeIntervalSince(start))) s")
            scanState = .done(result)
        } catch {
            guard !Task.isCancelled, self.target == target else { return }
            EngineLog.shared.write("ocr → lỗi \(error)")
            scanState = .failed("Không nhận dạng được hình ảnh này.")
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
