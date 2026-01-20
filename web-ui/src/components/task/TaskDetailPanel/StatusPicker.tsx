import type { TaskStatus } from '@/types'

interface StatusPickerProps {
  value: TaskStatus
  validTransitions: TaskStatus[]
  disabled?: boolean
  onChange: (status: TaskStatus) => void
}

const statusLabels: Record<TaskStatus, string> = {
  backlog: 'Backlog',
  todo: 'To Do',
  in_progress: 'In Progress',
  blocked: 'Blocked',
  done: 'Done',
  cancelled: 'Cancelled',
}

const statusStyles: Record<TaskStatus, string> = {
  backlog: 'bg-gray-100 text-gray-700',
  todo: 'bg-blue-100 text-blue-700',
  in_progress: 'bg-yellow-100 text-yellow-700',
  blocked: 'bg-red-100 text-red-700',
  done: 'bg-green-100 text-green-700',
  cancelled: 'bg-gray-200 text-gray-500',
}

export function StatusPicker({
  value,
  validTransitions,
  disabled = false,
  onChange,
}: StatusPickerProps) {
  const handleChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    onChange(e.target.value as TaskStatus)
  }

  // Include current status in the options (always shown)
  const options = [value, ...validTransitions.filter((s) => s !== value)]

  return (
    <div className="flex items-center gap-2">
      <label className="text-sm font-medium text-gray-700">Status</label>
      <select
        value={value}
        onChange={handleChange}
        disabled={disabled}
        className={`
          px-3 py-1.5 rounded-md text-sm font-medium
          border border-gray-300
          focus:outline-none focus:ring-2 focus:ring-blue-500
          disabled:opacity-50 disabled:cursor-not-allowed
          ${statusStyles[value]}
        `}
      >
        {options.map((status) => (
          <option
            key={status}
            value={status}
            disabled={status !== value && !validTransitions.includes(status)}
          >
            {statusLabels[status]}
          </option>
        ))}
      </select>
    </div>
  )
}
