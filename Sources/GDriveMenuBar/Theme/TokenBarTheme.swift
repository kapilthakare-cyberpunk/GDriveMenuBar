import SwiftUI

/// TokenBar-style design system for GDriveMenuBar.
enum TBTheme {
    static let blue = Color(nsColor: .systemBlue)
    // Accessible green (#1D7A33): systemGreen washes out on light glass cards.
    static let green = Color(red: 29/255, green: 122/255, blue: 51/255)
    static let gray = Color(nsColor: .secondaryLabelColor)
    static let orange = Color(nsColor: .systemOrange)
    static let red = Color(nsColor: .systemRed)
    static let yellow = Color(nsColor: .systemYellow)
    static let indigo = Color(red: 0x58/255, green: 0x56/255, blue: 0xD6/255)
    static let purple = Color(nsColor: .systemPurple)
    static let teal = Color(nsColor: .systemTeal)

    static func usageColor(_ pct: Double) -> Color {
        if pct >= 85 { return .red }
        if pct >= 70 { return .orange }
        return .green
    }

    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let bodyFont = Font.system(size: 12)
    static let numberFont = Font.system(size: 12, design: .monospaced)
    static let sectionFont = Font.system(size: 11, weight: .semibold)
}

struct TBCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TBSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(TBTheme.sectionFont)
            .foregroundStyle(TBTheme.gray)
    }
}

struct TabPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? AnyShapeStyle(.selection) : AnyShapeStyle(.quaternary.opacity(0.35)), in: Capsule())
    }
}

struct QuotaRing: View {
    let pct: Double // 0...100 used
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(pct/100, 0), 1))
                .stroke(TBTheme.usageColor(pct), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(pct))%").font(TBTheme.numberFont).bold()
        }.frame(width: 64, height: 64)
    }
}
