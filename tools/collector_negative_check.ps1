# 收集器负向检查（复核关闭轮 F-06 关闭标准）：在临时沙箱用 stub godot 验证
# run_regression.ps1 的三条判定——N1 白名单测试内的 SCRIPT ERROR 必须失败（不吞脚本异常）；
# N2 仅含预期模式错误时放行；N3 非白名单测试的意外 ERROR 必须失败。全程不碰项目本体。
# 用法：powershell -ExecutionPolicy Bypass -File tools\collector_negative_check.ps1
param(
    [string]$Collector = ""
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if ($Collector -eq "") { $Collector = Join-Path $repo "tests\run_regression.ps1" }

$JSON_LINES = @(
    "ERROR: Parse JSON failed. Error at line 0: Unterminated string",
    "ERROR: Parse JSON failed. Error at line 0: Unterminated string",
    "ERROR: Parse JSON failed. Error at line 0: Expected 'true' 'false' or 'null' got 'not'"
)


function New-Sandbox {
    param([string[]]$Stage6Lines, [string[]]$CleanLines)
    $sb = Join-Path ([System.IO.Path]::GetTempPath()) ("collector_neg_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path (Join-Path $sb "tests") -Force | Out-Null
    Copy-Item $Collector (Join-Path $sb "tests\run_regression.ps1")
    New-Item -ItemType File -Path (Join-Path $sb "tests\stage6_regression_smoke.gd") | Out-Null
    New-Item -ItemType File -Path (Join-Path $sb "tests\aaa_clean_probe.gd") | Out-Null
    $stub = Join-Path $sb "stub_godot.cmd"
    $body = @("@echo off", "echo %* | findstr /C:`"stage6_regression_smoke.gd`" >nul")
    $body += "if %errorlevel%==0 ("
    foreach ($line in $Stage6Lines) { $body += "  echo $line" }
    $body += ") else ("
    foreach ($line in $CleanLines) { $body += "  echo $line" }
    $body += @( ")", "exit /b 0" )
    Set-Content -Path $stub -Value ($body -join "`r`n") -Encoding ASCII
    return @{ Sandbox = $sb; Stub = $stub }
}


function Invoke-Collector {
    param([string]$SandboxStub)
    $sandboxCollector = Join-Path (Split-Path -Parent $SandboxStub) "tests\run_regression.ps1"
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sandboxCollector -Godot $SandboxStub 2>&1 | Out-String
    return @{ Out = $out; Exit = $LASTEXITCODE }
}


function Remove-Sandbox {
    param([string]$Path)
    if (Test-Path $Path) { Remove-Item -Recurse -Force $Path | Out-Null }
}


$failed = $false

# N1：白名单测试内混入 1 条 SCRIPT ERROR → 收集器必须失败并点名该测试
$sb = New-Sandbox -Stage6Lines ($JSON_LINES + @("SCRIPT ERROR: Attempt to call function 'missing_func' in base 'Node'")) -CleanLines @("PASS")
try {
    $r = Invoke-Collector $sb.Stub
    $ok = ($r.Exit -ne 0) -and ($r.Out -match "stage6_regression_smoke") -and ($r.Out -match "SCRIPT ERROR")
    Write-Output ("  N1 白名单不吞 SCRIPT ERROR：" + $(if ($ok) { "ok（exit=" + $r.Exit + "）" } else { "FAIL（exit=" + $r.Exit + "）`n" + $r.Out }))
    if (-not $ok) { $failed = $true }
} finally { Remove-Sandbox $sb.Sandbox }

# N2：仅 3 条预期 JSON 模式错误 → 收集器通过
$sb = New-Sandbox -Stage6Lines $JSON_LINES -CleanLines @("PASS")
try {
    $r = Invoke-Collector $sb.Stub
    $ok = ($r.Exit -eq 0) -and ($r.Out -match "REGRESSION_ALL_PASS")
    Write-Output ("  N2 预期错误按内容放行：" + $(if ($ok) { "ok" } else { "FAIL（exit=" + $r.Exit + "）`n" + $r.Out }))
    if (-not $ok) { $failed = $true }
} finally { Remove-Sandbox $sb.Sandbox }

# N3：非白名单测试输出 1 条无关 ERROR → 收集器必须失败
$sb = New-Sandbox -Stage6Lines $JSON_LINES -CleanLines @("ERROR: something unrelated")
try {
    $r = Invoke-Collector $sb.Stub
    $ok = ($r.Exit -ne 0) -and ($r.Out -match "aaa_clean_probe")
    Write-Output ("  N3 非白名单意外 ERROR 失败：" + $(if ($ok) { "ok（exit=" + $r.Exit + "）" } else { "FAIL（exit=" + $r.Exit + "）`n" + $r.Out }))
    if (-not $ok) { $failed = $true }
} finally { Remove-Sandbox $sb.Sandbox }

if ($failed) {
    Write-Output "COLLECTOR_NEGATIVE_FAIL"
    exit 1
}
Write-Output "COLLECTOR_NEGATIVE_PASS"
