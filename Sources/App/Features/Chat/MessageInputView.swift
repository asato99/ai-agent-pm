// Sources/App/Features/Chat/MessageInputView.swift
// 参照: docs/design/CHAT_FEATURE.md - MessageInputArea

import SwiftUI

/// メッセージ入力コンポーネント
struct MessageInputView: View {
    @Binding var text: String
    let onSend: () -> Void
    let isEnabled: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // テキスト入力エリア
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 36, maxHeight: 120)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .focused($isFocused)
                .accessibilityIdentifier("ChatMessageInput")

            // 送信ボタン
            Button(action: {
                sendMessage()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (⌘↵)")
            .accessibilityIdentifier("SendButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background)
    }

    // MARK: - Actions

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        guard canSend else { return }
        onSend()
    }
}

#if DEBUG
struct MessageInputView_Preview: View {
    @State private var text = ""

    var body: some View {
        VStack {
            Spacer()
            MessageInputView(
                text: $text,
                onSend: { print("Send: \(text)") },
                isEnabled: true
            )
        }
    }
}

#Preview {
    MessageInputView_Preview()
}
#endif
