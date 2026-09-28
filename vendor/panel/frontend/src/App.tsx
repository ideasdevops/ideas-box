import { Component, useEffect, useState, type ReactNode } from 'react'
import { NavLink, Route, Routes, useLocation } from 'react-router-dom'
import { api, PANEL_API, type Profile } from './api'
import { usePoll } from './components/run'
import { Pulse } from './components/ui'
import HoyPage from './pages/Hoy'
import ConversarPage from './pages/Conversar'
import TareasPage from './pages/Tareas'
import ProgramacionPage from './pages/Programacion'
import ActividadPage from './pages/Actividad'
import AgentesPage from './pages/Agentes'
import SkillsPage from './pages/Skills'
import ServersPage from './pages/Servers'
import MantenimientoPage from './pages/Mantenimiento'

type Item = { to: string; label: string; end?: boolean; badge?: 'curso' | 'revisar' }
const NAV: { grupo: string; items: Item[] }[] = [
  { grupo: '', items: [{ to: '/', label: 'Hoy', end: true, badge: 'revisar' }] },
  {
    grupo: 'Trabajar',
    items: [
      { to: '/conversar', label: 'Conversar' },
      { to: '/tareas', label: 'Tareas' },
      { to: '/programacion', label: 'Programación' },
    ],
  },
  { grupo: 'Mirar', items: [{ to: '/actividad', label: 'Actividad', badge: 'curso' }] },
  {
    grupo: 'Tu equipo',
    items: [
      { to: '/agentes', label: 'Agentes' },
      { to: '/skills', label: 'Habilidades' },
      { to: '/servers', label: 'Servidores' },
    ],
  },
  { grupo: 'Sistema', items: [{ to: '/mantenimiento', label: 'Mantenimiento' }] },
]

// Si una sección falla, se muestra un aviso en vez de dejar la página en blanco
class Resguardo extends Component<{ children: ReactNode; ruta: string }, { error: string | null }> {
  state = { error: null as string | null }
  static getDerivedStateFromError(e: Error) {
    return { error: e.message || String(e) }
  }
  componentDidUpdate(prev: { ruta: string }) {
    if (prev.ruta !== this.props.ruta && this.state.error) this.setState({ error: null })
  }
  render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="border border-rose-500/30 bg-rose-500/5 p-5 text-sm">
        <div className="text-rose-200 font-medium mb-1">Esta sección no se pudo mostrar</div>
        <div className="text-muted mb-3">
          Casi siempre pasa después de actualizar, si quedó corriendo la versión anterior del panel. Reinicialo
          desde Mantenimiento o con <span className="font-mono text-white">ideasbox panel restart</span>.
        </div>
        <div className="text-[11px] text-muted font-mono">{this.state.error}</div>
      </div>
    )
  }
}

function AvisoVersion() {
  const [reiniciando, setReiniciando] = useState(false)
  const reiniciar = async () => {
    setReiniciando(true)
    try {
      await api.restart()
    } catch {
      // un backend muy viejo no tiene este endpoint: queda el comando de la terminal
      setReiniciando(false)
      return
    }
    const esperar = async () => {
      try { const p = await api.profile(); if (p.api === PANEL_API) window.location.reload(); else setTimeout(esperar, 1500) } catch { setTimeout(esperar, 1500) }
    }
    setTimeout(esperar, 3000)
  }
  return (
    <div className="mb-6 border border-amber-500/40 bg-amber-500/10 px-4 py-3 flex items-center gap-4">
      <div className="text-sm text-amber-100 flex-1">
        El panel se actualizó, pero sigue corriendo la versión anterior. Reinicialo para que todo funcione
        (o en la terminal: <span className="font-mono">ideasbox panel restart</span>).
      </div>
      <button onClick={reiniciar} disabled={reiniciando} className="text-sm font-medium px-3 py-1.5 bg-accent text-black hover:bg-accent-dim hover:text-white disabled:opacity-50">
        {reiniciando ? 'Reiniciando…' : 'Reiniciar el panel'}
      </button>
    </div>
  )
}

export default function App() {
  // El panel se rotula con la empresa del perfil del stack, no con una marca fija.
  const [perfil, setPerfil] = useState<Profile | null>(null)
  const { data: prog } = usePoll(api.programacion, 6000)

  useEffect(() => {
    api.profile().then((p) => {
      setPerfil(p)
      document.title = `Ideas Box · ${p.empresa}`
    }).catch(() => setPerfil(null))
  }, [])

  const location = useLocation()
  const desactualizado = perfil !== null && perfil.api !== PANEL_API
  const enCurso = (prog?.corriendo.length ?? 0) + (prog?.en_cola.length ?? 0)
  const paraRevisar = prog?.sugerencias.filter((s) => s.tipo === 'recordatorio').length ?? 0

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 border-r border-border bg-panel flex flex-col sticky top-0 h-screen">
        <div className="px-5 py-5 border-b border-border">
          <div className="text-[12px] uppercase tracking-wider text-muted truncate">{perfil?.empresa || ' '}</div>
          <div className="text-white font-medium">Ideas Box</div>
          <div className="text-[11px] text-muted mt-0.5">Tu compañero de trabajo diario</div>
        </div>
        <nav className="flex-1 px-2 py-2 overflow-y-auto">
          {NAV.map((g) => (
            <div key={g.grupo || 'inicio'} className="mb-2">
              {g.grupo && <div className="px-3 pt-3 pb-1 text-[10px] uppercase tracking-wider text-muted/70">{g.grupo}</div>}
              {g.items.map((item) => {
                const n = item.badge === 'curso' ? enCurso : item.badge === 'revisar' ? paraRevisar : 0
                return (
                  <NavLink
                    key={item.to}
                    to={item.to}
                    end={item.end}
                    className={({ isActive }) =>
                      `flex items-center justify-between px-3 py-2 text-sm transition-colors border-l-2 ${
                        isActive ? 'bg-accent/10 text-accent border-accent' : 'text-muted hover:text-white hover:bg-panel-raised border-transparent'
                      }`
                    }
                  >
                    <span>{item.label}</span>
                    {n > 0 && (
                      <span className="flex items-center gap-1.5 text-[11px]">
                        {item.badge === 'curso' && <Pulse />}
                        <span className={item.badge === 'curso' ? 'text-accent' : 'text-white bg-accent/20 px-1.5'}>{n}</span>
                      </span>
                    )}
                  </NavLink>
                )
              })}
            </div>
          ))}
        </nav>
        <div className="px-5 py-4 border-t border-border text-[11px] text-muted leading-relaxed">
          {perfil && !perfil.claude ? (
            <span className="text-amber-300">No encuentro Claude Code: instalalo desde el menú de Ideas Box.</span>
          ) : (
            <>Los agentes trabajan en tu equipo. Publicar, enviar o desplegar siempre espera tu OK.</>
          )}
        </div>
      </aside>
      <main className="flex-1 p-8 min-w-0 max-w-6xl">
        {desactualizado && <AvisoVersion />}
        <Resguardo ruta={location.pathname}>
        <Routes>
          <Route path="/" element={<HoyPage perfil={perfil} />} />
          <Route path="/conversar" element={<ConversarPage />} />
          <Route path="/conversar/:id" element={<ConversarPage />} />
          <Route path="/tareas" element={<TareasPage />} />
          <Route path="/programacion" element={<ProgramacionPage />} />
          <Route path="/actividad" element={<ActividadPage />} />
          <Route path="/agentes" element={<AgentesPage />} />
          <Route path="/skills" element={<SkillsPage />} />
          <Route path="/servers" element={<ServersPage />} />
          <Route path="/mantenimiento" element={<MantenimientoPage />} />
        </Routes>
        </Resguardo>
      </main>
    </div>
  )
}
