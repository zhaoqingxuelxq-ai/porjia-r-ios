import SwiftUI

struct ModelsView: View {
    @State private var query = ""
    private let ds = DataSources.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                let st = ds.stats
                HStack(spacing: 12) {
                    StatCard(n: "\(st.providers)", label: "供应商")
                    StatCard(n: "\(st.models)", label: "模型")
                }.padding(.horizontal)

                TextField("搜索供应商 ID / 名称 / API", text: $query)
                    .textFieldStyle(.roundedBorder).padding(.horizontal)
                    .autocapitalization(.none).disableAutocorrection(true)

                List(ds.searchProviders(query)) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.id).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(p.modelCount) 模型").font(.caption).foregroundColor(.secondary)
                        }
                        Text(p.name).font(.caption).foregroundColor(.secondary)
                        Text(p.api).font(.caption2).foregroundColor(.blue).lineLimit(1)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("模型路由")
        }
        .navigationViewStyle(.stack)
    }
}

private struct StatCard: View {
    let n: String; let label: String
    var body: some View {
        VStack {
            Text(n).font(.title.weight(.bold)).foregroundColor(.red)
            Text(label).font(.caption).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity).padding()
        .background(Color(.secondarySystemBackground)).cornerRadius(10)
    }
}
