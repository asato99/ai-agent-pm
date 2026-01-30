import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { AppHeader } from '@/components/layout'
import { useAgent, useUpdateAgent, useSkills, useAgentSkills, useAssignSkills } from '@/hooks'
import type { AgentStatus, UpdateAgentRequest } from '@/types'

const statusOptions: { value: AgentStatus; label: string }[] = [
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
]

export function AgentDetailPage() {
  const { agentId } = useParams<{ agentId: string }>()
  const navigate = useNavigate()
  const { agent, isLoading, error } = useAgent(agentId ?? null)
  const updateAgent = useUpdateAgent()

  // Skill-related hooks
  const { skills: allSkills, isLoading: skillsLoading } = useSkills()
  const { agentSkills, isLoading: agentSkillsLoading } = useAgentSkills(agentId ?? null)
  const assignSkills = useAssignSkills()

  const [name, setName] = useState('')
  const [role, setRole] = useState('')
  const [status, setStatus] = useState<AgentStatus>('active')
  const [maxParallelTasks, setMaxParallelTasks] = useState(1)
  const [systemPrompt, setSystemPrompt] = useState('')
  const [formError, setFormError] = useState<string | null>(null)
  const [saveSuccess, setSaveSuccess] = useState(false)
  const [selectedSkillIds, setSelectedSkillIds] = useState<Set<string>>(new Set())
  const [skillSaveSuccess, setSkillSaveSuccess] = useState(false)
  const [skillSaveError, setSkillSaveError] = useState<string | null>(null)
  const [showSkillModal, setShowSkillModal] = useState(false)

  // Initialize form when agent data is loaded
  useEffect(() => {
    if (agent) {
      setName(agent.name)
      setRole(agent.role)
      setStatus(agent.status)
      setMaxParallelTasks(agent.maxParallelTasks)
      setSystemPrompt(agent.systemPrompt ?? '')
    }
  }, [agent])

  // Initialize selected skills when agent skills are loaded
  useEffect(() => {
    if (agentSkills) {
      setSelectedSkillIds(new Set(agentSkills.map(s => s.id)))
    }
  }, [agentSkills])

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!agent || !agentId) return

    const updates: UpdateAgentRequest = {}

    if (name !== agent.name) updates.name = name
    if (role !== agent.role) updates.role = role
    if (status !== agent.status) updates.status = status
    if (maxParallelTasks !== agent.maxParallelTasks) updates.maxParallelTasks = maxParallelTasks
    if ((systemPrompt || null) !== agent.systemPrompt) updates.systemPrompt = systemPrompt || undefined

    if (Object.keys(updates).length === 0) {
      // No changes
      setSaveSuccess(true)
      setTimeout(() => setSaveSuccess(false), 2000)
      return
    }

    updateAgent.mutate(
      { agentId, data: updates },
      {
        onSuccess: () => {
          setFormError(null)
          setSaveSuccess(true)
          setTimeout(() => setSaveSuccess(false), 2000)
        },
        onError: (err) => {
          setFormError(err.message)
        },
      }
    )
  }

  const handleBack = () => {
    navigate('/projects')
  }

  const handleSkillToggle = (skillId: string) => {
    setSelectedSkillIds(prev => {
      const next = new Set(prev)
      if (next.has(skillId)) {
        next.delete(skillId)
      } else {
        next.add(skillId)
      }
      return next
    })
  }

  const handleSaveSkills = () => {
    if (!agentId) return

    assignSkills.mutate(
      { agentId, skillIds: Array.from(selectedSkillIds) },
      {
        onSuccess: () => {
          setSkillSaveError(null)
          setShowSkillModal(false)
          setSkillSaveSuccess(true)
          setTimeout(() => setSkillSaveSuccess(false), 2000)
        },
        onError: (err) => {
          setSkillSaveError(err.message)
        },
      }
    )
  }

  const handleOpenSkillModal = () => {
    // Reset to current assigned skills when opening
    setSelectedSkillIds(new Set(agentSkills.map(s => s.id)))
    setSkillSaveError(null)
    setShowSkillModal(true)
  }

  const handleCloseSkillModal = () => {
    setShowSkillModal(false)
    setSkillSaveError(null)
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-gray-500">Loading...</p>
        </main>
      </div>
    )
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-red-500">An error occurred: {error.message}</p>
          <button
            onClick={handleBack}
            className="mt-4 text-blue-600 hover:underline"
          >
            ← Back
          </button>
        </main>
      </div>
    )
  }

  if (!agent) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-gray-500">Agent not found</p>
          <button
            onClick={handleBack}
            className="mt-4 text-blue-600 hover:underline"
          >
            ← Back
          </button>
        </main>
      </div>
    )
  }

  const isLocked = agent.isLocked
  const isFormDisabled = isLocked || updateAgent.isPending

  return (
    <div className="min-h-screen bg-gray-100">
      <AppHeader />

      <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <button
          onClick={handleBack}
          className="mb-6 text-blue-600 hover:underline flex items-center gap-1"
        >
          ← Back to Projects
        </button>

        <div className="bg-white rounded-lg shadow p-6">
          <h1 className="text-2xl font-bold text-gray-900 mb-6">Agent Detail</h1>

          {isLocked && (
            <div className="mb-4 p-3 bg-yellow-50 border border-yellow-200 rounded-md">
              <p className="text-sm text-yellow-700">
                This agent is currently locked and cannot be edited
              </p>
            </div>
          )}

          {formError && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-md">
              <p className="text-sm text-red-700">{formError}</p>
            </div>
          )}

          {saveSuccess && (
            <div className="mb-4 p-3 bg-green-50 border border-green-200 rounded-md">
              <p className="text-sm text-green-700">Saved successfully</p>
            </div>
          )}

          <form onSubmit={handleSubmit}>
            <div className="space-y-6">
              {/* Name */}
              <div>
                <label htmlFor="name" className="block text-sm font-medium text-gray-700 mb-1">
                  Name
                </label>
                <input
                  type="text"
                  id="name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                  required
                />
              </div>

              {/* Role */}
              <div>
                <label htmlFor="role" className="block text-sm font-medium text-gray-700 mb-1">
                  Role
                </label>
                <input
                  type="text"
                  id="role"
                  value={role}
                  onChange={(e) => setRole(e.target.value)}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                />
              </div>

              {/* Status */}
              <div>
                <label htmlFor="status" className="block text-sm font-medium text-gray-700 mb-1">
                  Status
                </label>
                <select
                  id="status"
                  value={status}
                  onChange={(e) => setStatus(e.target.value as AgentStatus)}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                >
                  {statusOptions.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </div>

              {/* Max Parallel Tasks */}
              <div>
                <label htmlFor="maxParallelTasks" className="block text-sm font-medium text-gray-700 mb-1">
                  Max Parallel Tasks
                </label>
                <input
                  type="number"
                  id="maxParallelTasks"
                  value={maxParallelTasks}
                  onChange={(e) => setMaxParallelTasks(parseInt(e.target.value, 10) || 1)}
                  min={1}
                  max={10}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                />
              </div>

              {/* System Prompt */}
              <div>
                <label htmlFor="systemPrompt" className="block text-sm font-medium text-gray-700 mb-1">
                  System Prompt
                </label>
                <textarea
                  id="systemPrompt"
                  value={systemPrompt}
                  onChange={(e) => setSystemPrompt(e.target.value)}
                  rows={6}
                  disabled={isFormDisabled}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
                />
              </div>

              {/* Skills */}
              <div className="border-t pt-6 mt-6">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-medium text-gray-700">Skills</h3>
                  <button
                    type="button"
                    onClick={handleOpenSkillModal}
                    disabled={isLocked}
                    className="px-2.5 py-1 text-xs text-purple-600 border border-purple-300 rounded hover:bg-purple-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Manage
                  </button>
                </div>

                {skillSaveSuccess && (
                  <div className="mb-3 p-2 bg-green-50 border border-green-200 rounded text-sm text-green-700">
                    Skills updated
                  </div>
                )}

                {agentSkillsLoading ? (
                  <p className="text-sm text-gray-500">Loading...</p>
                ) : agentSkills.length === 0 ? (
                  <p className="text-sm text-gray-500">No skills assigned</p>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    {agentSkills.map((skill) => (
                      <span
                        key={skill.id}
                        className="inline-flex items-center gap-1 px-2 py-0.5 bg-purple-100 text-purple-700 rounded-full text-xs"
                      >
                        <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                        </svg>
                        {skill.name}
                      </span>
                    ))}
                  </div>
                )}
              </div>

              {/* Read-only Info */}
              <div className="border-t pt-6 mt-6">
                <h3 className="text-sm font-medium text-gray-700 mb-4">Additional Info</h3>
                <dl className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <dt className="text-gray-500">Type</dt>
                    <dd className="font-medium">{agent.agentType === 'ai' ? 'AI' : 'Human'}</dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Hierarchy</dt>
                    <dd className="font-medium">
                      {agent.hierarchyType === 'owner' && 'Owner'}
                      {agent.hierarchyType === 'manager' && 'Manager'}
                      {agent.hierarchyType === 'worker' && 'Worker'}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Role Type</dt>
                    <dd className="font-medium">
                      {agent.roleType === 'owner' && 'Owner'}
                      {agent.roleType === 'manager' && 'Manager'}
                      {agent.roleType === 'general' && 'General'}
                    </dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Kick Method</dt>
                    <dd className="font-medium">{agent.kickMethod.toUpperCase()}</dd>
                  </div>
                  {agent.provider && (
                    <div>
                      <dt className="text-gray-500">Provider</dt>
                      <dd className="font-medium">{agent.provider}</dd>
                    </div>
                  )}
                  {agent.modelId && (
                    <div>
                      <dt className="text-gray-500">Model ID</dt>
                      <dd className="font-medium">{agent.modelId}</dd>
                    </div>
                  )}
                  <div>
                    <dt className="text-gray-500">Created At</dt>
                    <dd className="font-medium">{new Date(agent.createdAt).toLocaleString()}</dd>
                  </div>
                  <div>
                    <dt className="text-gray-500">Updated At</dt>
                    <dd className="font-medium">{new Date(agent.updatedAt).toLocaleString()}</dd>
                  </div>
                </dl>
              </div>
            </div>

            {/* Actions */}
            <div className="flex justify-end gap-3 mt-8 pt-6 border-t">
              <button
                type="button"
                onClick={handleBack}
                className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={isFormDisabled}
                className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {updateAgent.isPending ? 'Saving...' : 'Save'}
              </button>
            </div>
          </form>
        </div>

        {/* Skill Assignment Modal */}
        {showSkillModal && (
          <div className="fixed inset-0 z-50 overflow-y-auto">
            <div className="flex items-center justify-center min-h-screen px-4 pt-4 pb-20 text-center">
              {/* Backdrop */}
              <div
                className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
                onClick={handleCloseSkillModal}
              />

              {/* Modal */}
              <div className="relative bg-white rounded-lg shadow-xl max-w-md w-full mx-auto z-10">
                {/* Header */}
                <div className="flex items-center justify-between p-4 border-b">
                  <h3 className="text-lg font-semibold text-gray-900">Skill Assignment</h3>
                  <button
                    onClick={handleCloseSkillModal}
                    className="text-gray-400 hover:text-gray-500"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>

                {/* Agent Info */}
                <div className="p-4 bg-gray-50 border-b">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 bg-gray-200 rounded-full flex items-center justify-center">
                      <svg className="w-6 h-6 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                      </svg>
                    </div>
                    <div>
                      <div className="font-medium text-gray-900">{agent.name}</div>
                      <div className="text-sm text-gray-500">{agent.role}</div>
                    </div>
                  </div>
                </div>

                {/* Skill List */}
                <div className="p-4 max-h-80 overflow-y-auto">
                  {skillSaveError && (
                    <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-md">
                      <p className="text-sm text-red-700">{skillSaveError}</p>
                    </div>
                  )}

                  {skillsLoading ? (
                    <p className="text-gray-500 text-center py-8">Loading skills...</p>
                  ) : allSkills.length === 0 ? (
                    <div className="text-center py-8">
                      <svg className="w-12 h-12 text-gray-300 mx-auto mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                      </svg>
                      <p className="text-gray-500">No skills available</p>
                      <p className="text-sm text-gray-400 mt-1">Create skills in the macOS app</p>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {allSkills.map((skill) => (
                        <label
                          key={skill.id}
                          className="flex items-start gap-3 p-3 border rounded-md hover:bg-gray-50 cursor-pointer"
                        >
                          <input
                            type="checkbox"
                            checked={selectedSkillIds.has(skill.id)}
                            onChange={() => handleSkillToggle(skill.id)}
                            disabled={assignSkills.isPending}
                            className="mt-0.5 h-4 w-4 text-purple-600 focus:ring-purple-500 border-gray-300 rounded"
                          />
                          <div className="flex-1 min-w-0">
                            <div className="font-medium text-gray-900">{skill.name}</div>
                            {skill.description && (
                              <div className="text-sm text-gray-500 mt-0.5 line-clamp-2">{skill.description}</div>
                            )}
                            <div className="text-xs text-gray-400 mt-1 px-2 py-0.5 bg-gray-100 rounded inline-block">
                              {skill.directoryName}
                            </div>
                          </div>
                        </label>
                      ))}
                    </div>
                  )}
                </div>

                {/* Footer */}
                <div className="flex items-center justify-between p-4 border-t bg-gray-50">
                  <span className="text-sm text-gray-500">
                    {selectedSkillIds.size} skill(s) selected
                  </span>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={handleCloseSkillModal}
                      className="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
                    >
                      Cancel
                    </button>
                    <button
                      type="button"
                      onClick={handleSaveSkills}
                      disabled={assignSkills.isPending}
                      className="px-4 py-2 text-white bg-purple-600 rounded-md hover:bg-purple-700 disabled:opacity-50"
                    >
                      {assignSkills.isPending ? 'Saving...' : 'Save'}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  )
}
