import { useEffect, useState } from 'react'
import { NavLink, Route, Routes } from 'react-router-dom'
import { api } from './api'
import ChatPage from './pages/Chat'
import AgentesPage from './pages/Agentes'
import SkillsPage from './pages/Skills'
import TareasPage from './pages/Tareas'
import ServersPage from './pages/Servers'

const NAV = [
  { to: '/', label: 'Chat', end: true },
  { to: '/agentes', label: 'Agentes' },
  { to: '/skills', label: 'Skills' },
  { to: '/tareas', label: 'Tareas' },
  { to: '/servers', label: 'Servidores' },
]

export default function App() {
  // El panel se rotula con la empresa del perfil del stack, no con una marca fija.
  const [empresa, setEmpresa] = useState('')

  useEffect(() => {
    api
      .profile()
      .then((p) => {
        setEmpresa(p.empresa)
        document.title = `Panel de ${p.empresa}`
      })
      .catch(() => setEmpresa(''))
  }, [])

  return (
    <div className="min-h-screen flex">
      <aside className="w-56 shrink-0 border-r border-border bg-panel flex flex-col">
        <div className="px-5 py-5 border-b border-border">
          <div className="text-[13px] uppercase tracking-wider text-muted">{empresa || '\u00a0'}</div>
          <div className="text-white font-medium">Panel de comando</div>
        </div>
        <nav className="flex-1 px-2 py-3 space-y-0.5">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                `block px-3 py-2 text-sm transition-colors ${
                  isActive ? 'bg-accent/10 text-accent border-l-2 border-accent' : 'text-muted hover:text-white hover:bg-panel-raised border-l-2 border-transparent'
                }`
              }
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="px-5 py-4 border-t border-border text-[11px] text-muted">
          Agentes y skills se leen de tu raíz de datos. El panel no publica ni despliega solo.
        </div>
      </aside>
      <main className="flex-1 p-8 max-w-5xl">
        <Routes>
          <Route path="/" element={<ChatPage />} />
          <Route path="/agentes" element={<AgentesPage />} />
          <Route path="/skills" element={<SkillsPage />} />
          <Route path="/tareas" element={<TareasPage />} />
          <Route path="/servers" element={<ServersPage />} />
        </Routes>
      </main>
    </div>
  )
}
