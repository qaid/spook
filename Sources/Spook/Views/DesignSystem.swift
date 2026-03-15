import SwiftUI

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
    static let huge: CGFloat = 32
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 10
    static let panel: CGFloat = 12
}

// MARK: - Typography

enum SpookFont {
    static let caption3: Font = .system(size: 9)
    static let caption2: Font = .system(size: 10)
    static let caption: Font = .system(size: 11)
    static let body: Font = .system(size: 13)
    static let bodyMedium: Font = .system(size: 13, weight: .medium)
    static let headline: Font = .system(size: 15, weight: .semibold)
    static let title: Font = .system(size: 22, weight: .semibold)

    static let monoCaption: Font = .system(size: 11, design: .monospaced)
    static let monoBody: Font = .system(size: 13, design: .monospaced)
}

// MARK: - Colors

extension Color {
    static let spookDownload = Color.blue
    static let spookUpload = Color.green
    static let spookSurface = Color(nsColor: .windowBackgroundColor)
    static let spookSurfaceElevated = Color(nsColor: .controlBackgroundColor)
    static let spookTextBackground = Color(nsColor: .textBackgroundColor)
    static let spookBorder = Color.gray.opacity(0.15)
    static let spookTextPrimary = Color.primary
    static let spookTextSecondary = Color.secondary
    static let spookTextTertiary = Color.secondary.opacity(0.6)
}

// MARK: - Hover Highlight Modifier

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

// MARK: - Circular Button Style

struct CircularButtonStyle: ViewModifier {
    let isActive: Bool
    let activeColor: Color
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(isActive ? activeColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

extension View {
    func circularButton(isActive: Bool = false, activeColor: Color = .accentColor) -> some View {
        modifier(CircularButtonStyle(isActive: isActive, activeColor: activeColor))
    }
}
