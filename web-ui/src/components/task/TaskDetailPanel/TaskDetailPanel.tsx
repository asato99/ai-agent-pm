import type { Task } from '@/types'

interface TaskDetailPanelProps {
  task: Task | null
  isOpen: boolean
  onClose: () => void
}

export function TaskDetailPanel({ task, isOpen, onClose }: TaskDetailPanelProps) {
  if (!isOpen || !task) return null

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center"
    >
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />
      <div className="relative bg-white rounded-lg shadow-xl p-6 w-full max-w-lg">
        <h2 className="text-xl font-bold text-gray-900 mb-4">{task.title}</h2>
        <p className="text-gray-600 mb-4">{task.description}</p>
        <div className="flex justify-end">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
          >
            閉じる
          </button>
        </div>
      </div>
    </div>
  )
}
