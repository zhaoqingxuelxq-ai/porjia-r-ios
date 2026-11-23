import SwiftUI

/// 全局设计系统：统一配色、间距、圆角、卡片与徽标。
/// 用语义色（dynamicColor）自动适配浅色/深色模式，不写死背景。
enum Theme {
    // 品牌色
    static let brand = Color.red
    static let brandDeep = Color(red: 0.72, green: 0.06, blue: 0.10)
    static let brandSoft = Color.red.opacity(0.12)

    // 功能色（同时用于状态徽标）
    static let ok = Color.green
    static let warn = Color.orange
    static let danger = Color.red
    static let info = Color.blue
    static let accent = Color.purple

    // 动态背景（浅/深自适应）
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardFlat = Color(uiColor: .systemBackground)
    static let sep = Color(uiColor: .separator).opacity(0.35)
    static let text2 = Color(uiColor: .secondaryLabel)

    // 尺寸
    static let radius: CGFloat = 14
    static let radiusSm: CGFloat = 10
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12

    static let mono = Font.system(.caption, design: .monospaced)
}

/// 通用卡片容器
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(Theme.pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .cornerRadius(Theme.radius)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(Theme.sep, lineWidth: 0.5))
    }
}

/// 区块标题
struct SectionTitle: View {
    let icon: String
    let title: String
    var tint: Color = Theme.brand
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(tint)
            Text(title).font(.headline)
            Spacer()
        }
    }
}

/// 状态徽标
struct Badge: View {
    let text: String
    var tint: Color = Theme.brand
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14))
            .foregroundColor(tint)
            .cornerRadius(6)
    }
}

/// 统计卡
struct StatCard: View {
    let n: String
    let label: String
    var tint: Color = Theme.brand
    var body: some View {
        VStack(spacing: 4) {
            Text(n).font(.title2.weight(.bold)).foregroundColor(tint)
            Text(label).font(.caption).foregroundColor(Theme.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card)
        .cornerRadius(Theme.radiusSm)
    }
}

/// 主操作按钮
struct PrimaryButton: View {
    let title: String
    let icon: String
    var busy: Bool = false
    var disabled: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                else { Image(systemName: icon) }
                Text(busy ? "执行中…" : title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.brand)
        .disabled(disabled || busy)
    }
}

/// 空态
struct EmptyHint: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundColor(Theme.text2)
            Text(text).font(.subheadline).foregroundColor(Theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
