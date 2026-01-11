// Sources/App/Features/Chat/ChatMessageRow.swift
// 参照: docs/design/CHAT_FEATURE.md - ChatMessageRow

import SwiftUI
import Domain

/// チャットメッセージ行コンポーネント
struct ChatMessageRow: View {
    let message: ChatMessage
    let agentName: String?

    private var isFromUser: Bool {
        message.sender == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isFromUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
                // 送信者とタイムスタンプ
                HStack(spacing: 4) {
                    if !isFromUser {
                        Text(senderIcon)
                            .font(.caption)
                        if let name = agentName {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("You")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("👤")
                            .font(.caption)
                    }

                    Text(formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // メッセージ本文
                // Note: Text(message.content) を独立したアクセシビリティ要素として公開
                // XCUITestが staticTexts で検索できるようにする
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(messageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // 明示的に独立したアクセシビリティ要素として宣言
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(message.content)
                    .accessibilityIdentifier("ChatMessageContent-\(message.id.value)")
            }

            if !isFromUser {
                Spacer(minLength: 60)
            }
        }
        // .contain に変更して、子要素を個別にアクセス可能にする
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ChatMessageRow-\(message.id.value)")
    }

    // MARK: - Styling

    private var senderIcon: String {
        isFromUser ? "👤" : "🤖"
    }

    private var messageBackground: Color {
        isFromUser ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.createdAt)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        ChatMessageRow(
            message: ChatMessage(
                id: ChatMessageID.generate(),
                sender: .user,
                content: "タスクAの進捗を教えてください。",
                createdAt: Date()
            ),
            agentName: nil
        )

        ChatMessageRow(
            message: ChatMessage(
                id: ChatMessageID.generate(),
                sender: .agent,
                content: "タスクAは現在50%完了しています。主要な機能の実装が完了し、テストフェーズに入る準備をしています。",
                createdAt: Date()
            ),
            agentName: "Claude"
        )
    }
    .padding()
}
#endif
