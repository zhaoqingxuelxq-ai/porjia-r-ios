import SwiftUI

struct RulesView: View {
    private let ds = DataSources.shared
    @State private var query = ""

    private var files: [String] {
        query.isEmpty ? ds.ruleFiles : ds.ruleFiles.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Card {
                        SectionTitle(icon: "magnifyingglass", title: "V9 规范库", tint: .brand)
                        TextField("搜索章节", text: $query)
                            .textFieldStyle(.roundedBorder)
                        Text("\(files.count) 章 · 随 App 内置，离线可查")
                            .font(.caption2).foregroundColor(Theme.text2)
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(files, id: \.self) { f in
                            NavigationLink { RuleDetail(file: f) } label: {
                                HStack {
                                    Image(systemName: "doc.text.fill").foregroundColor(Theme.brand)
                                    Text(f).font(.subheadline).foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.text2)
                                }
                                .padding(14).background(Theme.card).cornerRadius(Theme.radiusSm)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("V9 规范")
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
