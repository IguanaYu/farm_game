#!/usr/bin/env bash
# 回归收集器（修复轮批次 D）：跑全部 headless 规则/场景测试，
# 通过口径 = 退出码 0 且无"未预期 ERROR 行"（不止看 PASS 字符串）。
# 白名单：stage6_regression_smoke 的 3 条 JSON 故障注入属预期路径；
# d41_audio_smoke 的 1 条为无头 dummy 音频驱动退出期的"resources still in use"引擎级提示
# （成功播放过的流在 ResourceCache 清理后仍被驱动侧持有，脚本侧无法回收，实机无声卡问题）。
# 用法：bash tests/run_regression.sh [godot可执行文件路径]
set -u

GODOT="${1:-E:/其他/chorme_download/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe}"
cd "$(dirname "$0")/.."

# 测试名 -> 允许的未预期 ERROR 行数（0 = 必须完全干净）
declare -A WHITELIST=(
  ["stage6_regression_smoke.gd"]=3
  ["d41_audio_smoke.gd"]=1
  # d53 装载真实 main_menu/world 场景做全链路冒烟，退出时引擎资源缓存报告 1 条（非功能错误）
  ["d53_login_panel_lifecycle.gd"]=1
)

total=0
failed_tests=0
summary=""
for path in tests/*.gd; do
  name="$(basename "$path")"
  case "$name" in
    capture_*) continue ;;  # 截图类需真实窗口，另跑
    m0_*) continue ;;  # M0 探针需编排器起服务端，见 tools/m0_local_verify.py
    m1_*) continue ;;  # M1 公网探针需真实服务器与真实凭据，见 docs/testing/Farm_M1_部署与公网自测_2026-10-03.md
  esac
  total=$((total + 1))
  out="$(mktemp)"
  ## 每项 8 分钟上限：脚本在 quit() 前崩溃会留下永不退出的场景循环，套件会挂死（R2 实测坑）。
  timeout 480 "$GODOT" --headless --path . --script "res://tests/$name" >"$out" 2>&1
  ec=$?
  errors=$(grep -cE "^ERROR|SCRIPT ERROR" "$out" || true)
  allow=${WHITELIST[$name]:-0}
  status="ok"
  if [ "$ec" -ne 0 ] || [ "$errors" -gt "$allow" ]; then
    status="FAIL"
    failed_tests=$((failed_tests + 1))
    echo "---- $name (exit=$ec errors=$errors allow=$allow) ----"
    grep -E "^ERROR|SCRIPT ERROR|FAIL:" "$out" | head -5
  fi
  summary+="$(printf '%-34s exit=%-3s errors=%-3s allow=%s %s' "$name" "$ec" "$errors" "$allow" "$status")\n"
  rm -f "$out"
done

echo "================ 回归汇总 ================"
printf "$summary"
echo "总计 $total 项，失败 $failed_tests 项"
if [ "$failed_tests" -ne 0 ]; then
  exit 1
fi
echo "REGRESSION_ALL_PASS"
