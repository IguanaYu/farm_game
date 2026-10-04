#!/usr/bin/env bash
# 收集器负向检查（复核关闭轮 F-06 关闭标准）：在临时沙箱用 stub godot 验证
# run_regression.sh 的三条判定——N1 白名单测试内的 SCRIPT ERROR 必须失败（不吞脚本异常）；
# N2 仅含预期模式错误时放行；N3 非白名单测试的意外 ERROR 必须失败。全程不碰项目本体。
# 用法：bash tools/collector_negative_check.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
COLLECTOR="${1:-$REPO/tests/run_regression.sh}"

JSON_LINES=(
  "ERROR: Parse JSON failed. Error at line 0: Unterminated string"
  "ERROR: Parse JSON failed. Error at line 0: Unterminated string"
  "ERROR: Parse JSON failed. Error at line 0: Expected 'true' 'false' or 'null' got 'not'"
)

# 生成沙箱：$1=目录 $2=stage6 输出文件 $3=clean 输出文件（各含逐行 echo 脚本）
make_sandbox() {
  local sb="$1" stage6_out="$2" clean_out="$3"
  mkdir -p "$sb/tests"
  cp "$COLLECTOR" "$sb/tests/run_regression.sh"
  touch "$sb/tests/stage6_regression_smoke.gd" "$sb/tests/aaa_clean_probe.gd"
  cat > "$sb/stub_godot.sh" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *stage6_regression_smoke.gd*)
STUB
  while IFS= read -r line; do echo "    echo \"$line\"" >> "$sb/stub_godot.sh"; done < "$stage6_out"
  echo "    ;;" >> "$sb/stub_godot.sh"
  echo "  *)" >> "$sb/stub_godot.sh"
  while IFS= read -r line; do echo "    echo \"$line\"" >> "$sb/stub_godot.sh"; done < "$clean_out"
  cat >> "$sb/stub_godot.sh" <<STUB
    ;;
esac
exit 0
STUB
  chmod +x "$sb/stub_godot.sh"
}

run_case() {
  local label="$1" stage6_file="$2" clean_file="$3" expect="$4" must_mention="$5"
  local sb
  sb="$(mktemp -d)"
  make_sandbox "$sb" "$stage6_file" "$clean_file"
  local out ec
  out="$(bash "$sb/tests/run_regression.sh" "$sb/stub_godot.sh" 2>&1)"
  ec=$?
  rm -rf "$sb"
  local ok=1
  if [ "$expect" = "fail" ]; then
    [ "$ec" -eq 0 ] && ok=0
  else
    [ "$ec" -ne 0 ] && ok=0
    printf '%s\n' "$out" | grep -q "REGRESSION_ALL_PASS" || ok=0
  fi
  if [ -n "$must_mention" ]; then
    printf '%s\n' "$out" | grep -q "$must_mention" || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    echo "  $label：ok（exit=$ec）"
  else
    echo "  $label：FAIL（exit=$ec）"
    printf '%s\n' "$out"
    FAILED=1
  fi
}

FAILED=0
TMP="$(mktemp -d)"
printf '%s\n' "${JSON_LINES[@]}" > "$TMP/json_only.txt"
printf '%s\n' "${JSON_LINES[@]}" "SCRIPT ERROR: Attempt to call function 'missing_func' in base 'Node'." > "$TMP/json_plus_script.txt"
printf 'PASS\n' > "$TMP/pass.txt"
printf 'ERROR: something unrelated\n' > "$TMP/unrelated.txt"

# N1：白名单测试内混入 1 条 SCRIPT ERROR → 收集器必须失败并点名该测试
run_case "N1 白名单不吞 SCRIPT ERROR" "$TMP/json_plus_script.txt" "$TMP/pass.txt" fail "SCRIPT ERROR"
# N2：仅 3 条预期 JSON 模式错误 → 收集器通过
run_case "N2 预期错误按内容放行" "$TMP/json_only.txt" "$TMP/pass.txt" pass ""
# N3：非白名单测试输出 1 条无关 ERROR → 收集器必须失败
run_case "N3 非白名单意外 ERROR 失败" "$TMP/json_only.txt" "$TMP/unrelated.txt" fail "aaa_clean_probe"

rm -rf "$TMP"
if [ "$FAILED" -ne 0 ]; then
  echo "COLLECTOR_NEGATIVE_FAIL"
  exit 1
fi
echo "COLLECTOR_NEGATIVE_PASS"
