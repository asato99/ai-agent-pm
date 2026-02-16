---
name: custom-clean-architecture
description: アーキテクチャ設計判断時に使用する。新規コードの層配置、層間の境界設計、コンポーネント構成の判断を支援する。新規機能追加、モジュール分割、Swift Package設計、DependencyContainer変更時に自動適用する。
---

# Custom Clean Architecture

Robert C. Martin「Clean Architecture」に基づくアーキテクチャレベルの設計原則。

## Clean Architectureの本質

> ソフトウェアアーキテクチャの目的は、システムの開発・デプロイ・運用・保守を容易にすることである。— Robert C. Martin

核心は**方針（ビジネスルール）と詳細（フレームワーク、DB、UI）の分離**。

**依存性の規則**: ソースコードの依存は**常に内側（上位方針）に向かう**。内側の層は外側の層の存在を知らない。

custom-solidのDIPは層境界を実現する**手段**。本スキルは層そのものの設計 ── 何をどの層に置くか、境界をどう越えるか ── を扱う。DIPの詳細はcustom-solidを参照。

## 層の責務と判断基準

| 層 | 責務 | 判断の問い |
|----|------|-----------|
| Domain | ビジネスの概念・ルール・計算 | 「フレームワークが消えても成り立つか？」 |
| Application | ユーザー操作フローの調整 | 「ユーザーストーリーを表現しているか？」 |
| Infrastructure | フレームワーク・外部システムの具象実装 | 「具体的なフレームワークに依存するか？」 |
| Presentation | UI状態管理・ユーザー操作の処理 | 「ユーザーの目に見える/操作に関わるか？」 |
| App | DI・アプリケーションエントリポイント | 「全層を結合する配線か？」 |

**「このコードはどの層に属するか？」の判断フロー**:
1. フレームワーク依存あり → Infrastructure
2. ユーザーに見える/操作に関わる → Presentation
3. 操作フローの調整 → Application
4. ビジネスの概念・ルール → Domain

各層の具体的な配置と判断例は [references/layer-guide.md](references/layer-guide.md) を参照。

## 境界を越えるデータの扱い

> 境界を越えるデータは、内側の層にとって便利な形式であるべきである。— Robert C. Martin

**原則**: 外側の層のデータ形式（UIモデル、DBスキーマ）を内側に持ち込まない。

**Domain Entityを直接UIに渡す場合の判断**:
- 小規模プロジェクトでは許容される。EntityがCodableでViewに直接バインドできるなら、中間DTOは不要なオーバーエンジニアリング。
- **DTOが必要になる兆候**: EntityがUI都合のプロパティ（`displayName`、`formattedDuration`、`isSelected`）を持ち始めたとき。EntityにUI責務が侵食している。

**このプロジェクトでの実践**:
- `RecordingSession` — Application層のDTO。UseCase → ViewModelへの結果受け渡し。Domain Entityの`Recording`とは別の構造で、録音操作の結果（URL、設定）を伝える。
- `StopRecordingResult` — 停止操作の結果を伝えるDTO。
- `Exercise`, `ScaleSettings` — Domain Entityを直接ViewModelが参照。現時点ではUI都合の肥大化がないため許容。

## コンポーネント凝集性の原則

コンポーネント（Swift Package、モジュール）内部にどのクラスを含めるかの判断基準。

**REP（再利用・リリース等価の原則）**: 再利用の単位 = リリースの単位。1つのPackageに含まれるクラスは一緒にリリースされる。バラバラに使いたいものを1つのPackageに入れない。

**CCP（閉鎖性共通の原則）**: 同じ理由で変更されるクラスは同じコンポーネントに集める。変更理由が異なるクラスは異なるコンポーネントに分離する。SRPのコンポーネント版。

**CRP（全再利用の原則）**: 使わないものへの依存を強制しない。コンポーネント内のクラスを1つでも使うなら、すべてに依存することになる。不要なクラスを含めない。ISPのコンポーネント版。

**このプロジェクトでの適用**:
- `VocalisDomain`: 音声トレーニングのコア概念（Exercise, Recording, ScaleSettings等）→ 同じ理由（トレーニング仕様の変更）で変わる（CCP）
- `SubscriptionDomain`: 課金の概念（SubscriptionStatus, SubscriptionTier, RecordingLimit）→ 課金仕様の変更で変わる（CCP）。音声トレーニングと課金は変更理由が異なるため分離。

## コンポーネント結合の原則

コンポーネント間の依存関係の判断基準。

**ADP（非循環依存の原則）**: コンポーネント間に循環依存を作らない。A → B → A は禁止。Package.swiftの`dependencies`で強制される。循環が発生したら、DIPでProtocolを使って依存方向を逆転させる。

**SDP（安定依存の原則）**: 安定したもの（変更頻度が低いもの）に依存する。不安定なもの（頻繁に変わるもの）に依存すると、自分も頻繁に変更を迫られる。

**SAP（安定度・抽象度等価の原則）**: 安定したコンポーネントは抽象的であるべき。安定しているのに具象的だと、拡張しにくい硬直したコンポーネントになる。

**このプロジェクトでの適用**:
- Domain層（VocalisDomain, SubscriptionDomain）: 最も安定、最も抽象的（Protocol定義が多い）→ SAP準拠
- Infrastructure層: 最も不安定（フレームワーク変更で書き換わる）、具象的 → SAP準拠
- Application層: 中間の安定度。Domain層のProtocolに依存し、Infrastructure層には依存しない

## Humble Object パターン

> テストしにくい部分を最小化し、テスト可能なロジックを分離する。— Robert C. Martin

テストが書きにくいコード（UI描画、ハードウェアアクセス、外部通信）を可能な限り薄く保ち、ロジックをテスト可能な場所に移す。

**SwiftUIでの適用**:
- **View（Humble Object）**: レイアウトとバインディングのみ。条件分岐や計算を含まない。
- **ViewModel（テスト可能なロジック）**: 状態遷移、バリデーション、フォーマット処理。XCTestで検証可能。

**判断基準**: UIフレームワーク（SwiftUI）に依存するコードに`if/switch`によるビジネスロジックを書いていないか？ 書いていたらViewModelに移す。

## アーキテクチャ違反の検出

**import文の監視**:
- Domain層（VocalisDomain/SubscriptionDomain）がAVFoundation、UIKit、StoreKitをimportしていないか → 違反
- Application層がInfrastructure層の具象型をimportしていないか → 違反

**DependencyContainer**:
- 具象型がProtocol型で保持されているか。`private lazy var scalePlayer: ScalePlayerProtocol`は正しい。`private lazy var scalePlayer: HybridScalePlayer`は漏洩。
- Factory Methodで画面ごとのViewModelを生成するとき、具象のInfrastructure型がPresentation層に漏れていないか。

**テスト困難性**:
- テストが書きにくい → 層の境界が曖昧な可能性。モックが大量に必要 → 依存が多すぎる。テストでAVFoundationの初期化が必要 → Infrastructure層のコードがDomainやApplicationに侵入している。

**Package.swift**:
- VocalisDomainのdependenciesが空か最小限か（外部フレームワーク依存なし）
- SubscriptionDomainがVocalisDomainに依存していないか（循環防止）

## 設計判断チェックリスト

### 新規機能追加時
- [ ] 新しいコードの層配置を判断したか？（判断フローチャート参照）
- [ ] 層を越える依存はProtocol経由か？（DIPの詳細はcustom-solid参照）
- [ ] DependencyContainerの変更が必要か？ Protocol型で保持しているか？

### Swift Package分割の検討時
- [ ] 変更理由が既存Packageと異なるか？（CCP）
- [ ] 循環依存が発生しないか？（ADP）
- [ ] Package内のすべての型が一緒に使われるか？（CRP）

### 連携ポイント
- **custom-solid**: DIP（依存方向の逆転）、ISP（Protocol分割）は層境界設計の手段
- **custom-tdd**: 層別テストパターン（references/layer-patterns.md）でテスト設計を判断
- **custom-refactoring**: Large ClassやFeature Envyは層境界の曖昧さに起因することがある
