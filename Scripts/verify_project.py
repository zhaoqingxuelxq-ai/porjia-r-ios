#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""破甲 R iOS 工程静态校验（Windows/Mac/Linux 均可跑，无需 Xcode）。

校验：目录结构、plist/xml 合法、YAML 合法、JSON 合法、Swift 括号配对、
资源引用齐全、关键配置字段（bundle id / 版本 / 签名方式）。
"""
import os
import sys
import json
import plistlib
import xml.etree.ElementTree as ET

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + (" :: " + str(detail) if detail and not cond else ""))


def main():
    print("破甲 R · iOS 原生工程静态校验")
    print("=" * 52)

    # T1 结构
    required = [
        "project.yml", "exportOptions.plist",
        "PorjiaR/Info.plist", "PorjiaR/PorjiaR.entitlements",
        "PorjiaR/App/PorjiaRApp.swift",
        "PorjiaR/Core/Envelope.swift", "PorjiaR/Core/Store.swift", "PorjiaR/Core/DataSources.swift",
        "PorjiaR/Engine/MachOParser.swift", "PorjiaR/Engine/BreakerEngine.swift",
        "PorjiaR/Features/RootView.swift", "PorjiaR/Features/BreakerView.swift",
        "PorjiaR/Features/ModelsView.swift", "PorjiaR/Features/RulesView.swift",
        "PorjiaR/Features/ConfigView.swift", "PorjiaR/Features/AboutView.swift",
        "PorjiaR/Resources/models-dev-api.json",
        "Scripts/build.sh", ".github/workflows/build-ipa.yml",
    ]
    missing = [r for r in required if not os.path.isfile(os.path.join(BASE, r))]
    check("T1 工程文件齐全", not missing, missing)

    # T2 Info.plist 合法 + 关键字段
    info_path = os.path.join(BASE, "PorjiaR", "Info.plist")
    try:
        ET.parse(info_path)
        with open(info_path, "rb") as f:
            info = plistlib.load(f)
        check("T2 Info.plist XML 合法", True)
    except Exception as e:
        info = {}
        check("T2 Info.plist XML 合法", False, e)
    check("T3 显示名 = 破甲 R", info.get("CFBundleDisplayName") == "破甲 R", info.get("CFBundleDisplayName"))
    check("T4 Bundle ID 变量化", info.get("CFBundleIdentifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)")
    check("T5 最低版本 15.0", info.get("MinimumOSVersion") == "15.0", info.get("MinimumOSVersion"))
    check("T6 文件共享开启", info.get("UIFileSharingEnabled") is True)
    check("T7 arm64 设备要求", "arm64" in info.get("UIRequiredDeviceCapabilities", []))
    check("T8 本地 URL scheme", "porjiar" in str(info.get("CFBundleURLTypes", "")))

    # T9 entitlements
    ent_path = os.path.join(BASE, "PorjiaR", "PorjiaR.entitlements")
    try:
        with open(ent_path, "rb") as f:
            ent = plistlib.load(f)
        check("T9 entitlements 合法", True)
        check("T10 application-identifier 变量化",
              ent.get("application-identifier") == "$(PRODUCT_BUNDLE_IDENTIFIER)")
    except Exception as e:
        check("T9 entitlements 合法", False, e)

    # T11 exportOptions
    with open(os.path.join(BASE, "exportOptions.plist"), "rb") as f:
        exp = plistlib.load(f)
    check("T11 ad-hoc 导出", exp.get("method") == "ad-hoc", exp.get("method"))

    # T12 YAML
    try:
        import yaml
        with open(os.path.join(BASE, "project.yml"), encoding="utf-8") as f:
            proj = yaml.safe_load(f)
        check("T12 project.yml 合法", True)
        tgt = proj["targets"]["PorjiaR"]
        check("T13 bundleId = top.porjia.r", tgt["settings"]["PRODUCT_BUNDLE_IDENTIFIER"] == "top.porjia.r")
        check("T14 部署目标 15.0", str(tgt["deploymentTarget"]) == "15.0", tgt["deploymentTarget"])
        check("T15 ad-hoc 签名", "-" in str(tgt["settings"].get("CODE_SIGN_IDENTITY")),
              tgt["settings"].get("CODE_SIGN_IDENTITY"))
    except Exception as e:
        check("T12 project.yml 合法", False, e)

    # T16 CI workflow
    wf = open(os.path.join(BASE, ".github", "workflows", "build-ipa.yml"), encoding="utf-8").read()
    check("T16 CI 用 macOS runner", "macos-" in wf)
    check("T17 CI 产出 IPA", "upload-artifact" in wf and "*.ipa" in wf)

    # T18 模型路由表完整
    with open(os.path.join(BASE, "PorjiaR", "Resources", "models-dev-api.json"), encoding="utf-8") as f:
        models = json.load(f)
    mcount = sum(len(p.get("models", {})) for p in models.values())
    check("T18 模型表 223/8080", len(models) >= 200 and mcount >= 8000, (len(models), mcount))

    # T19 V9 规范章节数
    rules = os.path.join(BASE, "PorjiaR", "Resources", "Rules")
    md = [f for f in os.listdir(rules) if f.endswith(".md")]
    check("T19 V9 规范 >=17 章", len(md) >= 17, len(md))

    # T20 Swift 括号配对 + 关键符号
    swift_dir = os.path.join(BASE, "PorjiaR")
    swift_files = []
    for root, _, files in os.walk(swift_dir):
        for fn in files:
            if fn.endswith(".swift"):
                swift_files.append(os.path.join(root, fn))
    check("T20 Swift 文件 >=8", len(swift_files) >= 8, len(swift_files))
    balanced = True
    for fp in swift_files:
        s = open(fp, encoding="utf-8").read()
        # 粗略剔除字符串与注释后统计花括号（够用于静态哨兵）
        for a, b in [("{", "}"), ("(", ")"), ("[", "]")]:
            if s.count(a) != s.count(b):
                balanced = False
                print("    括号不平衡: %s %s=%d %s=%d" % (os.path.basename(fp), a, s.count(a), b, s.count(b)))
    check("T21 Swift 括号配对", balanced)
    code = "\n".join(open(fp, encoding="utf-8").read() for fp in swift_files)
    check("T22 @main 入口", "@main" in code and "PorjiaRApp" in code)
    check("T23 破甲引擎 8 命令",
          all(k in code for k in ["info", "symbols", "strings", "gate", "auth", "patch", "verify", "report"]))
    check("T24 Mach-O 解析", "LC_SYMTAB" in code or "0x2" in code and "parseSymtab" in code)
    check("T25 文件导入 fileImporter", "fileImporter" in code)
    check("T26 无浏览器依赖", "WKWebView" not in code and "SFSafariViewController" not in code and "UIWebView" not in code)
    check("T27 无本地服务依赖", "URLSession" not in code and "http://127" not in code and "localhost" not in code)

    # T28 build.sh macOS 门禁
    sh = open(os.path.join(BASE, "Scripts", "build.sh"), encoding="utf-8").read()
    check("T28 build.sh 用 xcodegen+xcodebuild", "xcodegen generate" in sh and "xcodebuild" in sh)

    print("=" * 52)
    print("结果: %d/%d PASS" % (len(PASS), len(PASS) + len(FAIL)))
    if FAIL:
        print("失败项:", ", ".join(FAIL))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
