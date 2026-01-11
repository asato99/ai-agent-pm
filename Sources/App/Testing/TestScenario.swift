// Sources/App/Testing/TestScenario.swift
// UIテスト用シナリオ定義

#if DEBUG

import Foundation

/// テストシナリオの種類
public enum TestScenario: String {
    case empty = "Empty"                     // 空状態（プロジェクトなし）
    case basic = "Basic"                     // 基本データ（プロジェクト+エージェント+タスク）
    case multiProject = "MultiProject"       // 複数プロジェクト
    case uc001 = "UC001"                     // UC001: エージェントキック用
    case uc002 = "UC002"                     // UC002: マルチエージェント協調
    case uc003 = "UC003"                     // UC003: AIタイプ切り替え
    case uc004 = "UC004"                     // UC004: 複数プロジェクト×同一エージェント
    case uc005 = "UC005"                     // UC005: マネージャー→ワーカー委任
    case uc006 = "UC006"                     // UC006: 複数ワーカーへのタスク割り当て
    case uc007 = "UC007"                     // UC007: 依存関係のあるタスク実行
    case uc008 = "UC008"                     // UC008: タスクブロックによる作業中断
    case uc009 = "UC009"                     // UC009: エージェントとのチャット通信
    case uc010 = "UC010"                     // UC010: チャットタイムアウトエラー表示
    case noWD = "NoWD"                       // NoWD: workingDirectory未設定エラーテスト
    case internalAudit = "InternalAudit"     // Internal Audit機能テスト
    case workflowTemplate = "WorkflowTemplate" // ワークフローテンプレート機能テスト
}

#endif
