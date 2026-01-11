// Sources/App/Features/Chat/AgentChatView.swift
// 参照: docs/design/CHAT_FEATURE.md - AgentChatView

import SwiftUI
import Domain

/// _Concurrency.Task と Domain.Task の衝突を避けるためのエイリアス
private typealias AsyncTask = _Concurrency.Task

/// エージェントとのチャット画面
struct AgentChatView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(Router.self) var router

    let agentId: AgentID
    let projectId: ProjectID

    @State private var agent: Agent?
    @State private var project: Project?
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var pollingTimer: Timer?

    /// ポーリング間隔（秒）
    private let pollingInterval: TimeInterval = 3.0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()

            // Message List
            messageList

            Divider()

            // Input Area
            MessageInputView(
                text: $inputText,
                onSend: sendMessage,
                isEnabled: !isSending && project?.workingDirectory != nil
            )
        }
        .accessibilityIdentifier("AgentChatView")
        .task {
            await loadData()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        Group {
        HStack {
            // Agent info
            if let agent = agent {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(agent.type == .ai ? "🤖" : "👤")
                            .font(.title3)
                        Text(agent.name)
                            .font(.headline)
                    }
                    Text(agent.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status badge
                Text(agent.status.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: agent.status).opacity(0.2))
                    .foregroundStyle(statusColor(for: agent.status))
                    .clipShape(Capsule())
            } else {
                ProgressView()
                    .controlSize(.small)
                Spacer()
            }

            // Close button
            Button {
                router.closeChatView()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close chat")
            .accessibilityIdentifier("CloseChatButton")
        }
        .padding()
        .background(.background.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ChatHeader")
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty && !isLoading {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            ChatMessageRow(
                                message: message,
                                agentName: agent?.name
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                // 新しいメッセージが追加されたら最下部にスクロール
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ChatMessageList")
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Send a message to start a conversation with \(agent?.name ?? "the agent").")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if project?.workingDirectory == nil {
                Text("Note: Set a working directory for this project to enable chat.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            agent = try container.agentRepository.findById(agentId)
            project = try container.projectRepository.findById(projectId)

            // メッセージを読み込み
            await loadMessages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMessages() async {
        guard project?.workingDirectory != nil else { return }

        do {
            messages = try container.chatRepository.findMessages(
                projectId: projectId,
                agentId: agentId
            )
        } catch {
            // ファイルが存在しない場合は空のままでOK
            messages = []
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard project?.workingDirectory != nil else { return }

        let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        isSending = true

        AsyncTask {
            do {
                let message = ChatMessage(
                    id: ChatMessageID.generate(),
                    sender: .user,
                    content: content,
                    createdAt: Date()
                )

                try container.chatRepository.saveMessage(
                    message,
                    projectId: projectId,
                    agentId: agentId
                )

                // メッセージを再読み込み
                await loadMessages()

                // モック応答を追加（将来的にはMCP連携で実際のエージェント応答に置き換え）
                await addMockResponse()

            } catch {
                await MainActor.run {
                    router.showAlert(.error(message: error.localizedDescription))
                }
            }

            await MainActor.run {
                isSending = false
            }
        }
    }

    /// モック応答を追加（Phase 1ではMCP連携なし）
    private func addMockResponse() async {
        // 少し待ってからモック応答を追加
        try? await AsyncTask.sleep(nanoseconds: 1_000_000_000) // 1秒

        let mockContent = "メッセージを受け取りました。現在、この機能はモック実装です。将来的にはMCPを通じて実際のエージェントと通信します。"

        let mockMessage = ChatMessage(
            id: ChatMessageID.generate(),
            sender: .agent,
            content: mockContent,
            createdAt: Date()
        )

        do {
            try container.chatRepository.saveMessage(
                mockMessage,
                projectId: projectId,
                agentId: agentId
            )

            await loadMessages()
        } catch {
            print("Failed to save mock response: \(error)")
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { _ in
            AsyncTask { await loadMessages() }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Helpers

    private func statusColor(for status: AgentStatus) -> Color {
        switch status {
        case .active: return .green
        case .inactive: return .gray
        case .suspended: return .orange
        case .archived: return .secondary
        }
    }
}

#if DEBUG
#Preview {
    AgentChatView(
        agentId: AgentID.generate(),
        projectId: ProjectID.generate()
    )
    .environmentObject(try! DependencyContainer())
    .environment(Router())
}
#endif
