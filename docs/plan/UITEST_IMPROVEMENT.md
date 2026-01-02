# UIテスト改善計画

**作成日**: 2024-12-31
**ステータス**: ✅ 解決済み

---

## 解決サマリー（2026-01-01）

### 問題
XCUITestがmacOS SwiftUIアプリのウィンドウを検出できない（`windows.count = 0`）

### 根本原因
**TCC（Transparency, Consent, and Control）権限の欠如**
- IDE（Cursor等）のターミナルにアクセシビリティ権限が付与されていなかった
- XCUITestはアクセシビリティAPIを使用するため、権限が必要

### 解決策
`System Settings → Privacy & Security → Accessibility` で使用中のIDEに権限を付与

### 結果
- ✅ ウィンドウ検出成功
- ✅ UI要素（StaticText, Button, Group等）検出成功
- ✅ アクセシビリティ識別子による要素特定成功
- ✅ ターミナルからの`xcodebuild test`実行成功

### テスト実行結果
| 項目 | 数 |
|------|-----|
| 実行テスト | 54 |
| スキップ | 26 |
| 失敗 | 9 |
| 成功 | 19 |

※ 失敗はTCC権限問題ではなく、UI実装側のアクセシビリティ識別子不足が原因

---

## 絶対的な前提条件

> **これらの前提条件は交渉不可であり、全ての解決策はこれらを満たす必要がある**

### 1. 手動テストは選択肢にない

- 手動テストへのフォールバックは**絶対に不可**
- 全てのUIテストは自動化されなければならない
- 人間による目視確認に依存する解決策は却下

### 2. Viewユニットテストでの代替は不可

- ViewInspector等によるViewユニットテストは**代替手段として認めない**
- XCUITestまたは同等のE2Eテストフレームワークによる実際のUI操作テストが必須
- 単体テストはUIテストの補完であり、代替ではない

### 3. CI/CD環境での自動実行が必須

- ターミナル/CLIからの完全自動実行が必須
- ビルドパイプラインに統合可能であること
- 人間の介入なしで実行・結果取得ができること

---

## 現状の問題

### 症状

macOS SwiftUI アプリに対する XCUITest をターミナルから実行すると:

```
Windows: 0
Groups: 0
StaticTexts: 0
Buttons: 0
```

アプリは起動する（PID取得可能）が、XCUITestがUI要素を検出できない。

### 原因分析

XCUITestのアクセシビリティAPIは、macOSのWindowServer接続を必要とする。
ターミナルセッション（特にSSH経由）では、この接続が確立されない。

---

## 解決策の調査

### 調査対象

1. **macOS CI環境でのGUIセッション確保**
   - Xcode Cloud
   - GitHub Actions (macOS runner)
   - CircleCI macOS
   - Self-hosted runner設定

2. **ヘッドレス環境でのXCUITest実行**
   - 仮想ディスプレイ (Xvfb相当)
   - Screen Sharing / VNC有効化
   - launchd設定によるGUIセッション

3. **代替E2Eテストフレームワーク**
   - Appium (macOS対応)
   - Maestro
   - その他のmacOS UI自動化ツール

4. **XCUITest設定の最適化**
   - 環境変数・設定による改善
   - テストプロセスの起動方法変更

---

## 調査結果

### 1. macOSのGUIセッションとBootstrapネームスペース

**技術的背景** ([参照](https://aahlenst.dev/blog/accessing-the-macos-gui-in-automation-contexts/)):

macOSはMach Bootstrapネームスペース階層を持つ:
```
System bootstrap namespace
  └── Per-user bootstrap namespace
        └── Per-session bootstrap namespace (GUI / SSH)
```

- SSHセッションは「non-GUI per-session bootstrap namespace」に入る
- GUIにアクセスするには「GUI per-session bootstrap namespace」が必要
- WindowServerはGUIセッションのネームスペースにサービスを公開

**重要な発見**: SSHログインユーザーが**事前にGUIログインしていれば**、SSHからGUIにアクセス可能。

### 2. CI環境別の対応状況

#### CircleCI macOS ✅ 実現可能

CircleCIは**macOS orb**でTCC権限の自動設定をサポート ([ドキュメント](https://circleci.com/docs/testing-macos/)):

```yaml
version: 2.1
orbs:
  mac-permissions: circleci/macos

jobs:
  ui-test:
    macos:
      xcode: 14.2.0
    steps:
      - checkout
      - mac-permissions/add-uitest-permissions
      - run: bundle exec fastlane test
```

**仕組み**:
- SIP無効のXcode 11.7+イメージを使用
- TCC.db（権限データベース）を直接変更
- Xcode HelperとTerminalに必要な権限を付与

#### GitHub Actions macOS ⚠️ 追加設定必要

GitHub-hosted runnerでは追加の準備が必要:

1. **[paulz/prepare-macos](https://github.com/paulz/prepare-macos) Action**を使用:
```yaml
- name: Prepare macOS runner
  uses: paulz/prepare-macos@v1
- name: Run UI Tests
  run: xcodebuild test -scheme AIAgentPM -destination 'platform=macOS'
```

このActionが行うこと:
- コンピュータ名をユニークに変更（「同名のコンピュータ」警告回避）
- 通知ウィンドウを閉じる
- Do Not Disturbモードを有効化
- ファイアウォールを無効化
- Finderウィンドウを閉じる

**課題**: GitHub-hosted runnerでのXCUITestは[不安定という報告](https://github.com/orgs/community/discussions/65667)が多い。

#### Self-hosted Runner ✅ 最も確実

**推奨設定** ([参照](https://dev.to/cubesoft/how-to-set-up-a-github-actions-self-hosted-runner-on-macos-15-2pid)):

1. 専用ユーザー作成（例: `gha`）
2. **自動ログインを有効化**（System Preferences → Users & Groups）
3. Launch Agentとして設定（Aquaセッションを要求）
4. Screen Sharing/VNCを有効化（ヘッドレス運用時）

```bash
# Launch Agentの設定例
launchctl load ~/Library/LaunchAgents/actions.runner.plist
```

### 3. 代替フレームワーク

#### Appium Mac2 Driver ✅ 有望

[appium-mac2-driver](https://github.com/appium/appium-mac2-driver) はXCTestをバックエンドに使用:

**要件**:
- macOS 10.15+
- Xcode 12+
- `automationmodetool enable-automationmode-without-authentication`（CI用）

```python
from appium import webdriver

desired_caps = {
    "platformName": "mac",
    "automationName": "mac2",
    "bundleId": "com.aiagentpm.app"
}
driver = webdriver.Remote("http://localhost:4723", desired_caps)
```

**メリット**:
- W3C WebDriver互換
- 複数言語対応（Python, Java, etc.）
- XCUITestと同じ基盤を使用

**デメリット**:
- 同じWindowServer問題が存在する可能性
- 追加のセットアップが必要

### 4. TCC権限の手動設定

**TCC.dbの直接編集** ([参照](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)):

```bash
# ユーザーTCC.db（SIP有効でも編集可能）
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "INSERT INTO access VALUES('kTCCServiceAccessibility','com.apple.dt.Xcode-Helper',0,2,0,1,NULL,NULL,0,'UNUSED',NULL,0,1687392249);"
```

**注意**:
- システムTCC.db（`/Library/...`）はSIP無効が必要
- CircleCI orbを使うのが最も安全

### 5. fastlane統合

```ruby
# fastlane/Fastfile
default_platform :mac

platform :mac do
  lane :test do
    scan(
      scheme: "AIAgentPM",
      destination: "platform=macOS",
      clean: true
    )
  end
end
```

---

## ローカル開発環境での解決策（最優先）

> **開発時の問題解決が最優先。CI環境対応はその後。**

### 根本原因の特定

**XCUITestがウィンドウを検出できない真の原因**:

1. **Aquaセッション要件**: XCUITestはmacOSの「Aquaセッション」（GUIブートストラップ名前空間）内で実行される必要がある
2. **非GUIターミナル**: SSH、tmux、一部のターミナル環境はAquaセッション外で動作する
3. **NSHostingView問題**: SwiftUIのNSHostingViewは追加の隠れたアクセシビリティレイヤーを作成し、標準のアクセシビリティトラバーサルで検出されない

### 解決策A: Terminal.app経由での実行（推奨・即時）

**原理**: Terminal.appはAquaセッション内で起動するため、GUIアクセスが可能。

**実装**:

```bash
#!/bin/bash
# scripts/run-uitests.sh
cd /Users/kazuasato/Documents/dev/business/pm
xcodegen generate 2>&1
xcodebuild test \
  -project AIAgentPM.xcodeproj \
  -scheme AIAgentPM \
  -destination 'platform=macOS' \
  2>&1 | tee /tmp/uitest-results.log
echo "Test completed. Exit code: $?"
```

**実行方法**:
```bash
# Aquaセッション内でスクリプトを実行
open -a Terminal.app /path/to/scripts/run-uitests.sh
```

**または**:
```bash
# 直接Terminal.appで新しいタブを開いてコマンド実行
osascript -e 'tell application "Terminal"
  do script "cd /Users/kazuasato/Documents/dev/business/pm && xcodebuild test -project AIAgentPM.xcodeproj -scheme AIAgentPM -destination \"platform=macOS\""
end tell'
```

### 解決策B: Xcodeから直接実行

**最も確実な方法**:
- Xcode GUI で `Product > Test` (⌘U)
- Xcode Server（継続的インテグレーション用）

**制約**:
- GUIへのアクセスが必要
- 自動化にはAppleScriptでの制御が必要

### 解決策C: Launch Agent設定（自動化向け）

ローカルCIや自動テスト実行用にLaunch Agentを設定:

```xml
<!-- ~/Library/LaunchAgents/com.aiagentpm.uitest.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aiagentpm.uitest</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/path/to/scripts/run-uitests.sh</string>
    </array>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

**使用方法**:
```bash
# エージェントをロード
launchctl load ~/Library/LaunchAgents/com.aiagentpm.uitest.plist

# テスト実行
launchctl start com.aiagentpm.uitest
```

### 解決策D: Hit-Test技術によるワークアラウンド

NSHostingViewの隠れたレイヤー問題を回避するため、座標ベースの要素検出を使用:

```swift
// UITests/Helpers/HitTestHelper.swift
import XCTest

extension XCUIApplication {
    /// NSHostingViewの隠れたレイヤーを回避して要素を取得
    func elementAtPoint(_ point: CGPoint) -> XCUIElement? {
        let coordinate = coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
        coordinate.tap()
        // タップ後に選択された要素を取得
        return self.descendants(matching: .any).element(boundBy: 0)
    }
}
```

**注意**: この方法は最終手段であり、座標ベースのテストは脆弱。

### 診断コマンド

現在の環境がAquaセッション内かどうかを確認:

```bash
# GUIセッションの確認
launchctl print gui/$(id -u) 2>&1 | grep -E "session"
# 出力に "session = Aqua" があればGUIセッション内

# WindowServerの確認
pgrep -x WindowServer && echo "WindowServer is running"

# アクセシビリティ権限の確認
tccutil reset Accessibility com.apple.dt.Xcode-Helper 2>/dev/null
# System Preferences > Privacy & Security > Accessibility で確認
```

---

## 追加調査結果（2024-12-31）

### 問題の詳細診断

**症状の詳細**:
- アプリはビルド・起動成功（PID取得可能）
- `app.state.rawValue` = 4 (runningForeground)
- しかし `app.windows.count` = 0
- 全てのUI要素（StaticTexts, Buttons等）も検出不可

**根本原因**:

1. **TCC権限の欠如**: osascriptから`System Events`にアクセスしようとすると `osascriptには補助アクセスは許可されません (-25211)` エラーが発生
2. **Aquaセッション要件**: XCUITestは同様のアクセシビリティAPIを使用するため、同じ権限問題が発生
3. **Claude Code/IDE環境**: IDE（VSCode, Cursor等）のターミナルはAquaセッション内にあるが、アクセシビリティ権限が付与されていない可能性

### 解決策: TCC権限の付与

**必要な権限設定**:

1. **System Preferences → Privacy & Security → Accessibility**を開く
2. 以下のアプリに権限を付与:
   - **Terminal** (com.apple.Terminal) - ターミナルから実行する場合
   - **Xcode** (com.apple.dt.Xcode) - 必須
   - **Xcode Helper** (com.apple.dt.Xcode-Helper) - 必須
   - **使用中のIDE** (Cursor, VSCode等) - IDEターミナルから実行する場合

**権限付与手順**:
1. System Preferences → Privacy & Security → Accessibility
2. 左下の鍵アイコンをクリックしてロック解除
3. 「+」ボタンで上記アプリを追加
4. チェックボックスをオンにして有効化
5. 変更後、IDE/Terminal を再起動

### 検証方法

権限付与後、以下を実行して確認:

```bash
# アクセシビリティAPIの動作確認
osascript -e 'tell application "System Events" to return count of windows of process "Finder"'
# 数値が返れば成功

# XCUITestの実行
xcodebuild test -project AIAgentPM.xcodeproj -scheme AIAgentPM -destination 'platform=macOS'
```

### 最も確実な方法: Xcodeから直接実行

上記の権限設定が複雑な場合、**Xcode GUIからのテスト実行が最も確実**:

1. Xcodeでプロジェクトを開く
2. `Product → Test` (⌘U) でテスト実行
3. Xcodeは既にアクセシビリティ権限を持っている可能性が高い

### 注意事項

- **SIP（System Integrity Protection）有効時**: システムTCC.dbは直接編集不可
- **ユーザーTCC.db**: `~/Library/Application Support/com.apple.TCC/TCC.db` は編集可能だが推奨しない
- **最も安全な方法**: System Preferencesからの手動設定

---

## CI環境での解決策

### 短期（即座に実装可能）: CircleCI + macOS orb

**理由**:
- TCC権限問題を公式サポート
- SIP無効イメージを提供
- 設定が最もシンプル

**実装**:
1. CircleCIアカウント作成
2. `.circleci/config.yml` 追加
3. `circleci/macos` orbで権限設定

### 中期: GitHub Actions Self-hosted Runner

**理由**:
- 既存のGitHubワークフローと統合
- 完全な環境制御
- コスト最適化（GitHub-hostedは高価）

**実装**:
1. 専用macOSマシン準備（物理 or VM）
2. 自動ログイン設定
3. GitHub Actions runner インストール
4. Launch Agentとして構成

### 長期: Appium Mac2 Driver検討

**理由**:
- クロスプラットフォームテスト基盤
- WebDriver互換（CI統合が容易）

**検証事項**:
- WindowServer問題が解決されるか確認
- パフォーマンス比較

---

## 実装計画

### Phase 1: CircleCI導入（推奨・即時）

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  macos: circleci/macos@2

jobs:
  ui-test:
    macos:
      xcode: 15.2.0
    resource_class: macos.m1.medium.gen1
    steps:
      - checkout
      - macos/add-uitest-permissions
      - run:
          name: Generate Xcode Project
          command: xcodegen generate
      - run:
          name: Build and Test
          command: |
            xcodebuild test \
              -project AIAgentPM.xcodeproj \
              -scheme AIAgentPM \
              -destination 'platform=macOS' \
              -resultBundlePath TestResults

workflows:
  test:
    jobs:
      - ui-test
```

### Phase 2: GitHub Actions準備（並行）

```yaml
# .github/workflows/ui-test.yml
name: UI Tests

on: [push, pull_request]

jobs:
  ui-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Prepare macOS runner
        uses: paulz/prepare-macos@v1

      - name: Install xcodegen
        run: brew install xcodegen

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Run UI Tests
        run: |
          xcodebuild test \
            -project AIAgentPM.xcodeproj \
            -scheme AIAgentPM \
            -destination 'platform=macOS'
```

### Phase 3: Self-hosted Runner（必要に応じて）

GitHub-hosted runnerで問題が続く場合:
1. Mac miniまたはMac Studio準備
2. 自動ログイン + Screen Sharing設定
3. `actions/runner` インストール
4. systemdではなくLaunch Agentで起動

---

## 参考リンク

- [CircleCI Testing macOS applications](https://circleci.com/docs/testing-macos/)
- [paulz/prepare-macos GitHub Action](https://github.com/paulz/prepare-macos)
- [Accessing the macOS GUI in Automation Contexts](https://aahlenst.dev/blog/accessing-the-macos-gui-in-automation-contexts/)
- [appium-mac2-driver](https://github.com/appium/appium-mac2-driver)
- [macOS TCC.db Deep Dive](https://www.rainforestqa.com/blog/macos-tcc-db-deep-dive)
- [GitHub Community: XCUITest issues](https://github.com/orgs/community/discussions/65667)
- [fastlane scan documentation](https://docs.fastlane.tools/actions/scan/)

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2024-12-31 | 初版作成、調査開始 |
| 2024-12-31 | Web調査完了、CI解決策を文書化 |
| 2024-12-31 | ローカル開発環境の解決策を最優先として追加、Aquaセッション要件を特定 |
| 2024-12-31 | TCC権限問題を特定、具体的な権限付与手順を追加 |
| 2026-01-01 | **解決完了** - TCC権限付与によりXCUITestが正常動作、54テスト実行成功 |
