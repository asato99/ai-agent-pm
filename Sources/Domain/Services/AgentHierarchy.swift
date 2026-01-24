// Sources/Domain/Services/AgentHierarchy.swift
// 参照: docs/design/TASK_REQUEST_APPROVAL.md - エージェント階層判定

import Foundation

/// エージェント階層判定ユーティリティ
/// 要件: 祖先関係の判定（親、祖父母以上も判定可能）
public enum AgentHierarchy {

    /// 指定されたエージェントが子孫の祖先であるかを判定
    /// - Parameters:
    ///   - ancestor: 祖先候補のエージェントID
    ///   - descendant: 子孫候補のエージェントID
    ///   - agents: エージェント辞書（ID → Agent）
    /// - Returns: ancestorがdescendantの祖先である場合はtrue
    public static func isAncestorOf(
        ancestor: AgentID,
        descendant: AgentID,
        agents: [AgentID: Agent]
    ) -> Bool {
        // 自分自身は祖先ではない
        guard ancestor != descendant else { return false }

        // descendantが存在しない場合はfalse
        guard let descendantAgent = agents[descendant] else { return false }

        // 親を辿って祖先を探す
        var currentParentId = descendantAgent.parentAgentId

        while let parentId = currentParentId {
            // ancestorが見つかった
            if parentId == ancestor {
                return true
            }

            // 親エージェントを取得して次の親へ
            guard let parentAgent = agents[parentId] else {
                // 親が辞書に存在しない場合は終了
                return false
            }
            currentParentId = parentAgent.parentAgentId
        }

        // ルートまで辿ったがancestorは見つからなかった
        return false
    }
}
