# AIAgentPM セットアップガイド

このガイドでは、AIAgentPMをビルド・配布するための手順を説明します。

## 目次

1. [開発環境のセットアップ](#1-開発環境のセットアップ)
2. [CLIツールのビルドと配布](#2-cliツールのビルドと配布)
3. [macOSアプリのビルド](#3-macosアプリのビルド)
4. [コード署名と公証](#4-コード署名と公証)
5. [DMGの作成](#5-dmgの作成)
6. [Claude Codeとの連携設定](#6-claude-codeとの連携設定)

---

## 1. 開発環境のセットアップ

### 必要なツール

- **Xcode 15.0+** (macOS Sonoma以降推奨)
- **Swift 5.9+**
- **Homebrew** (オプション: ツールのインストール用)

### 依存関係の確認

```bash
# Swiftバージョン確認
swift --version

# Xcodeコマンドラインツール確認
xcode-select -p
```

### プロジェクトのクローン

```bash
git clone <repository-url>
cd pm
```

---

## 2. CLIツールのビルドと配布

### 自動ビルド (推奨)

```bash
# リリースビルドスクリプトを実行
./scripts/build-release.sh
```

このスクリプトは以下を実行します:
- MCP サーバー (`mcp-server-pm`) のリリースビルド
- 配布用ディレクトリ (`dist/`) の作成
- インストールスクリプトの生成

### 手動ビルド

```bash
# MCP サーバーのビルド
swift build -c release --product mcp-server-pm

# ビルド成果物の確認
ls -la .build/release/mcp-server-pm
```

### インストール

```bash
# ビルド後、インストールスクリプトを実行
./dist/install.sh

# または手動でコピー
sudo cp .build/release/mcp-server-pm /usr/local/bin/
```

---

## 3. macOSアプリのビルド

### 方法A: Swift Package Manager (開発用)

```bash
swift build -c release --product AIAgentPM
```

**注意**: SPMでビルドした場合、macOSアプリバンドル(.app)は生成されません。

### 方法B: Xcodeプロジェクトの作成 (配布用)

macOSアプリバンドルを作成するには、Xcodeプロジェクトが必要です。

#### Step 1: Xcodeプロジェクトの新規作成

1. Xcodeを開く
2. **File → New → Project**
3. **macOS → App** を選択
4. 以下の設定:
   - Product Name: `AIAgentPM`
   - Team: 開発者アカウント
   - Organization Identifier: `com.yourcompany`
   - Interface: **SwiftUI**
   - Language: **Swift**

#### Step 2: Swift Packageの追加

1. **File → Add Package Dependencies...**
2. **Add Local...** をクリック
3. `pm` ディレクトリを選択
4. 以下のターゲットを追加:
   - Domain
   - Infrastructure
   - UseCase
   - App (Sources/App内のファイル)

#### Step 3: ソースファイルの統合

既存の `Sources/App` ディレクトリの内容をXcodeプロジェクトに追加:

```
Sources/App/
├── AIAgentPMApp.swift        # エントリーポイント
├── Core/
│   ├── DependencyContainer/
│   ├── Navigation/
│   └── Extensions/
└── Features/
    ├── ProjectList/
    ├── TaskBoard/
    ├── TaskDetail/
    ├── AgentManagement/
    ├── Handoff/
    └── Settings/
```

#### Step 4: Info.plistの設定

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AIAgentPM</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
```

#### Step 5: MCPサーバーバイナリの埋め込み

1. `mcp-server-pm` バイナリをビルド
2. Xcodeプロジェクトに追加:
   - **File → Add Files to "AIAgentPM"...**
   - `.build/release/mcp-server-pm` を選択
   - **Copy items if needed** にチェック
   - **Add to targets: AIAgentPM** にチェック

3. **Build Phases** で確認:
   - **Copy Bundle Resources** に `mcp-server-pm` が含まれていること

---

## 4. コード署名と公証

### 前提条件

- **Apple Developer Program** への登録 (年間$99)
- **Developer ID Application** 証明書

### Step 1: 証明書の確認

```bash
# 利用可能な証明書を確認
security find-identity -v -p codesigning
```

### Step 2: Xcodeでの署名設定

1. プロジェクト設定を開く
2. **Signing & Capabilities** タブ
3. 以下を設定:
   - **Automatically manage signing**: チェック
   - **Team**: 開発者アカウント
   - **Signing Certificate**: Developer ID Application

### Step 3: コマンドラインでの署名 (オプション)

```bash
# アプリの署名
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
    AIAgentPM.app

# 署名の検証
codesign --verify --deep --strict AIAgentPM.app
```

### Step 4: 公証 (Notarization)

```bash
# アプリをZIP化
ditto -c -k --keepParent AIAgentPM.app AIAgentPM.zip

# 公証をリクエスト
xcrun notarytool submit AIAgentPM.zip \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "TEAM_ID" \
    --wait

# ステープル
xcrun stapler staple AIAgentPM.app
```

### Step 5: MCPサーバーバイナリの署名

```bash
# MCPサーバーの署名
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    mcp-server-pm

# 検証
codesign --verify --verbose mcp-server-pm
```

---

## 5. DMGの作成

### 方法A: Disk Utilityを使用

1. **Disk Utility** を開く
2. **File → New Image → Blank Image...**
3. 以下の設定:
   - Name: `AIAgentPM`
   - Size: 100 MB
   - Format: Mac OS Extended (Journaled)
   - Encryption: None
   - Partitions: Single partition - GUID
   - Image Format: read/write
4. マウントされたDMGに以下をコピー:
   - `AIAgentPM.app`
   - `Applications` へのシンボリックリンク
5. DMGを変換 (読み取り専用):
   ```bash
   hdiutil convert AIAgentPM-rw.dmg -format UDZO -o AIAgentPM.dmg
   ```

### 方法B: create-dmgツールを使用 (推奨)

```bash
# create-dmgのインストール
brew install create-dmg

# DMGの作成
create-dmg \
    --volname "AIAgentPM" \
    --volicon "icon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "AIAgentPM.app" 175 190 \
    --hide-extension "AIAgentPM.app" \
    --app-drop-link 425 190 \
    "AIAgentPM-1.0.0.dmg" \
    "dist/AIAgentPM.app"
```

### 方法C: スクリプトによる自動化

```bash
#!/bin/bash
# scripts/create-dmg.sh

APP_NAME="AIAgentPM"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
TEMP_DMG="${APP_NAME}-temp.dmg"

# 一時DMGを作成
hdiutil create -size 150m -fs HFS+ -volname "${APP_NAME}" "${TEMP_DMG}"

# マウント
hdiutil attach "${TEMP_DMG}" -mountpoint /Volumes/"${APP_NAME}"

# ファイルをコピー
cp -R "dist/${APP_NAME}.app" /Volumes/"${APP_NAME}"/
ln -s /Applications /Volumes/"${APP_NAME}"/Applications

# アンマウント
hdiutil detach /Volumes/"${APP_NAME}"

# 圧縮して最終DMGを作成
hdiutil convert "${TEMP_DMG}" -format UDZO -o "${DMG_NAME}"

# 一時ファイルを削除
rm "${TEMP_DMG}"

echo "Created: ${DMG_NAME}"
```

---

## 6. Claude Codeとの連携設定

### 設計原則

MCPサーバーは**ステートレス**に設計されています:
- 起動時は`--db`（データベースパス）のみ必要
- `--agent-id` や `--project-id` は**不要**
- 必要なIDはキック時のプロンプトで提供され、ツール呼び出し時に引数として渡される

### 自動設定 (アプリ内から)

1. AIAgentPMアプリを起動
2. **Settings** → **MCP Configuration** を開く
3. **Copy MCP Config** ボタンをクリック
4. Claude Code設定ファイルに貼り付け

### 手動設定

1. Claude Code設定ファイルを開く:
   ```bash
   nano ~/.claude/claude_desktop_config.json
   ```

2. 以下の設定を追加:
   ```json
   {
     "mcpServers": {
       "agent-pm": {
         "command": "/usr/local/bin/mcp-server-pm",
         "args": [
           "--db", "$HOME/Library/Application Support/AIAgentPM/pm.db"
         ]
       }
     }
   }
   ```

   **注意**: `--agent-id` や `--project-id` は不要です。これらはキック時にプロンプトで提供されます。

3. Claude Codeを再起動

### 設定の確認

```bash
# MCP サーバーの一覧を確認
claude --mcp-list

# テスト
# Claude Code内で以下のツールを呼び出し:
# mcp__agent-pm__list_agents
# mcp__agent-pm__list_projects
```

---

## トラブルシューティング

### ビルドエラー

**問題**: `Domain.Task` と `Swift.Task` の名前衝突
**解決**: 各ビューファイルで `private typealias AsyncTask = _Concurrency.Task` を使用

**問題**: `Agent` の初期化エラー
**解決**: `projectId` パラメータが必須。`Agent(id:, projectId:, name:, role:, type:)` の形式で初期化

### MCPサーバー

**問題**: MCPサーバーが認識されない
**解決**:
1. パスが正しいか確認
2. 実行権限を確認: `chmod +x /usr/local/bin/mcp-server-pm`
3. Claude Codeを再起動

**問題**: データベースエラー
**解決**:
1. ディレクトリの存在確認: `mkdir -p ~/Library/Application\ Support/AIAgentPM`
2. 書き込み権限の確認

### コード署名

**問題**: 署名が無効
**解決**:
1. 証明書が有効か確認
2. `--deep` オプションを使用
3. Gatekeeperをリセット: `sudo spctl --master-disable` (テスト時のみ)

---

## クイックリファレンス

### よく使うコマンド

```bash
# ビルド
swift build -c release --product mcp-server-pm
swift build -c release --product AIAgentPM

# テスト
swift test

# クリーン
swift package clean

# 署名確認
codesign --verify --deep --strict AIAgentPM.app

# MCPサーバー直接実行 (デバッグ)
.build/release/mcp-server-pm --db ./test.db
```

### ファイル配置

```
pm/
├── .build/release/           # ビルド成果物
│   ├── mcp-server-pm        # MCPサーバーバイナリ
│   └── AIAgentPM            # アプリバイナリ (SPM)
├── dist/                     # 配布用ファイル
│   ├── bin/
│   ├── docs/
│   ├── install.sh
│   └── claude-code-config.json
└── AIAgentPM.app/            # macOSアプリバンドル (Xcode)
```

---

## 更新履歴

- **v1.0.0** - 初期リリース
  - MCP サーバー実装
  - macOS アプリ (SwiftUI)
  - Claude Code連携
