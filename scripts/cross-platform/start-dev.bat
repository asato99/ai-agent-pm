@echo off
REM scripts/cross-platform/start-dev.bat
REM AI Agent PM - Windows コマンドプロンプトから WSL2 経由で開発環境を起動
REM
REM 使用方法:
REM   start-dev.bat                    デフォルト設定で起動
REM   start-dev.bat --port 8085        REST APIポートを指定
REM   start-dev.bat --db /tmp/test.db  DBパスを指定
REM   start-dev.bat --no-webui         Web UI なしで起動
REM
REM 前提条件:
REM   - WSL2 が有効化されていること
REM   - setup-wsl2.sh でセットアップ済みであること

echo === AI Agent PM - Windows Dev Environment ===
echo.

REM Check if WSL is available
wsl --status >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] WSL2 が見つかりません。
    echo WSL2 をインストールしてください: wsl --install
    exit /b 1
)

REM Get the script directory and convert to WSL path
set "SCRIPT_DIR=%~dp0"

REM Convert Windows path to WSL path
REM C:\Users\xxx\project\scripts\cross-platform\ -> /mnt/c/Users/xxx/project/scripts/cross-platform/
for /f "delims=" %%i in ('wsl wslpath -u "%SCRIPT_DIR%"') do set "WSL_SCRIPT_DIR=%%i"

echo WSL path: %WSL_SCRIPT_DIR%
echo.

REM Run the cross-platform start script via WSL
wsl bash -c "cd '%WSL_SCRIPT_DIR%' && chmod +x start-dev.sh && ./start-dev.sh %*"
