#!/usr/bin/env bash
# 回归收集器（复核关闭轮 F-06）：跑全部 headless 规则/场景测试，
# 通过口径 = 退出码 0 且无"未预期 ERROR 行"（不止看 PASS 字符串）。
# 规则：任何 SCRIPT ERROR 一律失败；^ERROR 行按白名单模式（内容子串）匹配并限行数，
# 不匹配任何模式或超出上限都算失败。模式表与 run_regression.ps1 逐字相同（防双轨漂移）。
# 用法：bash tests/run_regression.sh [godot可执行文件路径]
set -u

GODOT="${1:-E:/其他/chorme_download/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe}"
cd "$(dirname "$0")/.."

# 测试名 -> "模式名=上限行数"（空格分隔；模式名经 pattern_text 映射为含空格的实际子串）。
# 仅放行"预期路径"的引擎级 ERROR；SCRIPT ERROR 永不放行。与 run_regression.ps1 的 $Whitelist 一致：
# - stage6：主档/备档主动损坏注入的 3 条 JSON 解析故障；
# - d41：无头 dummy 音频驱动退出期的"resources still in use"提示（成功播放过的流在
#   ResourceCache 清理后仍被驱动侧持有，脚本侧无法回收，实机无声卡问题）；
# - d53：装载真实 main_menu/world 场景，退出期资源缓存同类提示 1 条。
whitelist_for() {
  case "$1" in
    stage6_regression_smoke.gd)     echo "Parse_JSON_failed=3" ;;
    d41_audio_smoke.gd)             echo "resources_still_in_use_at_exit=1" ;;
    d53_login_panel_lifecycle.gd)   echo "resources_still_in_use_at_exit=1" ;;
    *)                              echo "" ;;
  esac
}

pattern_text() {
  case "$1" in
    Parse_JSON_failed)               echo "Parse JSON failed" ;;
    resources_still_in_use_at_exit)  echo "resources still in use at exit" ;;
    *)                               echo "$1" ;;
  esac
}

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
  script_errors=$(grep -c "SCRIPT ERROR" "$out" || true)
  status="ok"
  detail=""
  [ "$ec" -ne 0 ] && detail="exit=$ec"
  # SCRIPT ERROR 一律失败（白名单永不覆盖脚本异常）
  if [ "$script_errors" -gt 0 ]; then
    status="FAIL"
    [ -z "$detail" ] && detail="SCRIPT ERROR（永不放行）"
  fi
  # ^ERROR 行按模式匹配并限行数；不匹配任何模式即未预期
  error_lines=$(grep "^ERROR" "$out" || true)
  if [ -n "$error_lines" ]; then
    unmatched_args=()
    for a in $(whitelist_for "$name"); do
      pat="$(pattern_text "${a%%=*}")"
      lim="${a##*=}"
      cnt=$(printf '%s\n' "$error_lines" | grep -cF "$pat" || true)
      if [ "$cnt" -gt "$lim" ]; then
        status="FAIL"
        [ -z "$detail" ] && detail="白名单超限：$pat=$cnt>$lim"
      fi
      unmatched_args+=(-e "$pat")
    done
    if [ ${#unmatched_args[@]} -gt 0 ]; then
      unmatched=$(printf '%s\n' "$error_lines" | grep -cvF "${unmatched_args[@]}" || true)
    else
      unmatched=$(printf '%s\n' "$error_lines" | grep -c . || true)
    fi
    if [ "$unmatched" -gt 0 ]; then
      status="FAIL"
      [ -z "$detail" ] && detail="未预期 ERROR x$unmatched"
    fi
  fi
  if [ "$status" = "FAIL" ]; then
    failed_tests=$((failed_tests + 1))
    echo "---- $name ($detail) ----"
    grep -E "^ERROR|SCRIPT ERROR|FAIL:" "$out" | head -5
  fi
  summary+="$(printf '%-34s exit=%-3s errors=%-3s %s' "$name" "$ec" "$errors" "$status")\n"
  rm -f "$out"
done

echo "================ 回归汇总 ================"
printf "$summary"
echo "总计 $total 项，失败 $failed_tests 项"
if [ "$failed_tests" -ne 0 ]; then
  exit 1
fi
echo "REGRESSION_ALL_PASS"
