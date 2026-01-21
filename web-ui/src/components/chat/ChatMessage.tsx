// web-ui/src/components/chat/ChatMessage.tsx
// 個別チャットメッセージの表示コンポーネント
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 6

import type { ChatMessage as ChatMessageType } from '@/types'

interface ChatMessageProps {
  message: ChatMessageType
}

export function ChatMessage({ message }: ChatMessageProps) {
  const isUser = message.sender === 'user'
  const isSystem = message.sender === 'system'

  // フォーマット済みの時刻を取得
  const formatTime = (dateString: string) => {
    const date = new Date(dateString)
    return date.toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })
  }

  return (
    <div
      className={`flex mb-4 ${isUser ? 'justify-end' : 'justify-start'}`}
      data-testid="chat-message"
      data-message-id={message.id}
    >
      <div
        className={`max-w-[70%] rounded-lg px-4 py-2 ${
          isUser
            ? 'bg-blue-500 text-white'
            : isSystem
              ? 'bg-gray-200 text-gray-600 italic'
              : 'bg-gray-100 text-gray-900'
        }`}
      >
        {/* Sender label for agent/system messages */}
        {!isUser && (
          <div className="text-xs font-semibold mb-1 opacity-70">
            {isSystem ? 'システム' : 'エージェント'}
          </div>
        )}

        {/* Message content */}
        <div className="whitespace-pre-wrap break-words">{message.content}</div>

        {/* Timestamp */}
        <div className={`text-xs mt-1 ${isUser ? 'text-blue-100' : 'text-gray-500'}`}>
          {formatTime(message.createdAt)}
        </div>
      </div>
    </div>
  )
}
