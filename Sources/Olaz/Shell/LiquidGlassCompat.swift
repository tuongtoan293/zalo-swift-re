import SwiftUI

// Lớp tương thích để chạy được trên macOS 15.
//
// Liquid Glass (`glassEffect`, `.buttonStyle(.glass)`, `GlassEffectContainer`, `safeAreaBar`, `ToolbarSpacer`,
// `scrollEdgeEffectStyle`, `sharedBackgroundVisibility`) chỉ có trong SDK macOS 26 (Swift 6.2 / Xcode 26 trở lên).
// Các view gọi qua đây: biên dịch bằng SDK mới và chạy trên macOS 26 thì dùng đúng API gốc; còn biên dịch bằng
// SDK 15 hoặc chạy trên macOS 15 thì thay bằng material / kiểu nút có sẵn.
// `compiler(>=6.2)` là dấu hiệu SDK 26: Xcode 26 là bản đầu tiên đi kèm Swift 6.2.

/// Thay cho `Glass`: `.regular`, `.tint(_:)`, `.interactive()`.
struct OlazGlass {
    var tint: Color?
    var isInteractive = false

    static var regular: OlazGlass { OlazGlass() }

    func tint(_ color: Color?) -> OlazGlass {
        var copy = self
        copy.tint = color
        return copy
    }

    func interactive(_ isEnabled: Bool = true) -> OlazGlass {
        var copy = self
        copy.isInteractive = isEnabled
        return copy
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    var native: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if isInteractive { glass = glass.interactive() }
        return glass
    }
    #endif
}

/// Thay cho `ScrollEdgeEffectStyle`.
enum OlazScrollEdgeStyle {
    case soft, hard

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    var native: ScrollEdgeEffectStyle {
        switch self {
        case .soft: .soft
        case .hard: .hard
        }
    }
    #endif
}

/// Bản macOS 15 của một mặt kính: material mỏng, viền sáng nhẹ, nhuộm màu nếu có.
private struct GlassFallback<S: Shape>: ViewModifier {
    let glass: OlazGlass
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.regularMaterial)
                    // Kính nhuộm vẫn để lộ material bên dưới, nên không phủ màu đặc.
                    if let tint = glass.tint { shape.fill(tint.opacity(0.75)) }
                }
            }
            .overlay { shape.stroke(.white.opacity(0.18), lineWidth: 0.5) }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

extension View {
    /// Thay cho `.glassEffect(_:in:)`.
    @ViewBuilder
    func olazGlass<S: Shape>(_ glass: OlazGlass = .regular, in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(glass.native, in: shape)
        } else {
            modifier(GlassFallback(glass: glass, shape: shape))
        }
        #else
        modifier(GlassFallback(glass: glass, shape: shape))
        #endif
    }

    /// Thay cho `.glassEffectID(_:in:)`. macOS 15 không có hiệu ứng hoà kính nên bỏ qua.
    @ViewBuilder
    func olazGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Thay cho `.buttonStyle(.glass)`.
    @ViewBuilder
    func olazGlassButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.bordered)
        #endif
    }

    /// Thay cho `.buttonStyle(.glassProminent)`.
    @ViewBuilder
    func olazGlassProminentButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    /// Thay cho `.safeAreaBar(edge:spacing:content:)`. macOS 15 dùng `safeAreaInset`, chỉ thiếu hiệu ứng mờ mép cuộn.
    @ViewBuilder
    func olazSafeAreaBar<V: View>(
        edge: VerticalEdge, spacing: CGFloat? = nil, @ViewBuilder content: () -> V
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: spacing, content: content)
        }
        #else
        safeAreaInset(edge: edge, spacing: spacing, content: content)
        #endif
    }

    /// Thay cho `.scrollEdgeEffectStyle(_:for:)`. macOS 15 không có nên bỏ qua.
    @ViewBuilder
    func olazScrollEdgeEffectStyle(_ style: OlazScrollEdgeStyle, for edges: Edge.Set) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(style.native, for: edges)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Thay cho `GlassEffectContainer`. macOS 15 chỉ xếp nội dung như cũ.
struct OlazGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Thay cho `ToolbarSpacer`. macOS 15 tự dồn nút về mép phải nên không cần khoảng trống, chỉ đặt một mục rỗng.
struct OlazToolbarSpacer: ToolbarContent {
    enum Sizing { case flexible, fixed }

    var sizing: Sizing
    var placement: ToolbarItemPlacement = .automatic

    init(_ sizing: Sizing, placement: ToolbarItemPlacement = .automatic) {
        self.sizing = sizing
        self.placement = placement
    }

    var body: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ToolbarSpacer(sizing == .flexible ? .flexible : .fixed, placement: placement)
        } else {
            ToolbarItem(placement: placement) { EmptyView() }
        }
        #else
        ToolbarItem(placement: placement) { EmptyView() }
        #endif
    }
}

// Gắn vào `ToolbarItem` chứ không vào `ToolbarContent`: SDK 26 có thể chỉ khai báo `sharedBackgroundVisibility`
// trên `CustomizableToolbarContent`, và bản gốc gọi nó đúng trên `ToolbarItem(placement:)`. Còn trong SDK 15.5,
// `ToolbarItem` chỉ là `CustomizableToolbarContent` khi `ID == String`, nên không gắn vào protocol đó được.
extension ToolbarItem {
    /// Thay cho `.sharedBackgroundVisibility(.hidden)`. macOS 15 không có nền chung quanh mục nên không cần ẩn.
    @ToolbarContentBuilder
    func olazHideSharedBackground() -> some ToolbarContent {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
