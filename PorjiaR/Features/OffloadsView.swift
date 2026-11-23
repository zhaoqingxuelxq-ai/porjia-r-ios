import SwiftUI
import UniformTypeIdentifiers

/// 原生能力页：剪贴板 / 定位 / 相册 OCR 三项子集，用户主动触发。
struct OffloadsView: View {
    @State private var result = ""
    @State private var busy = false
    @State private var showImagePicker = false
    @State private var pickedImage: UIImage?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Card {
                        SectionTitle(icon: "sparkles", title: "原生能力子集", tint: .purple)
                        Text("只暴露剪贴板、定位、相册 OCR 三项低敏能力用于验证；不含健康/NFC/HomeKit/通讯类宽权限。每次读取都由你主动点击，不后台常驻。")
                            .font(.caption).foregroundColor(Theme.text2)
                    }

                    Card {
                        SectionTitle(icon: "doc.on.clipboard", title: "剪贴板", tint: .blue)
                        HStack {
                            Button("读取剪贴板") {
                                let e = NativeOffloads.shared.clipboard()
                                result = e.jsonString
                            }.buttonStyle(.bordered)
                            Button("复制结果") {
                                let e = NativeOffloads.shared.copyToClipboard(result)
                                result = e.jsonString
                            }.buttonStyle(.bordered)
                        }
                    }

                    Card {
                        SectionTitle(icon: "location.fill", title: "定位（单次）", tint: .green)
                        Button("获取当前位置") {
                            busy = true; result = "定位中…"
                            Task {
                                let e = await NativeOffloads.shared.location()
                                DispatchQueue.main.async { busy = false; result = e.jsonString }
                            }
                        }.buttonStyle(.bordered).disabled(busy)
                    }

                    Card {
                        SectionTitle(icon: "viewfinder", title: "相册 OCR", tint: .orange)
                        Button("从相册选图识别文字") { showImagePicker = true }
                            .buttonStyle(.bordered)
                        if let img = pickedImage {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 180).cornerRadius(8)
                        }
                    }

                    Card {
                        SectionTitle(icon: "terminal", title: "输出", tint: .brand)
                        ScrollView {
                            Text(result.isEmpty ? "—" : result).font(Theme.mono)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(minHeight: 140, maxHeight: 300)
                    }
                }
                .padding()
            }
            .navigationTitle("原生能力")
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $pickedImage) { img in
                    let e = NativeOffloads.shared.ocr(image: img)
                    result = e.jsonString
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// UIKit 图片选择器桥接
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ ui: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ p: ImagePicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
                parent.onPick(img)
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
