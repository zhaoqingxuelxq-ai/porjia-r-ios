import SwiftUI

/// 配置条目页：四类条目（persona/prompt/rule/asset）逐项增删启停，持久化到沙箱。
struct ConfigView: View {
    @State private var entries: [[String: Any]] = Store.shared.entries()
    @State private var showAdd = false
    @State private var newID = ""
    @State private var newKind = "rule"
    @State private var newBody = ""
    @State private var newTrigger = ""
    private let kinds = ["persona", "prompt", "rule", "asset"]

    var body: some View {
        NavigationView {
            List {
                ForEach(entries, id: \.id) { e in
                    EntryRow(entry: e) {
                        toggle(e["id"] as? String ?? "")
                    }
                }
                .onDelete { idx in
                    for i in idx {
                        if let id = entries[i]["id"] as? String, entries[i]["builtin"] as? Bool != true {
                            entries.remove(at: i)
                        }
                    }
                    persist()
                }
            }
            .navigationTitle("配置条目")
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showAdd) {
                NavigationView {
                    Form {
                        TextField("条目 ID", text: $newID)
                        Picker("类型", selection: $newKind) {
                            ForEach(kinds, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("触发词", text: $newTrigger)
                        TextField("内容", text: $newBody)
                    }
                    .navigationTitle("新增条目")
                    .toolbar {
                        Button("添加") { add(); showAdd = false }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func persist() { Store.shared.saveEntries(entries); entries = Store.shared.entries() }

    private func toggle(_ id: String) {
        if let i = entries.firstIndex(where: { $0["id"] as? String == id }) {
            entries[i]["enabled"] = !(entries[i]["enabled"] as? Bool ?? false)
            persist()
        }
    }

    private func add() {
        guard !newID.isEmpty, kinds.contains(newKind) else { return }
        if let i = entries.firstIndex(where: { $0["id"] as? String == newID }) {
            entries[i]["body"] = newBody; entries[i]["trigger"] = newTrigger; entries[i]["enabled"] = true
        } else {
            entries.append(["id": newID, "kind": newKind, "body": newBody,
                            "trigger": newTrigger, "enabled": true])
        }
        newID = ""; newBody = ""; newTrigger = ""
        persist()
    }
}

extension Dictionary where Key == String, Value == Any {
    var id: String { self["id"] as? String ?? UUID().uuidString }
}

private struct EntryRow: View {
    let entry: [String: Any]
    let toggle: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry["id"] as? String ?? "").font(.subheadline.weight(.semibold))
                    if entry["builtin"] as? Bool == true {
                        Text("内置").font(.caption2).foregroundColor(.red)
                    }
                }
                Text(entry["body"] as? String ?? "").font(.caption).foregroundColor(.secondary).lineLimit(2)
                Text(entry["trigger"] as? String ?? "").font(.caption2).foregroundColor(.blue)
            }
            Spacer()
            Button(action: toggle) {
                Image(systemName: (entry["enabled"] as? Bool ?? false) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor((entry["enabled"] as? Bool ?? false) ? .green : .gray)
            }.buttonStyle(.plain)
        }
        .opacity((entry["enabled"] as? Bool ?? false) ? 1 : 0.55)
    }
}
