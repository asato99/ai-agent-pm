# XCUITest スクリーンショット取得ガイド

## 推奨方法: XCTAttachment + xcresulttool

XCUITestはサンドボックス環境で動作するため、ファイルシステムへの直接書き込みは制限される。
代わりに、XCTAttachmentでテスト結果に添付し、テスト後にCLIで抽出する。

### ステップ1: テストコードでスクリーンショットを添付

```swift
let screenshot = app.screenshot()
let attachment = XCTAttachment(screenshot: screenshot)
attachment.name = "descriptive_name"
attachment.lifetime = .keepAlways
add(attachment)
```

### ステップ2: テスト実行後にCLIで抽出

```bash
# xcresultのパスを取得
XCRESULT=$(ls -t ~/Library/Developer/Xcode/DerivedData/AIAgentPM-*/Logs/Test/*.xcresult | head -1)

# 添付ファイルをエクスポート
mkdir -p /tmp/attachments
xcrun xcresulttool export attachments \
  --path "$XCRESULT" \
  --output-path /tmp/attachments

# 確認
ls -la /tmp/attachments/
open /tmp/attachments/*.png
```

### オプション

```bash
# 失敗したテストの添付ファイルのみ
xcrun xcresulttool export attachments \
  --path "$XCRESULT" \
  --output-path /tmp/attachments \
  --only-failures
```

---

## 失敗するパターン（参考）

| 方法 | エラー |
|------|--------|
| `/tmp/`への直接書き込み | `Operation not permitted`（サンドボックス制限） |
| `~/Desktop/`への書き込み | サンドボックス内の別パスにリダイレクトされる |
| `FileManager.homeDirectoryForCurrentUser` | 実際のホームではなくコンテナ内パスを返す |

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2026-01-08 | 初版作成 |
