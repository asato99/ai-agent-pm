# クロスプラットフォーム開発環境セットアップガイド

AI Agent PM の MCP サーバーおよび REST サーバーを macOS 以外の環境（Windows / Linux）で起動するための手順書です。

---

## 目次

1. [アーキテクチャ概要](#アーキテクチャ概要)
2. [Windows (WSL2) セットアップ](#windows-wsl2-セットアップ)
3. [Linux セットアップ](#linux-セットアップ)
4. [開発サーバーの起動](#開発サーバーの起動)
5. [macOS との違い](#macos-との違い)
6. [トラブルシューティング](#トラブルシューティング)

---

## アーキテクチャ概要

### コンポーネント構成

```
┌─────────────────────────────────────────────────┐
│  ブラウザ (Windows / macOS / Linux)              │
│  http://localhost:5173                           │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Web UI (Vite dev server)                        │
│  Node.js / React  ── port 5173                   │
└──────────────────┬──────────────────────────────┘
                   │ API proxy
┌──────────────────▼──────────────────────────────┐
│  REST Server (Swift)                             │
│  Hummingbird HTTP ── port 8080                   │
├──────────────────────────────────────────────────┤
│  MCP Server (Swift)                              │
│  JSON-RPC over Unix Socket / HTTP                │
├──────────────────────────────────────────────────┤
│  SQLite Database                                 │
│  pm.db                                           │
└──────────────────────────────────────────────────┘
```

### プラットフォーム対応状況

| コンポーネント | macOS | Linux (WSL2) | Windows ネイティブ |
|--------------|-------|-------------|------------------|
| GUI アプリ (SwiftUI) | ✅ | ❌ | ❌ |
| REST Server | ✅ | ✅ | WSL2 経由 |
| MCP Server | ✅ | ✅ | WSL2 経由 |
| Coordinator (Python) | ✅ | ✅ | ✅ |
| Web UI (React) | ✅ | ✅ | ✅ |

> **Note**: Swift バイナリは Windows ネイティブでは動作しません。Windows では WSL2 を経由して Linux 上で実行します。

---

## Windows (WSL2) セットアップ

### 前提条件

- Windows 10 version 2004 以降、または Windows 11
- 管理者権限

### Step 1: WSL2 の有効化

PowerShell を管理者として開き、以下を実行:

```powershell
wsl --install
```

再起動後、Ubuntu が自動的にインストールされます。既に WSL2 が有効な場合はスキップしてください。

```powershell
# 確認
wsl --version
wsl --list --verbose
```

### Step 2: プロジェクトの準備

WSL2 内で作業する方法は2つあります:

**方法 A: WSL2 内にクローン（推奨）**

```bash
# WSL2 (Ubuntu) ターミナルで実行
cd ~
git clone <リポジトリURL> ai-agent-pm
cd ai-agent-pm
```

> WSL2 のファイルシステム内にクローンすると、I/O パフォーマンスが大幅に向上します。

**方法 B: Windows 側のファイルを参照**

```bash
# Windows の C:\Users\<ユーザー名>\projects\ai-agent-pm を使う場合
cd /mnt/c/Users/<ユーザー名>/projects/ai-agent-pm
```

> この方法は I/O が遅くなるため、ビルド時間が長くなる可能性があります。

### Step 3: 自動セットアップ

```bash
cd ai-agent-pm
chmod +x scripts/cross-platform/setup-wsl2.sh
./scripts/cross-platform/setup-wsl2.sh
```

このスクリプトは以下をインストール・設定します:

| 項目 | 内容 |
|------|------|
| システムパッケージ | curl, git, sqlite3, build-essential, clang, libicu-dev 等 |
| Swift | swiftly 経由で Swift 5.10.1 |
| Node.js | nvm 経由で LTS 版 |
| Python | pip 依存パッケージ (runner) |
| Web UI | npm install |
| Swift バイナリ | mcp-server-pm, rest-server-pm のリリースビルド |
| データディレクトリ | `~/.local/share/AIAgentPM/` |

### Step 4: サーバー起動

セットアップ完了後、以下のいずれかの方法で起動できます。

**方法 1: WSL2 ターミナルから直接**

```bash
./scripts/cross-platform/start-dev.sh
```

**方法 2: Windows コマンドプロンプトから**

```cmd
cd C:\Users\<ユーザー名>\projects\ai-agent-pm\scripts\cross-platform
start-dev.bat
```

**方法 3: PowerShell から**

```powershell
cd C:\Users\<ユーザー名>\projects\ai-agent-pm\scripts\cross-platform
.\start-dev.ps1
```

### Step 5: ブラウザでアクセス

Windows 側のブラウザで以下を開きます:

```
http://localhost:5173
```

> WSL2 は自動的に Windows 側にポートフォワーディングするため、特別な設定は不要です。

---

## Linux セットアップ

Ubuntu / Debian 系ディストリビューションを想定しています。

### 手動セットアップ

#### 1. Swift のインストール

```bash
# swiftly を使用（公式推奨）
curl -L https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
source ~/.local/share/swiftly/env.sh
swiftly install 5.10.1
```

または [swift.org](https://www.swift.org/install/) からダウンロード。

#### 2. Node.js のインストール

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc
nvm install --lts
```

#### 3. ビルドと起動

```bash
cd ai-agent-pm

# Swift サーバーのビルド
swift build -c release --product mcp-server-pm
swift build -c release --product rest-server-pm

# Web UI 依存パッケージ
cd web-ui && npm install && cd ..

# 起動
./scripts/cross-platform/start-dev.sh
```

---

## 開発サーバーの起動

### 起動スクリプトのオプション

```bash
./scripts/cross-platform/start-dev.sh [オプション]
```

| オプション | 説明 | デフォルト |
|-----------|------|----------|
| `--port <port>` | REST API ポート | 8080 |
| `--db <path>` | データベースファイルパス | プラットフォーム依存 |
| `--no-webui` | Web UI を起動しない | (起動する) |
| `--webui-port <port>` | Web UI ポート | 5173 |
| `-h, --help` | ヘルプ表示 | - |

### PowerShell 版のオプション

```powershell
.\start-dev.ps1 [-Port <port>] [-DbPath <path>] [-NoWebUI] [-WebUIPort <port>] [-Help]
```

### 使用例

```bash
# カスタムポートで起動
./start-dev.sh --port 8085

# テスト用の一時DBで起動
./start-dev.sh --db /tmp/test-aiagentpm.db

# REST API のみ起動（Web UI なし）
./start-dev.sh --no-webui
```

### 起動されるプロセス

| プロセス | ポート | 説明 |
|---------|-------|------|
| REST Server | 8080 | Swift HTTP サーバー (Hummingbird) |
| Web UI | 5173 | Vite 開発サーバー (React) |

### 停止方法

`Ctrl+C` で全プロセスが停止します。

---

## macOS との違い

### データ格納パス

| 項目 | macOS | Linux / WSL2 |
|------|-------|-------------|
| データベース | `~/Library/Application Support/AIAgentPM/pm.db` | `~/.local/share/AIAgentPM/pm.db` |
| ログ | `~/Library/Application Support/AIAgentPM/` | `~/.local/share/AIAgentPM/` |
| ポート設定 | `~/Library/Application Support/AIAgentPM/webserver-port` | `~/.local/share/AIAgentPM/webserver-port` |

> 環境変数 `AIAGENTPM_DB_PATH` を設定すると、上記のデフォルトパスを上書きできます。

### ポート設定の優先順位

| 優先度 | macOS | Linux / WSL2 |
|-------|-------|-------------|
| 1 | 環境変数 `AIAGENTPM_WEBSERVER_PORT` | 環境変数 `AIAGENTPM_WEBSERVER_PORT` |
| 2 | UserDefaults | *(なし)* |
| 3 | デフォルト値 (8080) | デフォルト値 (8080) |

> Linux では UserDefaults が利用できないため、環境変数またはデフォルト値が使用されます。

### ビルドシステム

| 項目 | macOS | Linux / WSL2 |
|------|-------|-------------|
| ビルドツール | Xcode (project.yml) または SPM | SPM のみ |
| ビルドコマンド | `xcodebuild` または `swift build` | `swift build` |
| バイナリ出力先 | `DerivedData/` または `.build/` | `.build/` |
| GUI アプリ | ビルド可能 | ビルド不可 |

### ビルドコマンド（SPM）

```bash
# MCP Server のビルド
swift build -c release --product mcp-server-pm

# REST Server のビルド
swift build -c release --product rest-server-pm

# バイナリの場所
ls -la .build/release/mcp-server-pm
ls -la .build/release/rest-server-pm
```

---

## トラブルシューティング

### Swift のビルドが失敗する

**症状**: `swift build` 実行時にコンパイルエラー

```bash
# 必要なシステムパッケージを確認
sudo apt-get install -y clang libicu-dev libcurl4-openssl-dev libssl-dev libxml2-dev libsqlite3-dev

# Swift バージョンを確認（5.9 以上が必要）
swift --version

# クリーンビルド
swift package clean
swift build -c release --product rest-server-pm
```

### WSL2 でポートにアクセスできない

**症状**: Windows ブラウザから `localhost:5173` にアクセスできない

```powershell
# WSL2 の IP アドレスを確認
wsl hostname -I

# その IP でアクセスを試す
# 例: http://172.xx.xx.xx:5173
```

最近の WSL2 では `localhost` が自動的にフォワーディングされますが、古いバージョンでは手動設定が必要な場合があります:

```powershell
# ポートフォワーディングを手動で設定
netsh interface portproxy add v4tov4 listenport=5173 listenaddress=0.0.0.0 connectport=5173 connectaddress=$(wsl hostname -I | ForEach-Object { $_.Trim() })
```

### データベースが見つからない

**症状**: `Error: Database not found`

```bash
# データベースを初期化
AIAGENTPM_DB_PATH=/tmp/test.db .build/release/mcp-server-pm setup

# 起動時にパスを指定
./scripts/cross-platform/start-dev.sh --db /tmp/test.db
```

### Node.js / npm が見つからない

**症状**: `npm: command not found`

```bash
# nvm を再読み込み
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Node.js がインストールされているか確認
nvm list
nvm use --lts
```

### WSL2 のファイルシステムが遅い

Windows 側のファイル (`/mnt/c/...`) を使用している場合、I/O が遅くなります。

```bash
# WSL2 側にプロジェクトを移動
cp -r /mnt/c/Users/<ユーザー名>/projects/ai-agent-pm ~/ai-agent-pm
cd ~/ai-agent-pm
```

### REST Server が起動しない

```bash
# ログを確認
cat ~/.local/share/AIAgentPM/rest-server-*.log 2>/dev/null

# ポートが使用中でないか確認
lsof -i :8080
# または
ss -tlnp | grep 8080

# 別のポートで試す
./scripts/cross-platform/start-dev.sh --port 8085
```

---

## ファイル構成

```
scripts/cross-platform/
├── setup-wsl2.sh      # WSL2 環境セットアップ（初回のみ）
├── start-dev.sh       # 開発サーバー起動（macOS / Linux / WSL2 共通）
├── start-dev.bat      # Windows コマンドプロンプト用ラッパー
└── start-dev.ps1      # Windows PowerShell 用ラッパー
```

### 関連ファイル（クロスプラットフォーム対応で変更されたもの）

| ファイル | 変更内容 |
|---------|---------|
| `Package.swift` | SPM ビルド定義（Linux で `swift build` を可能に） |
| `Sources/Infrastructure/AppConfig.swift` | Linux 用パス (`~/.local/share/`) の条件分岐 |
| `Sources/MCPServer/App.swift` | `@main` 削除、エントリポイント分離 |
| `Sources/MCPServer/Transport/Transport.swift` | 型の公開範囲を `public` に変更 |
| `Sources/MCPServerEntry/main.swift` | SPM ビルド用エントリポイント |
