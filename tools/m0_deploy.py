#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""M0 公网部署与验证（【主要】规划 M0 收尾项）。

前置：
  1. SSH 密钥已装（SSH_PW=... python .zcode/m0/ssh_run.py install_key）。
  2. 腾讯云安全组已放行入站 TCP 31971（用户在控制台操作）。

用法：
  python tools/m0_deploy.py info      # 采集服务器环境信息（规划 §10.2 要求记录）
  python tools/m0_deploy.py deploy    # 上传导出包+证书，nohup 起服务端
  python tools/m0_deploy.py verify    # 本机连 wss://111.229.19.23:31971 跑探针
  python tools/m0_deploy.py kill9     # 远端 kill -9（配合 verify 做强退恢复复测）
  python tools/m0_deploy.py logs      # 拉服务端日志尾部
"""

import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = "E:/其他/chorme_download/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe"
SSH_RUN = os.path.join(REPO, ".zcode", "m0", "ssh_run.py")
HOST = "111.229.19.23"
PORT = 31971
URL = "wss://%s:%d" % (HOST, PORT)
REMOTE_DIR = "/opt/farm-m0"
CERT = os.path.join(REPO, "server", "secrets", "farm_server.crt")
KEY = os.path.join(REPO, "server", "secrets", "farm_server.key")
BUILD = os.path.join(REPO, "build", "farm_server_linux")


def sh(cmd, **kw):
    print("$ %s" % cmd if isinstance(cmd, str) else "$ %s" % " ".join(cmd))
    return subprocess.run(cmd, **kw)


def ssh(cmd, timeout=90):
    r = sh([sys.executable, SSH_RUN, "run", cmd, str(timeout)])
    return r.returncode


def scp_upload(local, remote):
    """用 paramiko 的 sftp 上传（避开本机无 scp/密钥口令问题）。"""
    code = (
        "import os,sys;import paramiko;"
        "c=paramiko.SSHClient();c.set_missing_host_key_policy(paramiko.AutoAddPolicy());"
        "c.connect('%s',username='ubuntu',key_filename=os.path.expanduser('~/.ssh/id_ed25519'),timeout=15);"
        "s=c.open_sftp();s.put(sys.argv[1],sys.argv[2]);s.close();c.close();print('uploaded')" % HOST
    )
    r = sh([sys.executable, "-c", code, local, remote])
    return r.returncode


def cmd_info():
    rc = ssh(
        "echo ===os; . /etc/os-release && echo $PRETTY_NAME; uname -m; "
        "echo ===cpu_mem; nproc; free -h | head -2; "
        "echo ===disk; df -h / | tail -1; "
        "echo ===python; python3 --version 2>&1 || true; "
        "echo ===net; curl -s --max-time 5 ifconfig.me || true; echo; "
        "ss -tln | grep -E '31970|31971' || echo 'no farm ports listening'; "
        "echo ===tz; timedatectl show -p Timezone -p NTPSynchronized 2>/dev/null || true"
    )
    return rc


def cmd_deploy():
    ssh("sudo mkdir -p %s && sudo chown ubuntu:ubuntu %s && echo dir_ok" % (REMOTE_DIR, REMOTE_DIR))
    ssh("pkill -9 -f '^\./farm_server' 2>/dev/null; true")
    for name in ("farm_server.x86_64", "farm_server.pck", "libgdsqlite.linux.template_release.x86_64.so"):
        if scp_upload(os.path.join(BUILD, name), "%s/%s" % (REMOTE_DIR, name)) != 0:
            print("上传失败: %s" % name)
            return 1
    scp_upload(CERT, "%s/farm_server.crt" % REMOTE_DIR)
    scp_upload(KEY, "%s/farm_server.key" % REMOTE_DIR)
    rc = ssh(
        "cd %s && chmod +x farm_server.x86_64 && "
        "nohup ./farm_server.x86_64 --headless -- --server "
        "--port %d --db %s/online.db --cert %s/farm_server.crt --key %s/farm_server.key "
        "--bind 0.0.0.0 --tag m0 > server.log 2>&1 < /dev/null & echo started_pid=$!" % (REMOTE_DIR, PORT, REMOTE_DIR, REMOTE_DIR, REMOTE_DIR)
    )
    if rc != 0:
        return rc
    import time
    time.sleep(6)
    return ssh("tail -5 %s/server.log; ss -tln | grep 31971 || echo PORT_NOT_LISTENING" % REMOTE_DIR)


def probe(step, extra=None, want_rc=0):
    cmd = [GODOT, "--headless", "--path", ".", "--script", "res://tests/m0_wss_probe.gd", "--",
           "--url", URL, "--cert", CERT, "--step", step, "--timeout-ms", "12000"]
    if extra:
        cmd += extra
    r = sh(cmd, capture_output=True, timeout=60)
    text = (r.stdout + r.stderr).decode("utf-8", "replace")
    for line in text.splitlines():
        if line.startswith("M0-") or line.startswith("SCRIPT ERROR"):
            print(line)
    ok = r.returncode == want_rc
    print("[%s] %s rc=%d" % ("PASS" if ok else "FAIL", step, r.returncode))
    return ok


def cmd_verify():
    ok = True
    ok &= probe("ping")
    ok &= probe("handshake_fail", ["--cert", "-"])
    ok &= probe("tx", ["--count", "5", "--delta", "7", "--req-prefix", "net1"])
    ok &= probe("balance")
    ok &= probe("receipts")
    print("==== 公网验证 %s ====" % ("ALL PASS" if ok else "有失败项"))
    return 0 if ok else 1


def cmd_kill9():
    return ssh("pkill -9 -f '^\./farm_server' && echo killed || echo not_running; sleep 1; "
               "cd %s && nohup ./farm_server.x86_64 --headless -- --server "
               "--port %d --db %s/online.db --cert %s/farm_server.crt --key %s/farm_server.key "
               "--bind 0.0.0.0 --tag m0b > server.log 2>&1 < /dev/null & echo restarted" % (REMOTE_DIR, PORT, REMOTE_DIR, REMOTE_DIR, REMOTE_DIR))


def cmd_logs():
    return ssh("tail -30 %s/server.log" % REMOTE_DIR)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "info"
    fn = {"info": cmd_info, "deploy": cmd_deploy, "verify": cmd_verify,
          "kill9": cmd_kill9, "logs": cmd_logs}.get(mode)
    if not fn:
        raise SystemExit("用法: python tools/m0_deploy.py info|deploy|verify|kill9|logs")
    sys.exit(fn())
