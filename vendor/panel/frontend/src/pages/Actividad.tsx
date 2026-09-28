import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { api, fechaLinda, type SesionEntrada } from '../api'
import { RunBadge, RunView, usePoll } from '../components/run'
import { AutoScroll, Badge, Chips, EmptyState, Pulse, SectionHeader, Tabs } from '../components/ui'
import { Markdown } from '../components/markdown'

function Ejecuciones() {
  const [params, setParams] = useSearchParams()
  const [filtro, setFiltro] = useState<'todas' | 'activas' | 'agentes' | 'mantenimiento'>('todas')
  const q = filtro === 'activas' ? { estado: 'en_cola,corriendo' } : filtro === 'mantenimiento' ? { tipo: 'mantenimiento' } : {}
  const { data, recargar } = usePoll(() => api.runs({ ...q, limite: 80 }), 3000, [filtro])
  const lista = (data?.ejecuciones ?? []).filter((r) => filtro !== 'agentes' || r.tipo !== 'mantenimiento')
  const sel = Number(params.get('run')) || lista[0]?.id || null
  return (
    <div className="grid grid-cols-[320px_1fr] gap-5">
      <div>
        <div className="mb-3">
          <Chips value={filtro} onChange={setFiltro} options={[
            { value: 'todas', label: 'Todas' }, { value: 'activas', label: 'En curso' },
            { value: 'agentes', label: 'Agentes' }, { value: 'mantenimiento', label: 'Mantenimiento' },
          ]} />
        </div>
        <div className="space-y-1 max-h-[70vh] overflow-y-auto pr-1">
          {lista.length === 0 && <EmptyState label="Todavía no hay ejecuciones." />}
          {lista.map((r) => (
            <button key={r.id} onClick={() => setParams({ run: String(r.id) })}
              className={`w-full text-left px-3 py-2 border transition-colors ${r.id === sel ? 'border-accent/60 bg-accent/5' : 'border-border hover:border-accent/30'}`}>
              <div className="flex items-center gap-2">
                <RunBadge estado={r.estado} />
                <span className="text-[11px] text-muted truncate">{r.tipo === 'mantenimiento' ? 'mantenimiento' : r.tipo === 'chat' ? `conversación · ${r.agente}` : r.agente || 'tarea'}</span>
              </div>
              <div className="text-sm text-white truncate mt-1">{r.titulo}</div>
              <div className="text-[10px] text-muted">{fechaLinda(r.inicio ?? r.creada_en)}{r.origen === 'programada' && ' · programada'}</div>
            </button>
          ))}
        </div>
      </div>
      <div className="min-w-0">{sel ? <RunView key={sel} runId={sel} onChanged={recargar} /> : <EmptyState label="Elegí una ejecución para ver qué hizo." />}</div>
    </div>
  )
}

function VisorSesion({ id }: { id: string }) {
  const [entradas, setEntradas] = useState<SesionEntrada[]>([])
  const [activa, setActiva] = useState(false)
  const siguiente = useRef(0)
  const [detalle, setDetalle] = useState(false)
  useEffect(() => {
    let vivo = true
    siguiente.current = 0
    setEntradas([])
    const cargar = () => api.sesion(id, siguiente.current).then((d) => {
      if (!vivo) return
      siguiente.current = d.siguiente
      setActiva(d.activa)
      if (d.entradas.length) setEntradas((prev) => [...prev, ...d.entradas].slice(-600))
    }).catch(() => {})
    cargar()
    const t = setInterval(cargar, 2000)
    return () => { vivo = false; clearInterval(t) }
  }, [id])
  const visibles = entradas.filter((e) => detalle || e.tipo !== 'resultado')
  return (
    <div className="flex flex-col gap-2 min-w-0">
      <div className="flex items-center gap-2 text-xs text-muted">
        {activa ? <><Pulse tone="ok" /> <span className="text-emerald-300">en vivo</span></> : <span>en pausa</span>}
        <span>· solo lectura: muestra lo que pasa en la terminal, no la controla</span>
        <span className="flex-1" />
        <button onClick={() => setDetalle(!detalle)} className="hover:text-white">{detalle ? 'ocultar resultados' : 'mostrar resultados de comandos'}</button>
      </div>
      <AutoScroll deps={entradas.length} className="bg-ink border border-border p-3 space-y-2 h-[66vh]">
        {visibles.length === 0 && <div className="text-xs text-muted">Sin actividad todavía.</div>}
        {visibles.map((e, i) => (
          <div key={`${e.n}-${i}`} className="flex gap-2">
            <span className="text-[10px] text-muted/70 w-14 shrink-0 font-mono pt-0.5">{e.hora}</span>
            {e.tipo === 'pedido' && <div className="flex-1 min-w-0 border-l-2 border-accent pl-2 text-sm text-white whitespace-pre-wrap break-words">{e.texto}</div>}
            {e.tipo === 'texto' && <Markdown text={e.texto} className="flex-1 min-w-0" />}
            {e.tipo === 'herramienta' && <div className="text-xs min-w-0"><span className="text-sky-300">⚙ {e.herramienta}</span> <span className="text-muted font-mono break-all">{e.texto}</span></div>}
            {e.tipo === 'resultado' && <div className={`text-[11px] font-mono whitespace-pre-wrap break-all ${e.error ? 'text-rose-300' : 'text-muted/80'}`}>↳ {e.texto}</div>}
          </div>
        ))}
      </AutoScroll>
    </div>
  )
}

function Terminal() {
  const { data } = usePoll(api.sesiones, 5000)
  const [sel, setSel] = useState<string | null>(null)
  const sesiones = data?.sesiones ?? []
  const actual = sel ?? sesiones.find((s) => s.activa && s.origen === 'terminal')?.id ?? sesiones[0]?.id ?? null
  return (
    <div className="grid grid-cols-[320px_1fr] gap-5">
      <div className="space-y-1 max-h-[74vh] overflow-y-auto pr-1">
        {sesiones.length === 0 && <EmptyState label="No hay sesiones de Claude Code en los últimos días." />}
        {sesiones.map((s) => (
          <button key={s.id} onClick={() => setSel(s.id)}
            className={`w-full text-left px-3 py-2 border transition-colors ${s.id === actual ? 'border-accent/60 bg-accent/5' : 'border-border hover:border-accent/30'}`}>
            <div className="flex items-center gap-2">
              {s.activa ? <Pulse tone="ok" /> : <span className="w-2 h-2 rounded-full bg-border" />}
              <Badge tone={s.origen === 'terminal' ? 'info' : 'default'}>{s.origen === 'terminal' ? 'terminal' : 'panel'}</Badge>
              <span className="text-[10px] text-muted">{fechaLinda(s.actualizada)}</span>
            </div>
            <div className="text-sm text-white truncate mt-1">{s.titulo}</div>
            <div className="text-[10px] text-muted truncate">{s.carpeta} · {s.mensajes} mensajes</div>
          </button>
        ))}
      </div>
      <div className="min-w-0">{actual ? <VisorSesion key={actual} id={actual} /> : <EmptyState label="Elegí una sesión." />}</div>
    </div>
  )
}

export default function ActividadPage() {
  const [tab, setTab] = useState<'panel' | 'terminal'>('panel')
  return (
    <div>
      <SectionHeader title="Actividad" subtitle="Para mirar qué están haciendo tus agentes, paso a paso. Nada de esto se puede tocar desde acá: es un control visual." />
      <Tabs value={tab} onChange={setTab} options={[
        { value: 'panel', label: 'Lo que hace el panel' },
        { value: 'terminal', label: 'Terminal (sesiones de Claude)' },
      ]} />
      {tab === 'panel' ? <Ejecuciones /> : <Terminal />}
    </div>
  )
}
