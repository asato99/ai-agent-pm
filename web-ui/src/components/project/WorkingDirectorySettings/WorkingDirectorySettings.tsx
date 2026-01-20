// Phase 2.4: マルチデバイス対応 - ワーキングディレクトリ設定コンポーネント
// 参照: docs/design/MULTI_DEVICE_IMPLEMENTATION_PLAN.md

import { useState, useEffect } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/api/client'

interface WorkingDirectorySettingsProps {
  projectId: string
  currentWorkingDirectory?: string
}

interface WorkingDirectoryDTO {
  workingDirectory: string
}

export function WorkingDirectorySettings({
  projectId,
  currentWorkingDirectory,
}: WorkingDirectorySettingsProps) {
  const queryClient = useQueryClient()
  const [workingDirectory, setWorkingDirectory] = useState(currentWorkingDirectory || '')
  const [isEditing, setIsEditing] = useState(false)

  // currentWorkingDirectoryが変更されたら同期
  useEffect(() => {
    setWorkingDirectory(currentWorkingDirectory || '')
  }, [currentWorkingDirectory])

  const setWorkingDirectoryMutation = useMutation({
    mutationFn: async (newWorkingDirectory: string) => {
      const result = await api.put<WorkingDirectoryDTO>(
        `/projects/${projectId}/my-working-directory`,
        { workingDirectory: newWorkingDirectory }
      )
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['project', projectId] })
      setIsEditing(false)
    },
  })

  const deleteWorkingDirectoryMutation = useMutation({
    mutationFn: async () => {
      const result = await api.delete<void>(`/projects/${projectId}/my-working-directory`)
      if (result.error) {
        throw new Error(result.error.message)
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['project', projectId] })
      setWorkingDirectory('')
      setIsEditing(false)
    },
  })

  const handleSave = () => {
    if (workingDirectory.trim()) {
      setWorkingDirectoryMutation.mutate(workingDirectory.trim())
    }
  }

  const handleDelete = () => {
    if (window.confirm('ワーキングディレクトリ設定を削除しますか？')) {
      deleteWorkingDirectoryMutation.mutate()
    }
  }

  const handleCancel = () => {
    setWorkingDirectory(currentWorkingDirectory || '')
    setIsEditing(false)
  }

  const isPending = setWorkingDirectoryMutation.isPending || deleteWorkingDirectoryMutation.isPending

  return (
    <div className="bg-white rounded-lg shadow p-4 mb-4">
      <div className="flex items-center justify-between mb-2">
        <h3 className="text-sm font-medium text-gray-700">マイ ワーキングディレクトリ</h3>
        {!isEditing && (
          <button
            onClick={() => setIsEditing(true)}
            className="text-sm text-blue-600 hover:text-blue-800"
          >
            編集
          </button>
        )}
      </div>

      {isEditing ? (
        <div className="space-y-2">
          <input
            type="text"
            value={workingDirectory}
            onChange={(e) => setWorkingDirectory(e.target.value)}
            placeholder="/path/to/project"
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            disabled={isPending}
          />
          <div className="flex justify-end gap-2">
            {currentWorkingDirectory && (
              <button
                onClick={handleDelete}
                disabled={isPending}
                className="px-3 py-1.5 text-sm text-red-600 hover:text-red-800 disabled:opacity-50"
              >
                削除
              </button>
            )}
            <button
              onClick={handleCancel}
              disabled={isPending}
              className="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-800 disabled:opacity-50"
            >
              キャンセル
            </button>
            <button
              onClick={handleSave}
              disabled={isPending || !workingDirectory.trim()}
              className="px-3 py-1.5 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {isPending ? '保存中...' : '保存'}
            </button>
          </div>
        </div>
      ) : (
        <div className="text-sm text-gray-600">
          {currentWorkingDirectory ? (
            <code className="bg-gray-100 px-2 py-1 rounded">{currentWorkingDirectory}</code>
          ) : (
            <span className="text-gray-400 italic">未設定（プロジェクトのデフォルトを使用）</span>
          )}
        </div>
      )}
    </div>
  )
}
