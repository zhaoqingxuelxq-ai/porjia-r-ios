# 破甲 R · iOS 原生 IPA 交付说明

## 一、交付物

一个**原生 SwiftUI iOS 应用工程**，产物是标准 `.ipa`，用 TrollStore 直接安装到设备，全程不依赖浏览器、不依赖本地服务、不依赖网络。

| 项 | 值 |
|---|---|
| 工程目录 | `G:/WORKBUDDY智能体/2026-11-22-17-13-23/破甲R-iOS/` |
| 应用名 | 破甲 R |
| Bundle ID | `top.porjia.r` |
| 版本 | 1.0 (build 1) |
| 产物 | `PorjiaR.ipa`（由 build.sh / GitHub Actions 产出） |
| 工程定义 | `project.yml`（XcodeGen，可复现生成 .xcodeproj） |
| 静态校验 | `python Scripts/verify_project.py` → 28/28 PASS |

## 二、应用核心功能（全部原生、离线）

| 功能 | 实现 | 说明 |
|---|---|---|
| **破甲引擎** | Swift 原生 `Engine/BreakerEngine.swift` + `MachOParser.swift` | 8 子命令：`info / symbols / strings / gate / auth / patch / verify / report` |
| Mach-O / IPA 解析 | 纯 Swift 解析 thin / FAT、符号表、段映射、vm→file 偏移；系统 Compression 框架解 zip 内主二进制 | 不依赖 Python / r2 / IDA |
| 授权判定 `auth` | 符号 + 字符串启发式，判 server / local / mixed，给结论与下一步 | 先判再动手，避免空耗 |
| 校验点定位 `gate` | 符号表 + 字符串命中，秒级给候选 | 不做全量反汇编 |
| 字节补丁 `patch` | 等长替换 + 原字节强校验 + 自动 `.bak` 备份；默认 dry-run | 写入才落盘，可回滚 |
| 校验 `verify` | 指定偏移读字节比对 | 确认补丁落地 |
| 四件套报告 `report` | 目标/授权位置/校验点/patch 实体/验证步骤 | 可系统分享导出 |
| **模型路由** | 内置 `models-dev-api.json` | 223 供应商 / 8080 模型，支持按 ID/名称/API 检索 |
| **V9 规范库** | 内置 17 章 references + SOUL | 离线浏览，逐章查看 |
| **配置管理** | 沙箱 JSON 持久化 | 四类条目（persona/prompt/rule/asset）增删启停 |
| 文件导入 | iOS `fileImporter` + 文件 App 共享 | 从「文件」App 选 IPA / Mach-O 分析 |

数据处理：所有分析在本机沙箱完成，导入文件只在 App 文档目录，不上传；配置/记忆以 JSON 原子写落盘。App 不含任何 `WKWebView` / 网络请求 —— 纯原生。

## 三、目标 iOS 版本

| 项 | 值 | 依据 |
|---|---|---|
| Deployment Target | **iOS 15.0** | `project.yml` / Info.plist / entitlements 三处一致 |
| Swift | 5.9 | Xcode 15+ 自带 |
| SDK | iOS 17+ (Xcode 15/16) | 编译用；向下兼容到 15.0 |
| 编译配置 | Release，ad-hoc 签名 | `CODE_SIGN_IDENTITY="-"` |

选 15.0 的原因：SwiftUI 的 `fileImporter`、`GroupBox`、`.borderedProminent`、`.textSelection` 等所用 API 都在 iOS 15+ 稳定；同时 15.0 落在 TrollStore 支持区间内，覆盖绝大多数仍在用的越狱设备。若需下探到 iOS 14，需替换少量 SwiftUI API，可另行调整。

## 四、设备兼容范围

| 维度 | 范围 |
|---|---|
| 设备类型 | iPhone + iPad（`TARGETED_DEVICE_FAMILY = 1,2`） |
| CPU 架构 | arm64 / arm64e（A9 及以上，Info.plist 要求 `arm64`） |
| 系统版本 | iOS 15.0 / 15.x / 16.x（含 16.6.1）/ 17.0 |
| 安装前提 | 设备已安装 **TrollStore**（CoreTrust 绕过，安装不需 App Store 签名） |
| 方向 | iPhone：竖屏 + 左右横屏；iPad：四向 + 竖屏倒置 |

**不在兼容范围**：iOS 17.0.1 及以上（TrollStore 尚不支持）、未越狱且无 TrollStore 的设备（这类设备无法侧载本 ad-hoc IPA）、Intel 架构模拟器（工程只编 `iphoneos`）。

## 五、打包安装所需配置要求

### 5.1 编译环境（二选一）

- **本地 macOS**：macOS Sonoma/Sequoia + Xcode 15+ + XcodeGen + Homebrew
- **云端（推荐，Windows 用户用这个）**：GitHub 仓库 + Actions（自带 `macos-14` runner），推代码即自动出 IPA，从 Artifacts 下载

### 5.2 关键配置

| 配置文件 | 作用 | 关键字段 |
|---|---|---|
| `project.yml` | XcodeGen 生成 .xcodeproj | `bundleId: top.porjia.r`、`iOS 15.0`、`CODE_SIGN_IDENTITY: "-"`（ad-hoc）、iPhone+iPad |
| `PorjiaR/Info.plist` | 应用配置 | 显示名「破甲 R」、`UIFileSharingEnabled=true`、`LSSupportsOpeningDocumentsInPlace=true`、URL scheme `porjiar`、要求 arm64 |
| `PorjiaR/PorjiaR.entitlements` | 权限 | `application-identifier = $(PRODUCT_BUNDLE_IDENTIFIER)`、`get-task-allow=false` |
| `exportOptions.plist` | 导出 IPA | `method=ad-hoc`、`signingStyle=manual`、无 teamID、不削 bitcode |
| `Scripts/build.sh` | 本地一键打包 | xcodegen → xcodebuild archive → export IPA → 校验 |
| `.github/workflows/build-ipa.yml` | 云端打包 | `macos-14` → 同上 → 上传 IPA artifact |

### 5.3 打包步骤

**云端（本机是 Windows，走这条）：**
1. 把 `破甲R-iOS/` 整个目录作为仓库推到 GitHub（main 或 master 分支）
2. 触发 Actions（push 自动触发，或在 Actions 页点 Run workflow）
3. 跑完进 Artifacts 下载 `PorjiaR-IPA`
4. 解压得到 `破甲 R.ipa`

**本地 Mac：**
```bash
cd 破甲R-iOS
bash Scripts/build.sh
# 产物：build/ipa/破甲 R.ipa
```

### 5.4 安装到设备

1. iPhone/iPad 先装好 TrollStore（巨魔）
2. 用「文件」App 或 AirDrop 把 `破甲 R.ipa` 放到手机
3. 在 TrollStore 中打开该 IPA → Install
4. 桌面出现「破甲 R」图标，直接打开使用

注：Bundle ID `top.porjia.r` 与之前的 Minis 定制包（`com.aztut.app`）不同，两者可共存不冲突。覆盖升级本应用时，配置/记忆数据保留在 App 文档目录。

## 六、本机校验结果

本机为 Windows，无 Xcode / Swift，无法在此编译 iOS 二进制。已完成不依赖 Xcode 的全部静态校验：

`python Scripts/verify_project.py` → **28/28 PASS**
- 工程文件齐全、plist/XML/YAML/JSON 全部合法
- Bundle ID、版本、最低系统、签名方式、导出方式、CI 配置逐项核对
- 模型表 223/8080、V9 规范 17 章资源完整
- Swift 源码括号配对、`@main` 入口、8 命令、Mach-O 解析、fileImporter 都在
- 确认无 WebView、无网络请求、无本地服务依赖（纯原生）

Swift 代码里已修正一处真实问题：ZIP 内条目是 raw deflate，解压用 `COMPRESSION_DEFLATE`（非 zlib 包装）。

编译动作在 macOS / GitHub Actions 上执行，`build.sh` 与 CI 已把这一步脚本化，无需手工干预。
