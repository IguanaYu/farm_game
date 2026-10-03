#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M0 本地验证编排（【主要】好友联网试玩版规划 W01/M0）。

流程：起服务端(WSS+SQLite) → ping → 负向握手(不信任证书必须被拒) →
tx×5 → balance/receipts → kill -9 强杀 → 重启同库 → 余额/收据必须都在 →
重放同 req_id 必须命中去重 → 汇总耗时证据。
产物：.zcode/m0/run/ 下的服务端日志与结果 JSON。
"""

import json
import os
import socket
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "E:/其他/chorme_download/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe"
RUN_DIR = os.path.join(REPO, ".zcode", "m0", "run")
CERT = os.path.join(REPO, "server", "secrets", "farm_server.crt")
KEY = os.path.join(REPO, "server", "secrets", "farm_server.key")
PORT = 31971
URL = "wss://127.0.0.1:%d" % PORT

results = []
server_proc = None
server_log = None


def out(line):
    print(line, flush=True)


def record(name, ok, detail):
    results.append({"name": name, "ok": bool(ok), "detail": detail})
    out("%s %s | %s" % ("PASS" if ok else "FAIL", name, detail))


def start_server(db_path, tag):
    global server_proc, server_log
    log_path = os.path.join(RUN_DIR, "server_%s.log" % tag)
    server_log = open(log_path, "wb")
    cmd = [
        GODOT, "--headless", "--path", ".", "--",
        "--server", "--port", str(PORT), "--db", db_path, "--cert", CERT, "--key", KEY,
        "--bind", "127.0.0.1", "--tag", tag,
    ]
    server_proc = subprocess.Popen(cmd, cwd=REPO, stdout=server_log, stderr=subprocess.STDOUT)
    deadline = time.time() + 40
    while time.time() < deadline:
        if server_proc.poll() is not None:
            server_log.flush()
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                out("--- server %s 提前退出，日志:\n%s" % (tag, f.read()[-2000:]))
            return False
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=1):
                return True
        except OSError:
            time.sleep(0.3)
    out("server %s 启动超时" % tag)
    return False


def kill_server():
    global server_proc
    if server_proc is None:
        return
    pid = server_proc.pid
    subprocess.call(["taskkill", "/F", "/T", "/PID", str(pid)],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        server_proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        pass
    server_proc = None
    if server_log:
        server_log.flush()


def probe(extra_args, timeout=30):
    """跑一次客户端探针，返回 (rc, M0-RESULT dict or None, 输出)。"""
    cmd = [GODOT, "--headless", "--path", ".", "--script", "res://tests/m0_wss_probe.gd", "--",
           "--url", URL, "--step", "x", "--timeout-ms", "8000"] + extra_args
    try:
        p = subprocess.run(cmd, cwd=REPO, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, None, "probe timeout"
    text = (p.stdout + p.stderr).decode("utf-8", "replace")
    payload = None
    for line in text.splitlines():
        if line.startswith("M0-RESULT "):
            payload = json.loads(line[len("M0-RESULT "):])
    return p.returncode, payload, text


def expect(name, extra_args, want_rc=0, want=None):
    rc, payload, text = probe(extra_args)
    ok = rc == want_rc and (want is None or (payload is not None and _subset(payload, want)))
    fails = [ln for ln in text.splitlines() if ln.startswith("M0-FAIL")]
    detail = "rc=%d %s" % (rc, json.dumps(payload, ensure_ascii=False) if payload
                           else ("; ".join(fails) or text.strip()[-160:]))
    record(name, ok, detail)
    return payload if ok else None


def _subset(payload, want):
    for k, v in want.items():
        if payload.get(k) != v:
            return False
    return True


def main():
    os.makedirs(RUN_DIR, exist_ok=True)
    db_path = os.path.join(RUN_DIR, "m0.db")
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(db_path + suffix)
        except OSError:
            pass

    if not os.path.exists(CERT):
        record("前置：证书存在", False, CERT)
        return finish(1)
    record("前置：证书存在", True, CERT)

    if not start_server(db_path, "a"):
        record("服务端启动(WSS 监听+SQLite WAL)", False, "见上方日志")
        return finish(1)
    record("服务端启动(WSS 监听+SQLite WAL)", True, "port=%d" % PORT)

    expect("ping/pong", ["--step", "ping", "--cert", CERT])
    expect("负向：不信任证书必须握手失败", ["--step", "handshake_fail", "--cert", "-"], want_rc=0,
           want={"outcome": "rejected_as_expected"})
    tx = expect("tx×5", ["--step", "tx", "--cert", CERT, "--count", "5", "--delta", "10", "--req-prefix", "r"],
                want={"count": 5, "final_balance": 50})
    expect("balance=50", ["--step", "balance", "--cert", CERT], want={"value": 50})
    expect("receipts=5", ["--step", "receipts", "--cert", CERT], want={"count": 5})
    expect("malformed 包后服务存活", ["--step", "malformed", "--cert", CERT])

    kill_server()
    record("kill -9 强杀服务端", True, "taskkill /F /T")

    if not start_server(db_path, "b"):
        record("强杀后重启", False, "见上方日志")
        return finish(1)
    record("强杀后重启", True, "同库重开")

    expect("强杀后 balance=50（已提交事务未丢）", ["--step", "balance", "--cert", CERT], want={"value": 50})
    expect("强杀后 receipts=5（收据齐全）", ["--step", "receipts", "--cert", CERT], want={"count": 5})
    expect("重放 5 个原 req_id 全部命中去重（S02 雏形）",
           ["--step", "tx_replay", "--cert", CERT, "--count", "5", "--delta", "10", "--req-prefix", "r"],
           want={"dup_hits": 5, "final_balance": 50})
    expect("去重后 balance 仍=50", ["--step", "balance", "--cert", CERT], want={"value": 50})

    kill_server()
    return finish(0)


def finish(code):
    if server_proc is not None:
        kill_server()
    if server_log:
        server_log.close()
    ok_count = sum(1 for r in results if r["ok"])
    out("")
    out("==== M0 本地验证：%d/%d 项通过 ====" % (ok_count, len(results)))
    with open(os.path.join(RUN_DIR, "m0_results.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    out("结果已写入 .zcode/m0/run/m0_results.json")
    failed = [r for r in results if not r["ok"]]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
