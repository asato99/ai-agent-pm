import type { ProjectSummary } from '@/types'

interface ProjectCardProps {
  project: ProjectSummary
  onClick?: (projectId: string) => void
}

export function ProjectCard({ project, onClick }: ProjectCardProps) {
  const progressPercent = project.taskCount > 0
    ? Math.round((project.completedCount / project.taskCount) * 100)
    : 0

  const handleClick = () => {
    onClick?.(project.id)
  }

  return (
    <div
      data-testid="project-card"
      className="bg-white rounded-lg shadow p-6 hover:shadow-md transition-shadow cursor-pointer"
      onClick={handleClick}
    >
      <h3 className="text-lg font-semibold text-gray-900 mb-2">{project.name}</h3>
      <p className="text-sm text-gray-600 mb-4">{project.description}</p>

      <div className="space-y-2">
        <div className="flex justify-between text-sm text-gray-500">
          <span>タスク: {project.taskCount}</span>
          <span>あなたの担当: {project.myTaskCount}件</span>
        </div>

        <div
          role="progressbar"
          aria-valuenow={progressPercent}
          aria-valuemin={0}
          aria-valuemax={100}
          className="w-full bg-gray-200 rounded-full h-2.5"
        >
          <div
            className="bg-blue-600 h-2.5 rounded-full transition-all"
            style={{ width: `${progressPercent}%` }}
          />
        </div>

        <div className="flex justify-between text-xs text-gray-500">
          <span>完了: {project.completedCount}/{project.taskCount}</span>
          <span>{progressPercent}%</span>
        </div>

        {project.blockedCount > 0 && (
          <div className="text-xs text-orange-600 font-medium mt-2">
            ⚠️ ブロック中: {project.blockedCount}
          </div>
        )}
      </div>
    </div>
  )
}
