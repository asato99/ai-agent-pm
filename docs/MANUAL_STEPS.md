# AIAgentPM 手動作業手順書

自動化できない作業のみをまとめています。

---

## 前提: 自動化済みの作業

以下は自動化されているため、手動作業不要です：

```bash
# これだけで MCP サーバーとアプリがビルドされる
./scripts/build-release.sh
```

---

## 手動作業一覧

### 1. Apple Developer Program 登録

**必要な理由**: コード署名・公証に必須

1. https://developer.apple.com/programs/ にアクセス
2. 年間 $99 で登録
3. 「Developer ID Application」証明書を発行

**確認コマンド**:
```bash
security find-identity -v -p codesigning
```

---

### 2. Xcodeプロジェクト作成（アプリバンドル配布時のみ）

**必要な理由**: `.app` バンドル作成には Xcode プロジェクトが必要

1. Xcode → File → New → Project
2. macOS → App を選択
3. 設定:
   - Product Name: `AIAgentPM`
   - Interface: SwiftUI
   - Language: Swift
4. File → Add Package Dependencies → Add Local → `pm` ディレクトリを選択
5. `Sources/App` 内のファイルをプロジェクトに追加
6. `.build/release/mcp-server-pm` を Copy Bundle Resources に追加

---

### 3. コード署名

**必要な理由**: macOS Gatekeeper 対応

```bash
# アプリの署名
codesign --force --deep --sign "Developer ID Application: Your Name (TEAM_ID)" \
    AIAgentPM.app

# MCP サーバーの署名
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    dist/bin/mcp-server-pm
```

---

### 4. 公証 (Notarization)

**必要な理由**: macOS Catalina 以降で必須

```bash
# ZIP化
ditto -c -k --keepParent AIAgentPM.app AIAgentPM.zip

# 公証リクエスト
xcrun notarytool submit AIAgentPM.zip \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "TEAM_ID" \
    --wait

# ステープル
xcrun stapler staple AIAgentPM.app
```

**App-Specific Password 取得**: https://appleid.apple.com → セキュリティ → App用パスワード

---

### 5. DMG 作成

**必要な理由**: 配布用パッケージ

```bash
# create-dmg インストール
brew install create-dmg

# DMG 作成
create-dmg \
    --volname "AIAgentPM" \
    --window-size 600 400 \
    --icon "AIAgentPM.app" 175 190 \
    --app-drop-link 425 190 \
    "AIAgentPM-1.0.0.dmg" \
    "AIAgentPM.app"
```

---

## チェックリスト

| 作業 | 必須 | 完了 |
|------|:----:|:----:|
| Apple Developer 登録 | 配布時 | [ ] |
| Xcode プロジェクト作成 | .app配布時 | [ ] |
| コード署名 | 配布時 | [ ] |
| 公証 | 配布時 | [ ] |
| DMG 作成 | 配布時 | [ ] |

---

## 開発時のみの場合

配布せず開発・テスト目的なら、手動作業は **不要** です：

```bash
# ビルド
./scripts/build-release.sh

# インストール（ローカル）
./dist/install.sh

# Claude Code で使用可能
```
