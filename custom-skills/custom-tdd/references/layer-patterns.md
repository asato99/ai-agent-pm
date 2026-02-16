# アーキテクチャ層別テストパターン

## Domain層

ビジネスルールと不変条件のテスト。外部依存なし。

### エンティティ

```swift
// 不変条件: IDは生成時に一意
func testRecording_hasUniqueId() {
    let r1 = Recording()
    let r2 = Recording()
    XCTAssertNotEqual(r1.id, r2.id)
}

// ビジネスルール: 時間は負にならない
func testDuration_rejectsNegativeValue() {
    XCTAssertNil(Duration(seconds: -1))
}
```

### 値オブジェクト

```swift
// 等価性: 同じ値なら等しい
func testRecordingId_equalityByValue() {
    let id1 = RecordingId(value: "abc")
    let id2 = RecordingId(value: "abc")
    XCTAssertEqual(id1, id2)
}
```

### ドメインロジック（計算・変換）

```swift
// 変換メソッド: すべての出力プロパティを検証
func testToDemoSettings_producesOneKeyOnly() {
    let part = ExercisePart(ascendingKeyCount: 3)
    let demo = part.toDemoScalePresetSettings()

    XCTAssertEqual(demo.ascendingKeyCount, 0)  // キー進行なし
    XCTAssertEqual(demo.descendingKeyCount, 0)
    XCTAssertEqual(demo.keyProgressionPattern, .ascendingOnly)
}

// 生成ロジック: 出力の個数と内容を検証
func testGenerateKeyRoots_withZeroAscending_returnsSingleRoot() {
    let settings = ScaleSettings(ascendingKeyCount: 0)
    let roots = settings.generateKeyRoots()
    XCTAssertEqual(roots.count, 1)
}
```

## Application層（ユースケース）

依存コンポーネント間の協調をテスト。モックを使用。

### ユースケース

```swift
// 正常系: 依存関係が正しく呼ばれる
func testStartRecording_callsRecorderAndRepository() async throws {
    let sut = StartRecordingUseCase(recorder: mockRecorder, repo: mockRepo)

    try await sut.execute(user: user, settings: settings)

    XCTAssertTrue(mockRecorder.startCalled)
    XCTAssertEqual(mockRepo.savedURL, expectedURL)
}

// 異常系: エラー伝播
func testStartRecording_whenRecorderFails_throwsError() async {
    mockRecorder.shouldFail = true
    let sut = StartRecordingUseCase(recorder: mockRecorder, repo: mockRepo)

    await XCTAssertThrowsError {
        try await sut.execute(user: user, settings: settings)
    }
}
```

### モック設計の原則

- モックは振る舞いの記録と制御に徹する
- テスト専用メソッドを製品クラスに追加しない
- モックが複雑になったら製品コードの設計を見直す

## Infrastructure層

外部システムとのデータマッピングをテスト。

```swift
// シリアライズ/デシリアライズの往復
func testExercise_roundTripsToJSON() throws {
    let original = Exercise(name: "テスト", parts: [part1, part2])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Exercise.self, from: data)

    XCTAssertEqual(decoded.name, original.name)
    XCTAssertEqual(decoded.parts.count, original.parts.count)
}

// ファイルパス生成
func testFileURL_containsPartId() {
    let url = DemoAudioFileManager.fileURL(for: "demo_partId.m4a")
    XCTAssertTrue(url.lastPathComponent.contains("partId"))
}
```

## Presentation層（ViewModel）

状態遷移とユーザーアクションのテスト。

```swift
// 状態遷移: アクション → 期待される状態
func testStartPractice_transitionsToCountdown() async {
    let sut = createSUT()

    await sut.startPractice()

    XCTAssertEqual(sut.executionState, .countdown)
}

// コールバック連携: 外部イベント → 状態更新
func testOnPlaybackCompleted_marksPracticeComplete() {
    let sut = createSUT()
    sut.executionState = .practicing

    sut.onScalePlaybackCompleted()

    XCTAssertEqual(sut.executionState, .partCompleted)
}

// DI接続: 依存が正しく注入されているか
func testDemoPlayback_usesInjectedAudioPlayer() async {
    let sut = createSUT(demoAudioPlayer: mockPlayer)
    sut.exercise = exerciseWithDemo

    await sut.startDemo()

    XCTAssertTrue(mockPlayer.playCalled)
}
```

## テストヘルパーの原則

- `createSUT()` ファクトリでテスト対象の生成を統一
- デフォルト引数でモックを注入、テストごとに必要な部分のみ上書き
- テストデータは各テスト内で明示的に構築（共有フィクスチャを避ける）
