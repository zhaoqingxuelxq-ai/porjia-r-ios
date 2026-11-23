import SwiftUI

struct ModelsView: View {
    @State private var query = ""
    @State private var selected: DataSources.ProviderRow?
    private let ds = DataSources.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    let st = ds.stats
                    HStack(spacing: Theme.gap) {
                        StatCard(n: "\(st.providers)", label: "供应商", tint: Theme.brand)
                        StatCard(n: "\(st.models)", label: "模型", tint: .blue)
                    }

                    Card {
                        SectionTitle(icon: "magnifyingglass", title: "路由目录", tint: .blue)
                        TextField("搜索 ID / 名称 / API", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none).disableAutocorrection(true)
                        Text("点击供应商查看模型能力（推理 / 工具调用 / 结构化输出）")
                            .font(.caption2).foregroundColor(Theme.text2)
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(ds.searchProviders(query)) { p in
                            Button { selected = p } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(p.id).font(.subheadline.weight(.semibold))
                                            if p.npm.lowercased().contains("anthropic") {
                                                Badge(text: "Anthropic", tint: .orange)
                                            }
                                        }
                                        Text(p.name).font(.caption).foregroundColor(Theme.text2)
                                        Text(p.api).font(.caption2).foregroundColor(.blue).lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text("\(p.modelCount)").font(.title3.weight(.bold)).foregroundColor(Theme.brand)
                                        Text("模型").font(.caption2).foregroundColor(Theme.text2)
                                    }
                                }
                                .padding(Theme.pad)
                                .background(Theme.card)
                                .cornerRadius(Theme.radiusSm)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("模型路由")
            .sheet(item: $selected) { p in
                ProviderDetailView(provider: p)
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// 供应商模型能力详情
struct ProviderDetailView: View {
    let provider: DataSources.ProviderRow
    private let ds = DataSources.shared
    @Environment(\.presentationMode) var mode

    private var models: [DataSources.ModelInfo] { ds.models(of: provider.id) }
    private var keys: [String] { ds.envKeys(provider.id) }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("供应商")) {
                    Text(provider.id).font(.headline)
                    Text(provider.name).font(.caption).foregroundColor(Theme.text2)
                    Text(provider.api).font(.caption2).foregroundColor(.blue)
                    Text("Key 环境变量: \(keys.joined(separator: ", "))").font(.caption2).foregroundColor(Theme.text2)
                }
                Section(header: Text("模型能力（\(models.count)）")) {
                    ForEach(models.prefix(200)) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.name).font(.subheadline)
                            HStack {
                                if m.reasoning { Badge(text: "推理", tint: .purple) }
                                if m.toolCall { Badge(text: "工具", tint: .green) }
                                if m.structured { Badge(text: "结构化", tint: .blue) }
                                if !m.family.isEmpty { Text(m.family).font(.caption2).foregroundColor(Theme.text2) }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle(provider.name.isEmpty ? provider.id : provider.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { mode.wrappedValue.dismiss() } }
        }
        .navigationViewStyle(.stack)
    }
}
