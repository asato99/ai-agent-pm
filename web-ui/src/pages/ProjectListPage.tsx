import { useNavigate } from 'react-router-dom'
import { AppHeader } from '@/components/layout'
import { useProjects } from '@/hooks/useProjects'
import { ProjectCard } from '@/components/project'
import { AgentListSection } from '@/components/agent'

export function ProjectListPage() {
  const navigate = useNavigate()
  const { projects, isLoading, error } = useProjects()

  const handleProjectClick = (projectId: string) => {
    navigate(`/projects/${projectId}`)
  }

  return (
    <div className="min-h-screen bg-gray-100">
      <AppHeader />

      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <h2 className="text-2xl font-bold text-gray-900 mb-6">My Projects</h2>

        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {isLoading && (
            <div className="bg-white rounded-lg shadow p-6">
              <p className="text-gray-500">Loading projects...</p>
            </div>
          )}

          {error && (
            <div className="bg-white rounded-lg shadow p-6">
              <p className="text-red-500">An error occurred: {error.message}</p>
            </div>
          )}

          {!isLoading &&
            !error &&
            projects.map((project) => (
              <ProjectCard
                key={project.id}
                project={project}
                onClick={handleProjectClick}
              />
            ))}

          {!isLoading && !error && projects.length === 0 && (
            <div className="bg-white rounded-lg shadow p-6">
              <p className="text-gray-500">No projects found</p>
            </div>
          )}
        </div>

        <AgentListSection />
      </main>
    </div>
  )
}
