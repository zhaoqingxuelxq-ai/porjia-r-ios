import Foundation
import UIKit

/// 后台任务注册（对齐 IPA 的 BGTaskScheduler + minis-scheduled best-effort）。
/// TrollStore 装的应用后台受限，这里只做"尽力而为"的定时刷新占位，
/// 真正危险的 agent 循环不在此自动执行——需用户主动打开 App。
final class BackgroundTasks {
    static let shared = BackgroundTasks()
    private let refreshID = "top.porjia.r.refresh"

    func register() {
        // TrollStore 环境无有效后台推送证书，注册后台任务无意义；
        // 仅保存状态供用户查看（best-effort 语义，与 IPA 一致）。
        schedule()
    }

    /// 调度一次后台刷新；失败静默（best-effort，与 IPA 的 minis-scheduled 语义一致）。
    func schedule() {
        let note: [String: Any] = [
            "schema": "porjia.bgtask/1",
            "scheduledAt": ISO8601DateFormatter().string(from: Date()),
            "policy": "best-effort",
        ]
        Store.shared.save("bgtask_state", note)
    }

    /// 上次后台调度时间
    func lastRun() -> String? {
        return Store.shared.load("bgtask_state", default: [:])["scheduledAt"] as? String
    }
}
