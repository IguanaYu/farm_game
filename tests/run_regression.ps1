# 回归收集器（复核关闭轮 F-06，Windows PowerShell 版）：跑全部 headless 规则/场景测试，
# 通过口径 = 退出码 0 且无"未预期 ERROR 行"（不止看 PASS 字符串）。
# 规则：任何 SCRIPT ERROR 一律失败；^ERROR 行按白名单模式（内容子串）匹配并限行数，
# 不匹配任何模式或超出上限都算失败。模式表与 run_regression.sh 逐字相同（防双轨漂移）。
# 用法：powershell -ExecutionPolicy Bypass -File tests\run_regression.ps1 [-Godot <路径>]
param(
    [string]$Godot = "E:/其他/chorme_download/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")

# 测试名 -> 预期引擎级 ERROR 的模式列表（仅"预期路径"放行；SCRIPT ERROR 永不放行）：
# - stage6：主档/备档主动损坏注入的 3 条 JSON 解析故障；
# - d41：无头 dummy 音频驱动退出期的"resources still in use"提示（成功播放过的流被驱动侧持有）；
# - d53：装载真实 main_menu/world 场景，退出期资源缓存同类提示 1 条；
# - d54：真实输入链路装载 main_menu/world 场景并播过 BGM，退出期同类提示 2 条（场景资源+音频流）。
$Whitelist = @{
    "stage6_regression_smoke.gd"   = @(@{ pattern = "Parse JSON failed"; left = 3 })
    "d41_audio_smoke.gd"           = @(@{ pattern = "resources still in use at exit"; left = 1 })
    "d53_login_panel_lifecycle.gd" = @(@{ pattern = "resources still in use at exit"; left = 1 })
    "d54_menu_live_input_smoke.gd" = @(@{ pattern = "resources still in use at exit"; left = 2 })
}

$total = 0
$failedTests = 0
$summary = @()
foreach ($path in Get-ChildItem tests -Filter *.gd | Sort-Object Name) {
    $name = $path.Name
    if ($name.StartsWith("capture_")) { continue }  # 截图类需真实窗口，另跑
    if ($name.StartsWith("m0_")) { continue }  # M0 探针需编排器起服务端，见 tools/m0_local_verify.py
    if ($name.StartsWith("m1_")) { continue }  # M1 公网探针需真实服务器与真实凭据
    $total++
    $out = & $Godot --headless --path . --script "res://tests/$name" 2>&1 | Out-String
    $ec = $LASTEXITCODE
    $status = "ok"
    $detail = ""
    $lines = ($out -split "`r?`n") | Where-Object { $_ -match "^ERROR|SCRIPT ERROR" }
    if ($ec -ne 0) { $status = "FAIL"; $detail = "exit=$ec" }
    # 每个测试重建白名单余量，避免跨测试泄漏
    $allowances = @()
    if ($Whitelist.ContainsKey($name)) {
        foreach ($a in $Whitelist[$name]) { $allowances += @{ pattern = $a.pattern; left = $a.left } }
    }
    foreach ($line in $lines) {
        if ($line -match "SCRIPT ERROR") {
            $status = "FAIL"
            if ($detail -eq "") { $detail = "SCRIPT ERROR（永不放行）" }
            continue
        }
        $matched = $false
        foreach ($a in $allowances) {
            if ($a.left -gt 0 -and $line.Contains($a.pattern)) {
                $a.left -= 1
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            $status = "FAIL"
            if ($detail -eq "") { $detail = "未预期 ERROR：$line" }
        }
    }
    if ($status -eq "FAIL") {
        $failedTests++
        Write-Output "---- $name ($detail) ----"
        ($out -split "`n" | Select-String -Pattern "^ERROR|SCRIPT ERROR|FAIL:" | Select-Object -First 5)
    }
    $summary += "{0,-36} exit={1,-3} errors={2,-3} {3}" -f $name, $ec, $lines.Count, $status
}

Write-Output "================ 回归汇总 ================"
$summary | ForEach-Object { Write-Output $_ }
Write-Output "总计 $total 项，失败 $failedTests 项"
if ($failedTests -ne 0) { exit 1 }
Write-Output "REGRESSION_ALL_PASS"
