import { useState, useRef, useEffect } from 'react'
import type { Task, TaskPriority } from '@/types'

interface TaskCardProps {
  task: Task
  onClick?: (taskId: string) => void
  onDelete?: (taskId: string) => void
}

const priorityLabels: Record<TaskPriority, string> = {
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  urgent: 'Urgent',
}

const priorityStyles: Record<TaskPriority, string> = {
  low: 'bg-gray-100 text-gray-700',
  medium: 'bg-blue-100 text-blue-700',
  high: 'bg-orange-100 text-orange-700',
  urgent: 'bg-red-100 text-red-700',
}

export function TaskCard({ task, onClick, onDelete }: TaskCardProps) {
  const [menuOpen, setMenuOpen] = useState(false)
  const [confirmOpen, setConfirmOpen] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)

  const handleClick = () => {
    if (!menuOpen && !confirmOpen) {
      onClick?.(task.id)
    }
  }

  const handleMenuClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    setMenuOpen(!menuOpen)
  }

  const handleDeleteClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    setMenuOpen(false)
    setConfirmOpen(true)
  }

  const handleConfirmDelete = (e: React.MouseEvent) => {
    e.stopPropagation()
    onDelete?.(task.id)
    setConfirmOpen(false)
  }

  const handleCancelDelete = (e: React.MouseEvent) => {
    e.stopPropagation()
    setConfirmOpen(false)
  }

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setMenuOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  return (
    <>
      <div
        data-testid="task-card"
        data-task-id={task.id}
        className="bg-white rounded-lg shadow p-4 hover:shadow-md transition-shadow cursor-pointer relative"
        onClick={handleClick}
      >
        <div className="flex justify-between items-start">
          <h4 className="text-sm font-medium text-gray-900 mb-2 flex-1">{task.title}</h4>
          <div className="relative" ref={menuRef}>
            <button
              type="button"
              aria-label="メニュー"
              className="p-1 hover:bg-gray-100 rounded"
              onClick={handleMenuClick}
              onPointerDown={(e) => e.stopPropagation()}
            >
              <svg className="w-4 h-4 text-gray-500" fill="currentColor" viewBox="0 0 20 20">
                <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
              </svg>
            </button>
            {menuOpen && (
              <div
                role="menu"
                className="absolute right-0 mt-1 w-32 bg-white border border-gray-200 rounded-md shadow-lg z-10"
              >
                <button
                  role="menuitem"
                  className="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-gray-100"
                  onClick={handleDeleteClick}
                >
                  削除
                </button>
              </div>
            )}
          </div>
        </div>
        <span
          className={`inline-block px-2 py-1 text-xs font-medium rounded ${priorityStyles[task.priority]}`}
        >
          {priorityLabels[task.priority]}
        </span>
      </div>

      {/* Delete confirmation dialog */}
      {confirmOpen && (
        <div
          className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
          onClick={handleCancelDelete}
        >
          <div
            role="dialog"
            aria-modal="true"
            className="bg-white rounded-lg p-6 max-w-sm w-full mx-4"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-lg font-medium text-gray-900 mb-4">タスクを削除しますか？</h3>
            <p className="text-sm text-gray-600 mb-6">
              タスク「{task.title}」を削除します。この操作は取り消せません。
            </p>
            <div className="flex justify-end gap-3">
              <button
                type="button"
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                onClick={handleCancelDelete}
              >
                キャンセル
              </button>
              <button
                type="button"
                className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700"
                onClick={handleConfirmDelete}
              >
                削除
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
