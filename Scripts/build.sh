#!/usr/bin/env bash
# 破甲 R · iOS IPA 一键打包脚本（必须在 macOS + Xcode 上运行）
# 用法： bash Scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build"
APP="PorjiaR"
SCHEME="PorjiaR"

echo "==> [0/5] 环境检查（需 macOS + Xcode）"
[[ "$(uname)" == "Darwin" ]] || { echo "本脚本只能在 macOS 运行；Windows/Linux 请用 GitHub Actions 云端打包"; exit 1; }
xcodebuild -version
command -v xcodegen >/dev/null 2>&1 || {
  echo "未安装 xcodegen，尝试安装..."
  if command -v brew >/dev/null 2>&1; then brew install xcodegen;
  else echo "请先安装 xcodegen: brew install xcodegen 或 https://github.com/yonaskolb/XcodeGen"; exit 1; fi
}

echo "==> [1/5] 生成 Xcode 工程"
xcodegen generate

echo "==> [2/5] 清理旧产物"
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> [3/5] Archive（ad-hoc 签名，arm64 真机）"
xcodebuild -scheme "$SCHEME" -project "$APP.xcodeproj" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/$APP.xcarchive" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
  clean archive

echo "==> [4/5] 导出 IPA"
xcodebuild -exportArchive \
  -archivePath "$OUT/$APP.xcarchive" \
  -exportOptionsPlist exportOptions.plist \
  -exportPath "$OUT/ipa" \
  CODE_SIGNING_ALLOWED=NO

IPA="$OUT/ipa/破甲 R.ipa"
[[ -f "$IPA" ]] || IPA="$(find "$OUT/ipa" -name '*.ipa' -print -quit)"

echo "==> [5/5] 校验产物"
if [[ -f "$IPA" ]]; then
  unzip -t "$IPA" >/dev/null && echo "ZIP 完整性: OK"
  echo "IPA: $IPA"
  echo "大小: $(du -h "$IPA" | cut -f1)"
  echo "安装: 用 TrollStore 打开该 IPA → Install"
else
  echo "未找到 IPA 产物"; exit 1
fi
