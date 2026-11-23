#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
破甲 R · GitHub Actions 全自动出包脚本（Windows / macOS / Linux 通用，仅用标准库）

用法：
    python Scripts/build_via_github.py --user <GitHub用户名> --token <Personal Access Token>

可选：
    --repo <仓库名>          默认 porjia-r-ios
    --private/--public       默认私有仓库
    --no-wait                只推送触发，不等待下载
    --timeout <秒>           等待 CI 的最长秒数，默认 1800

token 需要的权限（创建 classic token 时勾选）：
    repo  (全部) —— 建私有仓库 + 推送代码 + 读 actions 产物
若用 fine-grained token：需要 Contents(read/write)、Actions(read)、Metadata(read)。

流程（全自动，无需再操作）：
    1. 检查/创建 GitHub 仓库
    2. 配置 git remote 并推送当前工程（含 .github/workflows/build-ipa.yml）
    3. push 自动触发 macOS runner 上的 Xcode 编译
    4. 轮询 Actions 运行状态，实时打印进度
    5. 成功后下载 PorjiaR-IPA 产物，解压出 .ipa 到 build/ipa/
    6. 校验 IPA 完整性并打印安装路径
"""
import argparse
import base64
import io
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.github.com"
UA = "PorjiaR-Builder/1.0"


def log(msg):
    print(f"[出包] {msg}", flush=True)


def api(method, path, token, body=None, raw=False):
    url = API + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", UA)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            payload = r.read()
            return payload if raw else (json.loads(payload) if payload else None)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise RuntimeError(f"GitHub API {method} {path} -> HTTP {e.code}\n{detail[:800]}")


def sh(cmd, cwd=ROOT, check=True):
    log("$ " + " ".join(cmd))
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.stdout:
        print(r.stdout.rstrip(), flush=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"命令失败 (exit {r.returncode}): {r.stderr.strip()[:1000]}")
    return r


def ensure_repo(user, repo, token, private):
    path = f"/repos/{user}/{repo}"
    try:
        info = api("GET", path, token)
        log(f"仓库已存在: {info['html_url']}")
        return info
    except RuntimeError as e:
        if "HTTP 404" not in str(e):
            raise
    log(f"创建仓库: {repo} ({'私有' if private else '公开'})")
    body = {
        "name": repo,
        "private": private,
        "description": "破甲 R v9 · iOS 原生 IPA（GitHub Actions 自动编译）",
        "auto_init": False,
    }
    info = api("POST", "/user/repos", token, body)
    log(f"仓库已创建: {info['html_url']}")
    return info


def push(user, repo, token):
    # 用 token 嵌 URL 的方式推送，避免交互凭证
    remote = f"https://{token}@github.com/{user}/{repo}.git"
    sh(["git", "remote", "remove", "origin"], check=False)
    sh(["git", "remote", "add", "origin", remote])
    sh(["git", "branch", "-M", "main"])
    sh(["git", "push", "-u", "-f", "origin", "main"])
    # 推完把远程 URL 清成明文（不把 token 落盘）
    sh(["git", "remote", "set-url", "origin", f"https://github.com/{user}/{repo}.git"])


def latest_run(user, repo, token, since):
    runs = api("GET", f"/repos/{user}/{repo}/actions/runs?per_page=10", token)
    items = runs.get("workflow_runs", [])
    if not items:
        return None
    for r in items:
        # 只认本次 push 之后触发的 run
        created = r.get("created_at", "")
        if created >= since and r.get("event") in ("push", "workflow_dispatch"):
            return r
    return items[0]


def wait_ci(user, repo, token, timeout):
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    log("等待 Actions 触发…")
    run = None
    deadline = time.time() + timeout
    while time.time() < deadline:
        run = latest_run(user, repo, token, since)
        if run:
            log(f"检测到 run #{run['run_number']} status={run['status']} conclusion={run.get('conclusion')}")
            break
        time.sleep(5)
    if not run:
        raise RuntimeError("超时：未检测到 Actions 运行（检查仓库 Settings > Actions 是否启用）")

    rid = run["id"]
    last = None
    while time.time() < deadline:
        cur = api("GET", f"/repos/{user}/{repo}/actions/runs/{rid}", token)
        status = cur.get("status")
        concl = cur.get("conclusion")
        if (status, concl) != last:
            log(f"run #{cur['run_number']}: status={status} conclusion={concl}")
            last = (status, concl)
        if status == "completed":
            if concl == "success":
                return cur
            # 失败：拉日志尾部帮助排错
            try:
                logs = api("GET", f"/repos/{user}/{repo}/actions/runs/{rid}/logs", token, raw=True)
                z = zipfile.ZipFile(io.BytesIO(logs))
                tail = []
                for n in z.namelist():
                    if n.endswith(".txt"):
                        txt = z.read(n).decode("utf-8", "replace")
                        tail.extend([l for l in txt.splitlines() if "error:" in l.lower() or "fail" in l.lower()][-20:])
                if tail:
                    log("编译错误摘要:\n" + "\n".join(tail[-25:]))
            except Exception as e:
                log(f"(取日志失败: {e})")
            raise RuntimeError(f"Actions 失败: {concl} — 查看 {cur.get('html_url')}")
        time.sleep(10)
    raise RuntimeError(f"等待 CI 超时 ({timeout}s)，run: {run.get('html_url')}")


def download_ipa(user, repo, token, run_id):
    arts = api("GET", f"/repos/{user}/{repo}/actions/runs/{run_id}/artifacts", token)
    items = arts.get("artifacts", [])
    if not items:
        raise RuntimeError("构建成功但没有 artifact（检查 workflow 的 upload-artifact 步骤）")
    art = next((a for a in items if "IPA" in a["name"].upper()), items[0])
    log(f"下载产物: {art['name']} ({art['size']} bytes)")
    blob = api("GET", f"/repos/{user}/{repo}/actions/artifacts/{art['id']}/zip", token, raw=True)

    out_dir = os.path.join(ROOT, "build", "ipa")
    os.makedirs(out_dir, exist_ok=True)
    z = zipfile.ZipFile(io.BytesIO(blob))
    z.extractall(out_dir)
    ipas = []
    for dp, _, fs in os.walk(out_dir):
        for f in fs:
            if f.lower().endswith(".ipa"):
                ipas.append(os.path.join(dp, f))
    if not ipas:
        raise RuntimeError("artifact 解压后未找到 .ipa 文件")
    ipa = ipas[0]
    with zipfile.ZipFile(ipa) as zz:
        bad = zz.testzip()
    if bad:
        raise RuntimeError(f"IPA zip 损坏: {bad}")
    log(f"IPA 校验通过: {ipa}")
    log(f"大小: {os.path.getsize(ipa)} bytes")
    return ipa


def main():
    ap = argparse.ArgumentParser(description="破甲 R · GitHub Actions 全自动出包")
    ap.add_argument("--user", required=True, help="GitHub 用户名")
    ap.add_argument("--token", required=True, help="Personal Access Token (repo 权限)")
    ap.add_argument("--repo", default="porjia-r-ios", help="仓库名，默认 porjia-r-ios")
    ap.add_argument("--public", action="store_true", help="用公开仓库（默认私有）")
    ap.add_argument("--no-wait", action="store_true", help="只推送触发，不等待下载")
    ap.add_argument("--timeout", type=int, default=1800, help="等待 CI 秒数，默认 1800")
    args = ap.parse_args()

    token = args.token.strip()
    if not token:
        raise RuntimeError("token 为空")
    log(f"目标仓库: https://github.com/{args.user}/{args.repo}")

    ensure_repo(args.user, args.repo, token, not args.public)
    push(args.user, args.repo, token)
    log("代码已推送，Actions 已触发")

    if args.no_wait:
        log(f"--no-wait 模式，请到 https://github.com/{args.user}/{args.repo}/actions 查看")
        return

    run = wait_ci(args.user, args.repo, token, args.timeout)
    ipa = download_ipa(args.user, args.repo, token, run["id"])
    log(f"完成！用 TrollStore 打开安装: {ipa}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[出包] 失败: {e}", file=sys.stderr, flush=True)
        sys.exit(1)
