import { Routes, Route, Navigate } from 'react-router-dom'

function App() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to="/login" replace />} />
      <Route path="/login" element={<div>Login Page (TODO)</div>} />
      <Route path="/projects" element={<div>Project List (TODO)</div>} />
      <Route path="/projects/:id" element={<div>Task Board (TODO)</div>} />
      <Route path="*" element={<div>404 Not Found</div>} />
    </Routes>
  )
}

export default App
