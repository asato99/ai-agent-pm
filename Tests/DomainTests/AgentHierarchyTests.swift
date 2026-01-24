// Tests/DomainTests/AgentHierarchyTests.swift
// 参照: docs/design/TASK_REQUEST_APPROVAL.md - エージェント階層判定ロジック

import XCTest
@testable import Domain

/// AgentHierarchy.isAncestorOf のテスト
/// 要件: 祖先関係の判定（親、祖父母以上も判定可能）
final class AgentHierarchyTests: XCTestCase {

    // MARK: - テストデータ

    /// 階層構造:
    /// Human A (Owner)
    /// ├── AI Worker A1
    /// └── AI Worker A2
    /// Human B (Owner)
    /// ├── AI Worker B1
    /// └── AI Worker B2

    private func makeAgent(id: String, parentId: String? = nil, type: AgentType = .ai) -> Agent {
        Agent(
            id: AgentID(value: id),
            name: "Agent \(id)",
            role: "Test",
            type: type,
            parentAgentId: parentId.map { AgentID(value: $0) }
        )
    }

    private func makeTestAgents() -> [AgentID: Agent] {
        let humanA = makeAgent(id: "human-a", parentId: nil, type: .human)
        let workerA1 = makeAgent(id: "worker-a1", parentId: "human-a")
        let workerA2 = makeAgent(id: "worker-a2", parentId: "human-a")
        let humanB = makeAgent(id: "human-b", parentId: nil, type: .human)
        let workerB1 = makeAgent(id: "worker-b1", parentId: "human-b")
        let workerB2 = makeAgent(id: "worker-b2", parentId: "human-b")

        return [
            humanA.id: humanA,
            workerA1.id: workerA1,
            workerA2.id: workerA2,
            humanB.id: humanB,
            workerB1.id: workerB1,
            workerB2.id: workerB2,
        ]
    }

    // MARK: - 直接の親子関係

    /// 親 → 子: isAncestorOf = true
    func test_isAncestorOf_directParent_returnsTrue() {
        // Given
        let agents = makeTestAgents()
        let parent = agents[AgentID(value: "human-a")]!
        let child = agents[AgentID(value: "worker-a1")]!

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: parent.id,
            descendant: child.id,
            agents: agents
        )

        // Then
        XCTAssertTrue(result, "親は子の祖先であるべき")
    }

    /// 子 → 親: isAncestorOf = false
    func test_isAncestorOf_directChild_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let parent = agents[AgentID(value: "human-a")]!
        let child = agents[AgentID(value: "worker-a1")]!

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: child.id,
            descendant: parent.id,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "子は親の祖先ではない")
    }

    // MARK: - 祖父母関係

    /// 祖父母 → 孫: isAncestorOf = true
    func test_isAncestorOf_grandparent_returnsTrue() {
        // Given: grandparent → parent → child
        let grandparent = makeAgent(id: "owner", parentId: nil, type: .human)
        let parent = makeAgent(id: "human-a", parentId: "owner", type: .human)
        let child = makeAgent(id: "worker-a1", parentId: "human-a")

        let agents: [AgentID: Agent] = [
            grandparent.id: grandparent,
            parent.id: parent,
            child.id: child,
        ]

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: grandparent.id,
            descendant: child.id,
            agents: agents
        )

        // Then
        XCTAssertTrue(result, "祖父母は孫の祖先であるべき")
    }

    /// 曾祖父母 → 曾孫: isAncestorOf = true
    func test_isAncestorOf_greatGrandparent_returnsTrue() {
        // Given: great-grandparent → grandparent → parent → child
        let greatGrandparent = makeAgent(id: "ceo", parentId: nil, type: .human)
        let grandparent = makeAgent(id: "owner", parentId: "ceo", type: .human)
        let parent = makeAgent(id: "human-a", parentId: "owner", type: .human)
        let child = makeAgent(id: "worker-a1", parentId: "human-a")

        let agents: [AgentID: Agent] = [
            greatGrandparent.id: greatGrandparent,
            grandparent.id: grandparent,
            parent.id: parent,
            child.id: child,
        ]

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: greatGrandparent.id,
            descendant: child.id,
            agents: agents
        )

        // Then
        XCTAssertTrue(result, "曾祖父母は曾孫の祖先であるべき")
    }

    // MARK: - 兄弟関係

    /// 兄弟 → 兄弟: isAncestorOf = false
    func test_isAncestorOf_siblings_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let sibling1 = agents[AgentID(value: "worker-a1")]!
        let sibling2 = agents[AgentID(value: "worker-a2")]!

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: sibling1.id,
            descendant: sibling2.id,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "兄弟は祖先ではない")
    }

    // MARK: - 他人関係

    /// 他系統のエージェント: isAncestorOf = false
    func test_isAncestorOf_unrelatedAgents_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let agentA = agents[AgentID(value: "worker-a1")]!
        let agentB = agents[AgentID(value: "worker-b1")]!

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: agentA.id,
            descendant: agentB.id,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "他系統のエージェントは祖先ではない")
    }

    /// 他系統の親 → 他系統の子: isAncestorOf = false
    func test_isAncestorOf_unrelatedParent_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let humanA = agents[AgentID(value: "human-a")]!
        let workerB1 = agents[AgentID(value: "worker-b1")]!

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: humanA.id,
            descendant: workerB1.id,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "他系統の親は祖先ではない")
    }

    // MARK: - 自分自身

    /// 自分自身: isAncestorOf = false
    func test_isAncestorOf_self_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let agent = agents[AgentID(value: "worker-a1")]!

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: agent.id,
            descendant: agent.id,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "自分自身は自分の祖先ではない")
    }

    // MARK: - エッジケース

    /// 存在しないエージェント: isAncestorOf = false
    func test_isAncestorOf_nonExistentAgent_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let existingAgent = agents[AgentID(value: "worker-a1")]!
        let nonExistentId = AgentID(value: "non-existent")

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: nonExistentId,
            descendant: existingAgent.id,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "存在しないエージェントは祖先ではない")
    }

    /// descendantが存在しない: isAncestorOf = false
    func test_isAncestorOf_nonExistentDescendant_returnsFalse() {
        // Given
        let agents = makeTestAgents()
        let existingAgent = agents[AgentID(value: "human-a")]!
        let nonExistentId = AgentID(value: "non-existent")

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: existingAgent.id,
            descendant: nonExistentId,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "存在しない子孫に対しては祖先ではない")
    }

    /// 空のagents辞書: isAncestorOf = false
    func test_isAncestorOf_emptyAgents_returnsFalse() {
        // Given
        let agents: [AgentID: Agent] = [:]
        let id1 = AgentID(value: "agent-1")
        let id2 = AgentID(value: "agent-2")

        // When
        let result = AgentHierarchy.isAncestorOf(
            ancestor: id1,
            descendant: id2,
            agents: agents
        )

        // Then
        XCTAssertFalse(result, "空のagents辞書では祖先判定はfalse")
    }
}
