// web-ui/src/hooks/useUnreadCounts.ts
// 未読メッセージカウント取得フック
// Reference: docs/design/CHAT_FEATURE.md - Unread count feature

import { useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'

interface UnreadCountsResponse {
  counts: Record<string, number>
}

interface UseUnreadCountsResult {
  /** エージェントID -> 未読数のマッピング */
  unreadCounts: Record<string, number>
  /** 読み込み中フラグ */
  isLoading: boolean
  /** エラー情報 */
  error: Error | null
  /** 特定エージェントの未読数を取得 */
  getCountFor: (agentId: string) => number
  /** 合計未読数 */
  totalUnread: number
  /** 手動リフレッシュ */
  refetch: () => Promise<unknown>
}

/**
 * プロジェクト内の未読メッセージカウントを取得するフック
 * @param projectId プロジェクトID
 * @returns 未読カウント情報
 */
export function useUnreadCounts(projectId: string): UseUnreadCountsResult {
  const queryKey = ['unreadCounts', projectId]

  const { data, isLoading, error, refetch } = useQuery({
    queryKey,
    queryFn: async (): Promise<UnreadCountsResponse> => {
      const sessionToken = localStorage.getItem('sessionToken')
      if (!sessionToken) {
        throw new Error('Not authenticated')
      }

      const response = await fetch(`/api/projects/${projectId}/unread-counts`, {
        headers: {
          Authorization: `Bearer ${sessionToken}`,
        },
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.message || `HTTP ${response.status}`)
      }

      return response.json()
    },
    enabled: !!projectId,
    // 30秒ごとに自動更新
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  })

  const unreadCounts = data?.counts ?? {}

  // 特定エージェントの未読数を取得
  const getCountFor = useCallback(
    (agentId: string): number => {
      return unreadCounts[agentId] ?? 0
    },
    [unreadCounts]
  )

  // 合計未読数
  const totalUnread = Object.values(unreadCounts).reduce((sum, count) => sum + count, 0)

  return {
    unreadCounts,
    isLoading,
    error: error as Error | null,
    getCountFor,
    totalUnread,
    refetch,
  }
}
