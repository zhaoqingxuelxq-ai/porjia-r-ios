#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""轮询 GitHub Actions 状态；成功后下载 IPA 产物到 build/ipa/。"""
import io, json, os, sys, time, urllib.request, urllib.error, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USER = "zhaoqingxuelxq-ai"
REPO = "porjia-r-ios"
API = "https://api.github.com"


def get_token():
    t = os.environ.get("GH_TOKEN", "").strip()
    if t:
        return t
    for p in (os.path.join(ROOT, ".gh_tok.tmp"), os.path.join(ROOT, "Scripts", ".gh_tok.tmp")):
        if os.path.exists(p):
            return open(p, encoding="utf-8").read().strip()
    raise SystemExit("无 token")


TOK = get_token()


def api(method, path, body=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    if "?" in path:
        p, q = path.split("?", 1)
        from urllib.parse import quote
        path = quote(p, safe="/") + "?" + quote(q, safe="=&:%")
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOK}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "PorjiaR-Builder/1.0")
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as r:
        b = r.read()
        return b if raw else (json.loads(b) if b else None)


def run_logs(run_id):
    """取失败日志里的错误行。"""
    try:
        blob = api("GET", f"/repos/{USER}/{REPO}/actions/runs/{run_id}/logs", raw=True)
        z = zipfile.ZipFile(io.BytesIO(blob))
        errs = []
        for n in z.namelist():
            if n.endswith(".txt"):
                txt = z.read(n).decode("utf-8", "replace")
                for line in txt.splitlines():
                    ll = line.lower()
                    if "error:" in ll or "fatal error" in ll or "❌" in line or " failed" in ll:
                        errs.append(line.strip())
        return errs[-30:]
    except Exception as e:
        return [f"(日志读取失败: {e})"]


def download(run_id):
    arts = api("GET", f"/repos/{USER}/{REPO}/actions/runs/{run_id}/artifacts")
    items = arts.get("artifacts", [])
    if not items:
        print("构建成功但无 artifact", flush=True)
        return
    art = next((a for a in items if "IPA" in a["name"].upper()), items[0])
    print(f"下载产物: {art['name']} ({art['size']} bytes)", flush=True)
    blob = api("GET", f"/repos/{USER}/{REPO}/actions/artifacts/{art['id']}/zip", raw=True)
    out = os.path.join(ROOT, "build", "ipa")
    os.makedirs(out, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(blob)).extractall(out)
    ipas = []
    for dp, _, fs in os.walk(out):
        for f in fs:
            if f.lower().endswith(".ipa"):
                ipas.append(os.path.join(dp, f))
    if ipas:
        ipa = ipas[0]
        with zipfile.ZipFile(ipa) as zz:
            bad = zz.testzip()
        print(f"IPA: {ipa}", flush=True)
        print(f"大小: {os.path.getsize(ipa)} bytes, zip校验: {'OK' if not bad else '损坏 '+bad}", flush=True)
    else:
        print("artifact 内无 .ipa", flush=True)


def main():
    timeout = int(sys.argv[1]) if len(sys.argv) > 1 else 1800
    deadline = time.time() + timeout
    print(f"轮询 Actions（最长 {timeout}s）…", flush=True)
    last_key = None
    run_id = None
    while time.time() < deadline:
        try:
            runs = api("GET", f"/repos/{USER}/{REPO}/actions/runs?per_page=5")
            items = runs.get("workflow_runs", [])
            if not items:
                print("暂无 run，等待…", flush=True)
                time.sleep(10)
                continue
            r = items[0]
            run_id = r["id"]
            key = (r["status"], r.get("conclusion"), r["run_number"])
            if key != last_key:
                print(f"run #{r['run_number']}: status={r['status']} conclusion={r.get('conclusion')}", flush=True)
                last_key = key
            if r["status"] == "completed":
                if r.get("conclusion") == "success":
                    download(run_id)
                    return 0
                else:
                    print(f"构建失败: {r.get('conclusion')}", flush=True)
                    for line in run_logs(run_id):
                        print("  " + line[:220], flush=True)
                    print(f"详情: {r.get('html_url')}", flush=True)
                    return 2
        except Exception as e:
            print(f"轮询异常: {str(e)[:200]}", flush=True)
        time.sleep(15)
    print("等待超时", flush=True)
    return 3


if __name__ == "__main__":
    sys.exit(main())
