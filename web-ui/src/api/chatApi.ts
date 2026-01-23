// web-ui/src/api/chatApi.ts
// チャットAPIクライアント
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 4

import { api } from './client'
import type {
  ChatMessage,
  ChatMessagesResponse,
  GetChatMessagesOptions,
} from '@/types'

/**
 * チャットAPIクライアント
 */
export const chatApi = {
  /**
   * チャットメッセージ一覧を取得
   * @param projectId プロジェクトID
   * @param agentId エージェントID
   * @param options 取得オプション（limit, after, before）
   * @returns メッセージ一覧とページネーション情報
   */
  async getMessages(
    projectId: string,
    agentId: string,
    options?: GetChatMessagesOptions
  ): Promise<ChatMessagesResponse> {
    const params: Record<string, string> = {}
    if (options?.limit !== undefined) {
      params.limit = String(options.limit)
    }
    if (options?.after) {
      params.after = options.after
    }
    if (options?.before) {
      params.before = options.before
    }

    const result = await api.get<ChatMessagesResponse>(
      `/projects/${projectId}/agents/${agentId}/chat/messages`,
      Object.keys(params).length > 0 ? params : undefined
    )

    if (result.error) {
      throw new Error(result.error.message)
    }

    return result.data!
  },

  /**
   * チャットメッセージを送信
   * @param projectId プロジェクトID
   * @param agentId エージェントID
   * @param content メッセージ内容
   * @param relatedTaskId 関連タスクID（オプション）
   * @returns 作成されたメッセージ
   */
  async sendMessage(
    projectId: string,
    agentId: string,
    content: string,
    relatedTaskId?: string
  ): Promise<ChatMessage> {
    const result = await api.post<ChatMessage>(
      `/projects/${projectId}/agents/${agentId}/chat/messages`,
      { content, relatedTaskId }
    )

    if (result.error) {
      throw new Error(result.error.message)
    }

    return result.data!
  },

  /**
   * チャットを既読にする
   * @param projectId プロジェクトID
   * @param agentId エージェントID（送信者）
   */
  async markAsRead(projectId: string, agentId: string): Promise<void> {
    const result = await api.post<{ success: boolean }>(
      `/projects/${projectId}/agents/${agentId}/chat/mark-read`,
      {}
    )

    if (result.error) {
      throw new Error(result.error.message)
    }
  },

  /**
   * チャットセッションを開始する
   * Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Phase 3
   * @param projectId プロジェクトID
   * @param agentId エージェントID（対話相手）
   */
  async startSession(projectId: string, agentId: string): Promise<void> {
    const result = await api.post<{ success: boolean }>(
      `/projects/${projectId}/agents/${agentId}/chat/start`,
      {}
    )

    if (result.error) {
      throw new Error(result.error.message)
    }
  },

  /**
   * チャットセッションを終了する
   * Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
   * @param projectId プロジェクトID
   * @param agentId エージェントID（対話相手）
   *
   * This sets the session state to 'terminating', which causes:
   * 1. Agent's next getNextAction call returns 'exit' action
   * 2. Agent calls logout, setting session state to 'ended'
   */
  async endSession(projectId: string, agentId: string): Promise<void> {
    const result = await api.post<{ success: boolean }>(
      `/projects/${projectId}/agents/${agentId}/chat/end`,
      {}
    )

    if (result.error) {
      throw new Error(result.error.message)
    }
  },

  /**
   * チャットセッションを終了する（sendBeacon版）
   * Reference: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md - Section 6
   *
   * ブラウザ/タブを閉じる時に使用。sendBeaconはページアンロード中でも
   * 確実にリクエストを送信できる。
   *
   * @param projectId プロジェクトID
   * @param agentId エージェントID（対話相手）
   * @returns boolean - sendBeaconが成功したかどうか
   */
  endSessionBeacon(projectId: string, agentId: string): boolean {
    const url = `/api/projects/${projectId}/agents/${agentId}/chat/end`
    const data = JSON.stringify({})
    const blob = new Blob([data], { type: 'application/json' })
    return navigator.sendBeacon(url, blob)
  },
}
