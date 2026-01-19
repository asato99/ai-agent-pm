import { Routes, Route, Navigate } from 'react-router-dom'
import { LoginPage, ProjectListPage } from '@/pages'
import { ProtectedRoute } from '@/components/auth'

function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/login" replace />} />
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/projects"
        element={
          <ProtectedRoute>
            <ProjectListPage />
          </ProtectedRoute>
        }
      />
      <Route path="/projects/:id" element={<div>Task Board (TODO)</div>} />
      <Route path="*" element={<div>404 Not Found</div>} />
    </Routes>
  )
}

export default App
