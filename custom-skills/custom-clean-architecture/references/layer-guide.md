# このプロジェクトの層配置ガイド

## Domain層に置くもの

VocalisDomain Package / SubscriptionDomain Package に配置。

**Entity**: ビジネスの核となる概念。ライフサイクルとIDを持つ。
- Recording, Exercise, ExercisePart, ExerciseSession, ScaleSettings, ScalePreset, User

**Value Object**: 不変で等価性で比較される値。
- MIDINote, Duration, Tempo, RecordingId, ExerciseId, DetectedPitch, NotePattern, PitchFrame

**Domain Service**: Entity単体に属さないビジネスロジック。
- RecordingStatisticsCalculator, OctaveCorrectionService, VibratoAnalyzer, HighFrequencyAnalyzer

**Repository Interface / Service Interface**: 外部リソースへのアクセスを抽象化。
- RecordingRepositoryProtocol, AudioRecorderProtocol, ScalePlayerProtocol, LoggerProtocol, PitchDetectionStrategy

**判断基準**: 「AVFoundation、StoreKit、UserDefaults が消えても成り立つか？」
- Yes → Domain層
- No → Domain層ではない

**よくある誤り**:
- ファイルパス操作のユーティリティ → Infrastructure層（FileSystemに依存）
- JSON Codable準拠 → Domain Entityに付けて良い（Swift標準ライブラリはフレームワークではない）
- UIに便利な計算プロパティ → Presentation層のHelperかViewModel

## Application層に置くもの

`VocalisStudio/Application/` に配置。

**UseCase**: 1つのユーザー操作フローを調整する。複数のDomainオブジェクトとRepository Interfaceを組み合わせてビジネスシナリオを実現する。
- StartRecordingWithScaleUseCase, StopRecordingUseCase, SaveDemoRecordingUseCase, CreateExerciseUseCase

**Application Service**: ユースケース横断のアプリケーションレベルのポリシー。
- RecordingPolicyServiceImpl（録音制限の判定）, ScalePlaybackCoordinator（再生の調整）

**DTO（Data Transfer Object）**: 層間のデータ受け渡しに使う構造体。Domain Entityそのものではないが、UseCaseの結果を伝える。
- RecordingSession（UseCase → ViewModel）, StopRecordingResult

**判断基準**: 「ユーザーの操作フロー（ストーリー）を調整しているか？」
- Yes → Application層
- No → 別の層

**よくある誤り**:
- UseCaseにUIの表示ロジックを入れる → Presentation層
- UseCaseにAVFoundation呼び出しを直接書く → Infrastructure層
- 1つのUseCaseに複数の操作フローを詰め込む → UseCaseを分割

## Infrastructure層に置くもの

`VocalisStudio/Infrastructure/` に配置。

**Repository実装**: Domain層のRepository Interfaceの具象実装。
- FileRecordingRepository, UserDefaultsAudioSettingsRepository, UserDefaultsExerciseRepository

**Framework Wrapper**: iOS固有フレームワークの薄いラッパー。
- AVAudioRecorderWrapper, HybridScalePlayer, RealtimePitchDetector, CountdownSoundPlayer

**External Service**: 外部サービスとの統合。
- StoreKitSubscriptionRepository, RecordingUsageTracker

**分析エンジン**: アルゴリズムの具象実装。
- AudioFileAnalyzer, YINStrategy, PYINStrategy, FCPEStrategy

**ログ**: ログ出力の具象実装。
- FileLogger, OSLogAdapter

**判断基準**: 「具体的なフレームワーク（AVFoundation, StoreKit, UserDefaults）やシステムに依存するか？」
- Yes → Infrastructure層
- No → 別の層

**よくある誤り**:
- Infrastructure層にビジネスルールを書く → Domain層
- Repository実装がDomain Entityの不変条件を検証する → Domain Entity自身の責務
- Framework WrapperがUseCaseの役割を果たす → Application層に分離

## Presentation層に置くもの

`VocalisStudio/Presentation/` に配置。

**ViewModel**: UIの状態管理とユーザーアクションの処理。UseCaseを呼び出す。
- RecordingStateViewModel, ExerciseExecutionViewModel, PitchDetectionViewModel, SubscriptionViewModel

**View**: SwiftUI画面。Humble Objectとして最小限のロジックのみ持つ。
- RecordingView, ExerciseExecutionView, PaywallView, AnalysisView

**Component**: 再利用可能なUI部品。
- PitchBarView, SpectrogramRenderer, PitchGraphRenderer

**Helper / Theme**: UI固有のユーティリティと視覚的設定。
- PitchNameHelper, ColorPalette, Typography, ButtonStyles

**判断基準**: 「ユーザーの目に見える、または操作に直接関わるか？」
- Yes → Presentation層
- No → 別の層

## 判断フローチャート

新しいコードを書くとき、以下の順で判断する:

```
1. フレームワーク（AVFoundation, StoreKit, UIKit）に依存するか？
   ├─ Yes → Infrastructure層
   └─ No ↓

2. ユーザーに見える / 操作に関わるか？
   ├─ Yes → Presentation層（View or ViewModel）
   └─ No ↓

3. ユーザー操作フロー（ストーリー）の調整か？
   ├─ Yes → Application層（UseCase）
   └─ No ↓

4. ビジネスの概念・ルール・計算か？
   ├─ Yes → Domain層
   └─ No → 判断に迷う場合は下記参照
```

**迷ったときのヒューリスティクス**:
- テストを書くとき、モックが不要 → Domain層の可能性が高い
- テストを書くとき、AVFoundation等のモックが必要 → Infrastructure層の可能性
- 「この型はどのUseCaseからも使える」→ Domain層
- 「このロジックは特定の画面でしか使わない」→ Presentation層

## Swift Package分割の判断基準

**いつPackageに切り出すか**:
- 独立したドメイン境界を持ち、他のドメインと異なる変更理由を持つ場合
- ビルド時間の短縮が期待できる場合
- 依存関係の制約をコンパイラレベルで強制したい場合

**現在の分割**:
- `VocalisDomain`: 音声トレーニングのコアドメイン（Entity, Value Object, Service Interface）
- `SubscriptionDomain`: 課金ドメイン（SubscriptionStatus, SubscriptionTier, RecordingLimit）

**分割の理由**: 課金ルールと音声トレーニングロジックは異なるアクターの要求で変更される（SRP at package level）。Package.swiftの`dependencies`で依存方向を強制し、SubscriptionDomainがVocalisDomainに依存しない（循環依存の防止）。
