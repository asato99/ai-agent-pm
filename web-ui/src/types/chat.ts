// web-ui/src/types/chat.ts
// チャット機能の型定義
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 4

/**
 * チャットメッセージ
 * Uses senderId/receiverId for dual storage model
 * Reference: docs/design/CHAT_FEATURE.md - Section 2.4
 */
export interface ChatMessage {
  id: string
  /** Sender's agent ID */
  senderId: string
  /** Receiver's agent ID (only in sender's storage) */
  receiverId?: string
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
  /**
   * Whether the agent has pending messages to respond to
   * This is determined by server-side logic (findUnreadMessages)
   * Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md
   */
  awaitingAgentResponse: boolean
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
