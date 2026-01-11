// Sources/App/Features/Chat/AgentChatView.swift
// 参照: docs/design/CHAT_FEATURE.md - AgentChatView

import SwiftUI
import Domain

/// _Concurrency.Task と Domain.Task の衝突を避けるためのエイリアス
private typealias AsyncTask = _Concurrency.Task

// MARK: - Debug Logging for XCUITest

private func chatDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] [AgentChatView] \(message)\n"

    // Also write to file for XCUITest
    let logFile = "/tmp/aiagentpm_debug.log"
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data, attributes: nil)
        }
    }
}

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
    @State private var isWaitingForResponse = false
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

                        // 応答待機中のインジケータ
                        if isWaitingForResponse {
                            WaitingForResponseView(agentName: agent?.name)
                                .id("waiting-indicator")
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
        guard project?.workingDirectory != nil else {
            chatDebugLog("loadMessages: workingDirectory is nil")
            return
        }

        do {
            let newMessages = try container.chatRepository.findMessages(
                projectId: projectId,
                agentId: agentId
            )
            let previousCount = messages.count
            messages = newMessages
            if newMessages.count != previousCount {
                chatDebugLog("loadMessages: count changed \(previousCount) -> \(newMessages.count)")

                // エージェントからの応答を受信したら待機状態を解除
                if isWaitingForResponse,
                   let lastMessage = newMessages.last,
                   lastMessage.sender == .agent {
                    isWaitingForResponse = false
                    chatDebugLog("loadMessages: agent response received, waiting state cleared")
                }
            }
        } catch {
            // ファイルが存在しない場合は空のままでOK
            chatDebugLog("loadMessages error: \(error)")
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

                // チャット用の起動理由を登録（Coordinatorがエージェントを起動する）
                await triggerAgentForChat()

                await MainActor.run {
                    isWaitingForResponse = true
                }

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

    /// エージェントをチャット応答用に起動するためのpending purposeを登録
    /// Coordinatorがこれを検知してエージェントを起動し、
    /// エージェントが get_pending_messages → respond_chat を実行する
    private func triggerAgentForChat() async {
        chatDebugLog("triggerAgentForChat: agentId=\(agentId.value), projectId=\(projectId.value)")
        do {
            let pendingPurpose = PendingAgentPurpose(
                agentId: agentId,
                projectId: projectId,
                purpose: .chat,
                createdAt: Date()
            )
            try container.pendingAgentPurposeRepository.save(pendingPurpose)
            chatDebugLog("triggerAgentForChat: PendingAgentPurpose saved successfully")

            // Verify it was saved by reading it back
            if let found = try? container.pendingAgentPurposeRepository.find(agentId: agentId, projectId: projectId) {
                chatDebugLog("triggerAgentForChat: Verified - found pending purpose: \(found.purpose)")
            } else {
                chatDebugLog("triggerAgentForChat: WARNING - pending purpose NOT found after save!")
            }
        } catch {
            chatDebugLog("triggerAgentForChat: FAILED - \(error)")
            // エラーでもUIには表示しない（ポーリングで応答を待つ）
        }
    }

    // MARK: - Polling

    private func startPolling() {
        chatDebugLog("startPolling: interval=\(pollingInterval)s")
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { _ in
            chatDebugLog("Polling timer fired")
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

// MARK: - WaitingForResponseView

/// エージェントの応答待機中に表示するインジケータ
private struct WaitingForResponseView: View {
    let agentName: String?

    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // 送信者表示
                HStack(spacing: 4) {
                    Text("🤖")
                        .font(.caption)
                    if let name = agentName {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // ローディングバブル
                HStack(spacing: 4) {
                    Text("応答を待っています")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(String(repeating: ".", count: dotCount + 1))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer(minLength: 60)
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("エージェントの応答を待っています")
        .accessibilityIdentifier("WaitingForResponseIndicator")
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
