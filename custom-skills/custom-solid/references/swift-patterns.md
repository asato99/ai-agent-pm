# Swift/iOS/Clean Architecture における SOLID 適用パターン

## SRP in Swift

### ViewModel分割パターン

1つのViewModelが肥大化したら、責任ごとに子ViewModelに分割する:

```swift
// コーディネーター: 子ViewModel間の調整のみ
class RecordingViewModel: ObservableObject {
    let recordingStateVM: RecordingStateViewModel   // 録音状態管理
    let pitchDetectionVM: PitchDetectionViewModel   // ピッチ検出
    let subscriptionViewModel: SubscriptionViewModel // 課金状態
}

// 単一責任: 録音の状態とカウントダウンのみ
class RecordingStateViewModel: ObservableObject {
    @Published var recordingState: RecordingState
    @Published var countdownValue: Int
}

// 単一責任: ピッチ検出のみ
class PitchDetectionViewModel: ObservableObject {
    @Published var detectedPitch: DetectedPitch?
    @Published var pitchAccuracy: PitchAccuracy
}
```

**判断基準**: ViewModelの`@Published`プロパティが2つ以上の独立した関心事に属するなら分割を検討。

### Extension活用

1つのクラスに複数のProtocol準拠がある場合、extensionで責任を視覚的に分離する:

```swift
class ExerciseExecutionViewModel: ObservableObject { /* コアロジック */ }

extension ExerciseExecutionViewModel: ScalePlaybackDelegate { /* 再生コールバック */ }
extension ExerciseExecutionViewModel: CountdownDelegate { /* カウントダウン処理 */ }
```

ただしextensionは視覚的分離にすぎない。責任が本質的に異なるなら別クラスに分割する。

## OCP in Swift

### Protocol + 具象実装

新しい振る舞いの追加時に既存コードを変更しない構造:

```swift
// Domain層: 抽象（変更に閉じている）
protocol ScalePlayerProtocol {
    func loadScaleElements(_ elements: [ScaleElement], tempo: Tempo)
    func play(muted: Bool) async throws
    func stop() async
}

// Infrastructure層: 具象実装A（拡張に開いている）
class AVAudioPlayerScalePlayer: ScalePlayerProtocol { /* シンセサイザー */ }

// Infrastructure層: 具象実装B（既存コードを変更せずに追加）
class HybridScalePlayer: ScalePlayerProtocol { /* SF2 + シンセサイザー */ }
```

### @unknown default

Swift enumの網羅性チェックを活かしつつ、将来のcase追加に備える:

```swift
switch scaleType {
case .major: ...
case .minor: ...
@unknown default: fatalError("未対応のスケールタイプ: \(scaleType)")
}
```

`@unknown default`はコンパイラ警告を出すため、新しいcaseの対応漏れを防ぐ。

## LSP in Swift

### Protocol準拠の設計

準拠型を差し替えても呼び出し側が壊れない設計:

```swift
// UseCase は ScalePlayerProtocol に依存
class StartRecordingWithScaleUseCase {
    private let scalePlayer: ScalePlayerProtocol  // 具象型を知らない

    func execute(...) async throws {
        try await scalePlayer.play(muted: false)  // どの実装でも動く
    }
}
```

**違反の兆候**:
```swift
// BAD: 具象型チェック → LSP違反
func handlePlayer(_ player: ScalePlayerProtocol) {
    if let hybrid = player as? HybridScalePlayer {
        hybrid.reloadSoundFont()  // Protocol にないメソッド
    }
}
```

### 前提条件の明文化

Protocol のドキュメントコメントで事前条件・事後条件を明記する:

```swift
protocol AudioRecorderProtocol {
    /// 録音準備。録音URLを返す。
    /// - Precondition: マイク権限が許可済み
    /// - Postcondition: startRecording() を呼び出せる状態になる
    func prepareRecording() async throws -> URL
}
```

## ISP in Swift

### Protocol Composition（&構文）

大きなProtocolを分割し、必要な部分だけ組み合わせる:

```swift
// 分離された小さなProtocol
protocol Playable {
    func play() async throws
    func stop() async
    var isPlaying: Bool { get }
}

protocol Seekable {
    func seek(to time: TimeInterval) async
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
}

// 必要な部分だけ要求
func monitorPlayback(_ player: Playable & Seekable) { ... }
```

### 小さなProtocol設計

このプロジェクトでの実例:

```
AudioRecorderProtocol  - 録音のみ
AudioPlayerProtocol    - 再生のみ
ScalePlayerProtocol    - スケール再生のみ
PitchDetectorProtocol  - ピッチ検出のみ
```

AudioRecorderとAudioPlayerは別のProtocol。録音だけ必要な箇所でAudioPlayerのメソッドへの依存を強制しない。

**判断基準**: モックを作るとき、使わないメソッドの空実装が3つ以上あればProtocol分割を検討。

## DIP in Swift

### Repository Pattern

Domain層がProtocolを定義し、Infrastructure層が実装する:

```
Domain層（内側）                Infrastructure層（外側）
RecordingRepositoryProtocol  ←  FileRecordingRepository
AudioRecorderProtocol        ←  AVAudioRecorderWrapper
ScalePlayerProtocol          ←  HybridScalePlayer
```

ソースコードの依存方向が制御の流れと逆転する:
- **制御の流れ**: UseCase → Repository実装 → ファイルシステム
- **依存の方向**: UseCase → Protocol ← Repository実装

### DependencyContainer

DIコンテナで具象実装を1箇所に集約する:

```swift
class DependencyContainer {
    // Infrastructure（具象 → Protocol型で保持）
    private lazy var scalePlayer: ScalePlayerProtocol = {
        HybridScalePlayer(settingsRepository: audioSettingsRepository)
    }()

    // Application（Protocolを注入）
    private lazy var stopRecordingUseCase: StopRecordingUseCaseProtocol = {
        StopRecordingUseCase(
            audioRecorder: audioRecorder,
            scalePlayer: scalePlayer,
            recordingRepository: recordingRepository
        )
    }()

    // Factory Method（画面遷移時に生成）
    func makeExerciseExecutionViewModel(exercise: Exercise) -> ExerciseExecutionViewModel {
        ExerciseExecutionViewModel(
            exercise: exercise,
            recordingStateVM: RecordingStateViewModel(...),
            pitchDetectionVM: PitchDetectionViewModel(...)
        )
    }
}
```

### Protocol定義の配置ルール

| Protocol | 定義する層 | 理由 |
|----------|----------|------|
| RecordingRepositoryProtocol | Domain | ビジネスルールが要求するデータアクセス |
| AudioRecorderProtocol | Domain | ドメインロジックが必要とする録音機能 |
| LoggerProtocol | Domain | Application層が使うが実装は知らない |
| StartRecordingUseCaseProtocol | Application | Presentation層がUseCaseを抽象で参照 |

**鉄則**: Protocolは「使う側」の層に定義する。Infrastructure層にProtocolを定義してDomain層がimportするのはDIP違反。

## このプロジェクトでの依存構造

```
Presentation層
  ↓ 依存
Application層（UseCase）
  ↓ 依存
Domain層（Protocol定義 + Entity + Value Object）
  ↑ 実装（依存方向が逆転）
Infrastructure層（AVFoundation, FileSystem, UserDefaults）
```

DependencyContainer（App層）だけが全層を知り、具象実装をProtocolに結びつける。
