# 回归收集器（修复轮批次 D，Windows PowerShell 版）：跑全部 headless 规则/场景测试，
# 通过口径 = 退出码 0 且无"未预期 ERROR 行"（不止看 PASS 字符串）。
# 白名单：stage6_regression_smoke 的 3 条 JSON 故障注入属预期路径；
# d41_audio_smoke 的 1 条为无头 dummy 音频驱动退出期的"resources still in use"引擎级提示。
# 用法：powershell -ExecutionPolicy Bypass -File tests\run_regression.ps1 [-Godot <路径>]
param(
    [string]$Godot = "E:/其他/chorme_download/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")

$Whitelist = @{ "stage6_regression_smoke.gd" = 3; "d41_audio_smoke.gd" = 1 }

$total = 0
$failedTests = 0
$summary = @()
foreach ($path in Get-ChildItem tests -Filter *.gd | Sort-Object Name) {
    $name = $path.Name
    if ($name.StartsWith("capture_")) { continue }  # 截图类需真实窗口，另跑
    $total++
    $out = & $Godot --headless --path . --script "res://tests/$name" 2>&1 | Out-String
    $ec = $LASTEXITCODE
    $errors = ([regex]::Matches($out, "(?m)^ERROR|SCRIPT ERROR")).Count
    $allow = if ($Whitelist.ContainsKey($name)) { $Whitelist[$name] } else { 0 }
    $status = "ok"
    if ($ec -ne 0 -or $errors -gt $allow) {
        $status = "FAIL"
        $failedTests++
        Write-Output "---- $name (exit=$ec errors=$errors allow=$allow) ----"
        ($out -split "`n" | Select-String -Pattern "^ERROR|SCRIPT ERROR|FAIL:" | Select-Object -First 5)
    }
    $summary += "{0,-36} exit={1,-3} errors={2,-3} allow={3} {4}" -f $name, $ec, $errors, $allow, $status
}

Write-Output "================ 回归汇总 ================"
$summary | ForEach-Object { Write-Output $_ }
Write-Output "总计 $total 项，失败 $failedTests 项"
if ($failedTests -ne 0) { exit 1 }
Write-Output "REGRESSION_ALL_PASS"
