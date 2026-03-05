import { useState } from 'react'
import { AppHeader } from '@/components/layout/AppHeader/AppHeader'
import { GeneralSettings } from '@/components/settings/GeneralSettings'
import { CoordinatorSettings } from '@/components/settings/CoordinatorSettings'
import { RunnerSetupSection } from '@/components/settings/RunnerSetupSection'
import { useSettings, useUpdateSettings, useRegenerateToken, useClearToken } from '@/hooks'

const TABS = ['General', 'Coordinator', 'Runner Setup'] as const
type Tab = (typeof TABS)[number]

export function SettingsPage() {
  const [activeTab, setActiveTab] = useState<Tab>('General')
  const { settings, isLoading, error } = useSettings()
  const updateSettings = useUpdateSettings()
  const regenerateToken = useRegenerateToken()
  const clearToken = useClearToken()

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-gray-500">Loading settings...</p>
        </main>
      </div>
    )
  }

  if (error || !settings) {
    return (
      <div className="min-h-screen bg-gray-100">
        <AppHeader />
        <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <p className="text-red-500">Failed to load settings: {error?.message}</p>
        </main>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-100">
      <AppHeader />
      <main className="max-w-3xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <h2 className="text-2xl font-bold text-gray-900 mb-6">Settings</h2>

        {/* Tab Navigation */}
        <div className="border-b border-gray-200 mb-6">
          <nav className="flex gap-4">
            {TABS.map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`pb-3 px-1 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                {tab}
              </button>
            ))}
          </nav>
        </div>

        {/* Tab Content */}
        <div className="bg-white rounded-lg shadow p-6">
          {activeTab === 'General' && (
            <GeneralSettings
              settings={settings}
              onUpdate={(data) => updateSettings.mutate(data)}
              isUpdating={updateSettings.isPending}
            />
          )}

          {activeTab === 'Coordinator' && (
            <CoordinatorSettings
              settings={settings}
              onToggleRemoteAccess={(allow) =>
                updateSettings.mutate({ allowRemoteAccess: allow })
              }
              onRegenerateToken={() => regenerateToken.mutate()}
              onClearToken={() => clearToken.mutate()}
              isUpdating={updateSettings.isPending}
              isRegenerating={regenerateToken.isPending}
              isClearing={clearToken.isPending}
            />
          )}

          {activeTab === 'Runner Setup' && (
            <RunnerSetupSection settings={settings} />
          )}
        </div>
      </main>
    </div>
  )
}
