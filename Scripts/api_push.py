#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用 GitHub REST API 上传工程文件（绕开被阻断的 github.com git 端口）。
API 写文件产生的 commit 同样触发 GitHub Actions。

token 来源优先级：
  1. 环境变量 GH_TOKEN
  2. 当前文件同目录的 .gh_tok.tmp
"""
import base64, json, os, sys, time, urllib.request, urllib.error
from urllib.parse import quote

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USER = "zhaoqingxuelxq-ai"
REPO = "porjia-r-ios"
BRANCH = "main"
API = "https://api.github.com"

# 上传的文件白名单（相对 ROOT），用 git ls-files 的结果由外部传入更稳，这里扫描
EXCLUDE_DIRS = {".git", "build", "__pycache__", ".github/workflows"}
SKIP_NAMES = {".gh_tok.tmp", "*.ipa", "*.pyc"}


def get_token():
    t = os.environ.get("GH_TOKEN", "").strip()
    if t:
        return t
    p = os.path.join(ROOT, "Scripts", ".gh_tok.tmp")
    if not os.path.exists(p):
        p = os.path.join(ROOT, ".gh_tok.tmp")
    if os.path.exists(p):
        return open(p, encoding="utf-8").read().strip()
    raise SystemExit("未找到 token")


def api(method, path, token, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    # 路径含中文文件名时先做 percent-encode，保留查询分隔符
    if "?" in path:
        p, q = path.split("?", 1)
        enc_path = quote(p, safe="/") + "?" + quote(q, safe="=&:%")
    else:
        enc_path = quote(path, safe="/")
    req = urllib.request.Request(API + enc_path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "PorjiaR-Builder/1.0")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            b = r.read()
            return b if raw else (json.loads(b) if b else None)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} -> {e.code}: {detail[:600]}")


def collect_files():
    out = []
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in EXCLUDE_DIRS]
        for fn in fns:
            if fn in SKIP_NAMES or fn.endswith((".pyc", ".ipa")):
                continue
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            # 跳过 git 内部
            if rel.startswith(".git/"):
                continue
            out.append((rel, full))
    # workflow 单独处理（API 需要特殊路径）
    wf = os.path.join(ROOT, ".github", "workflows", "build-ipa.yml")
    if os.path.exists(wf):
        out.append((".github/workflows/build-ipa.yml", wf))
    return out


def main():
    tok = get_token()
    print(f"[API推送] 仓库 {USER}/{REPO}", flush=True)
    try:
        api("GET", f"/repos/{USER}/{REPO}", tok)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            api("POST", "/user/repos", tok, {
                "name": REPO, "private": True,
                "description": "破甲 R v9 iOS 原生 IPA (GitHub Actions 自动编译)",
                "auto_init": False,
            })
            print("[API推送] 仓库已创建", flush=True)

    files = collect_files()
    print(f"[API推送] 待上传 {len(files)} 个文件", flush=True)
    ok = 0
    for rel, full in files:
        try:
            content = base64.b64encode(open(full, "rb").read()).decode()
        except Exception as e:
            print(f"  跳过 {rel}: {e}", flush=True)
            continue
        body = {
            "message": f"upload {rel}",
            "content": content,
            "branch": BRANCH,
        }
        try:
            api("PUT", f"/repos/{USER}/{REPO}/contents/{rel}", tok, body)
            ok += 1
            print(f"  ✓ {rel}", flush=True)
        except RuntimeError as e:
            # 文件已存在时需要 sha
            if "422" in str(e) or "409" in str(e):
                try:
                    cur = api("GET", f"/repos/{USER}/{REPO}/contents/{rel}?ref={BRANCH}", tok)
                    body["sha"] = cur.get("sha")
                    api("PUT", f"/repos/{USER}/{REPO}/contents/{rel}", tok, body)
                    ok += 1
                    print(f"  ✓ {rel} (更新)", flush=True)
                    continue
                except Exception as e2:
                    print(f"  ✗ {rel}: {str(e2)[:120]}", flush=True)
            else:
                print(f"  ✗ {rel}: {str(e)[:120]}", flush=True)
    print(f"[API推送] 完成: {ok}/{len(files)}", flush=True)
    # 手动触发 workflow
    try:
        api("POST", f"/repos/{USER}/{REPO}/actions/workflows/build-ipa.yml/dispatches",
            tok, {"ref": BRANCH})
        print("[API推送] 已手动触发 Actions", flush=True)
    except Exception as e:
        print(f"[API推送] 触发失败(push 也会触发): {str(e)[:200]}", flush=True)
    print(f"[API推送] 查看: https://github.com/{USER}/{REPO}/actions", flush=True)


if __name__ == "__main__":
    main()
