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
}
