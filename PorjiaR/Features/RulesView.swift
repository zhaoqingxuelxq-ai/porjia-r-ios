import SwiftUI

struct RulesView: View {
    private let ds = DataSources.shared
    @State private var selected: String?

    var body: some View {
        NavigationView {
            List(ds.ruleFiles, id: \.self) { f in
                NavigationLink(f) { RuleDetail(file: f) }
            }
            .navigationTitle("V9 规范库")
            Text("选择左侧章节查看。规范随 App 内置，无需联网。")
                .foregroundColor(.secondary)
        }
        .navigationViewStyle(.stack)
    }
}

private struct RuleDetail: View {
    let file: String
    private let ds = DataSources.shared
    var body: some View {
        ScrollView {
            Text(ds.ruleContent(file))
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(file)
        .navigationBarTitleDisplayMode(.inline)
    }
}
