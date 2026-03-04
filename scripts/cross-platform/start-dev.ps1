# scripts/cross-platform/start-dev.ps1
# AI Agent PM - PowerShell から WSL2 経由で開発環境を起動
#
# 使用方法:
#   .\start-dev.ps1                    # デフォルト設定で起動
#   .\start-dev.ps1 -Port 8085         # REST APIポートを指定
#   .\start-dev.ps1 -DbPath /tmp/t.db  # DBパスを指定
#   .\start-dev.ps1 -NoWebUI           # Web UI なしで起動
#
# 前提条件:
#   - WSL2 が有効化されていること
#   - setup-wsl2.sh でセットアップ済みであること

param(
    [int]$Port = 0,
    [string]$DbPath = "",
    [switch]$NoWebUI,
    [int]$WebUIPort = 0,
    [switch]$Help
)

if ($Help) {
    Write-Host "AI Agent PM - 開発環境起動 (WSL2経由)"
    Write-Host ""
    Write-Host "使用方法:"
    Write-Host "  .\start-dev.ps1 [オプション]"
    Write-Host ""
    Write-Host "オプション:"
    Write-Host "  -Port <port>       REST APIポート (デフォルト: 8080)"
    Write-Host "  -DbPath <path>     データベースパス (WSL内パス)"
    Write-Host "  -NoWebUI           Web UI を起動しない"
    Write-Host "  -WebUIPort <port>  Web UI ポート (デフォルト: 5173)"
    Write-Host "  -Help              このヘルプを表示"
    exit 0
}

Write-Host "=== AI Agent PM - Windows Dev Environment ===" -ForegroundColor Cyan
Write-Host ""

# Check WSL availability
try {
    $wslStatus = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "WSL not available"
    }
} catch {
    Write-Host "[ERROR] WSL2 が見つかりません。" -ForegroundColor Red
    Write-Host "WSL2 をインストールしてください: wsl --install"
    exit 1
}

# Convert script path to WSL path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WslScriptDir = (wsl wslpath -u ($ScriptDir -replace '\\', '/')).Trim()

Write-Host "WSL path: $WslScriptDir" -ForegroundColor Gray
Write-Host ""

# Build arguments for the bash script
$args = @()
if ($Port -gt 0) {
    $args += "--port"
    $args += $Port.ToString()
}
if ($DbPath -ne "") {
    $args += "--db"
    $args += $DbPath
}
if ($NoWebUI) {
    $args += "--no-webui"
}
if ($WebUIPort -gt 0) {
    $args += "--webui-port"
    $args += $WebUIPort.ToString()
}

$argsStr = $args -join " "

# Run via WSL
Write-Host "サーバーを起動中..." -ForegroundColor Yellow
Write-Host "Ctrl+C で停止" -ForegroundColor Yellow
Write-Host ""

wsl bash -c "cd '$WslScriptDir' && chmod +x start-dev.sh && ./start-dev.sh $argsStr"
