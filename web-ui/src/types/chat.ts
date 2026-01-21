// web-ui/src/types/chat.ts
// チャット機能の型定義
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 4

/**
 * チャットメッセージの送信者
 */
export type ChatSender = 'user' | 'agent' | 'system'

/**
 * チャットメッセージ
 */
export interface ChatMessage {
  id: string
  sender: ChatSender
  content: string
  createdAt: string // ISO8601形式
  relatedTaskId?: string
}

/**
 * チャットメッセージ一覧のレスポンス（REST API）
 */
export interface ChatMessagesResponse {
  messages: ChatMessage[]
  hasMore: boolean
  totalCount?: number
}

/**
 * メッセージ送信リクエスト
 */
export interface SendMessageRequest {
  content: string
  relatedTaskId?: string
}

/**
 * チャットバリデーションエラー
 */
export interface ChatValidationError {
  error: string
  code: string
  details?: {
    maxLength?: number
    actualLength?: number
  }
}

/**
 * チャット取得オプション（REST API用）
 */
export interface GetChatMessagesOptions {
  limit?: number
  after?: string
  before?: string
}
