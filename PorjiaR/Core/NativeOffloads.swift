import Foundation
import UIKit
import CoreLocation
import Vision
import Photos

/// 原生能力子集：剪贴板 / 定位 / 相册 OCR。
/// 只取低敏三项用于验证 Native Offload 模式；不含健康/NFC/HomeKit/通知等宽权限。
/// 所有读取由用户主动点击触发，单次授权，不做后台常驻采集。
final class NativeOffloads: NSObject {
    static let shared = NativeOffloads()
    private let loc = CLLocationManager()
    private var locContinuation: CheckedContinuation<Envelope, Never>?

    override init() {
        super.init()
        loc.delegate = self
        loc.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - 剪贴板
    func clipboard() -> Envelope {
        let s = UIPasteboard.general.string ?? ""
        return .ok("offload.clipboard", ["length": s.count, "preview": String(s.prefix(200))], tool: "NativeOffloads")
    }

    func copyToClipboard(_ text: String) -> Envelope {
        UIPasteboard.general.string = text
        return .ok("offload.copy", ["length": text.count], tool: "NativeOffloads")
    }

    // MARK: - 定位（单次，WhenInUse）
    func location() async -> Envelope {
        switch loc.authorizationStatus {
        case .notDetermined:
            loc.requestWhenInUseAuthorization()
            // 授权回调后再请求位置
            return await withCheckedContinuation { c in locContinuation = c }
        case .authorizedWhenInUse, .authorizedAlways:
            loc.requestLocation()
            return await withCheckedContinuation { c in locContinuation = c }
        case .denied, .restricted:
            return .fail("offload.location", "定位权限被拒绝", code: 3, tool: "NativeOffloads")
        @unknown default:
            return .fail("offload.location", "未知定位权限状态", code: 3, tool: "NativeOffloads")
        }
    }

    // MARK: - 相册 OCR（选一张图识别文字）
    func ocr(image: UIImage) -> Envelope {
        guard let cg = image.cgImage else {
            return .fail("offload.ocr", "图像无效", tool: "NativeOffloads")
        }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([req])
            let texts = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return .ok("offload.ocr", ["lines": texts.count, "text": texts.joined(separator: "\n")], tool: "NativeOffloads")
        } catch {
            return .fail("offload.ocr", error.localizedDescription, tool: "NativeOffloads")
        }
    }
}

extension NativeOffloads: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            locContinuation?.resume(returning: .fail("offload.location", "权限被拒绝", code: 3, tool: "NativeOffloads"))
            locContinuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else {
            locContinuation?.resume(returning: .fail("offload.location", "无位置数据", tool: "NativeOffloads"))
            locContinuation = nil
            return
        }
        let e = Envelope.ok("offload.location", [
            "lat": c.latitude, "lon": c.longitude,
            "note": "WGS84；国内地图需 GCJ-02 转换",
        ], tool: "NativeOffloads")
        locContinuation?.resume(returning: e)
        locContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locContinuation?.resume(returning: .fail("offload.location", error.localizedDescription, tool: "NativeOffloads"))
        locContinuation = nil
    }
}
