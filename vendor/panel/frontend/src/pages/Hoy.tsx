import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api, fechaLinda, type Agente, type Modo, type Profile, type Sugerencia } from '../api'
import { AgentSelect, ModoSelector, RunBadge, RunView, usePoll } from '../components/run'
import { Badge, Button, EmptyState, Input, Modal, Panel, TextArea } from '../components/ui'

function saludo() {
  const h = new Date().getHours()
  return h < 12 ? 'Buen día' : h < 20 ? 'Buenas tardes' : 'Buenas noches'
}

// Ejecuta la acción que propone una sugerencia (o lleva a donde se resuelve)
export function useAccionSugerencia(recargar: () => void) {
  const navigate = useNavigate()
  const [runVisible, setRunVisible] = useState<number | null>(null)
  const ejecutar = async (s: Sugerencia) => {
    const a = s.accion
    if (!a) return
    if (a.tipo === 'mantenimiento') {
      const { run_id } = await api.maint({ accion: a.accion })
      setRunVisible(run_id)
    } else if (a.tipo === 'ir') navigate(a.a)
    else if (a.tipo === 'ejecucion') setRunVisible(a.id)
    else if (a.tipo === 'tarea') navigate(`/tareas?ver=${a.id}`)
    else if (a.tipo === 'recordatorio') {
      await api.doneRecordatorio(a.id)
      recargar()
    }
  }
  const modal = runVisible && (
    <Modal title="Ejecución" wide onClose={() => { setRunVisible(null); recargar() }}>
      <RunView runId={runVisible} onChanged={recargar} />
    </Modal>
  )
  return { ejecutar, modal }
}

export function SugerenciaFila({ s, onAccion }: { s: Sugerencia; onAccion: (s: Sugerencia) => void }) {
  const tono = s.nivel === 'alerta' ? 'border-l-rose-400' : s.nivel === 'accion' ? 'border-l-accent' : 'border-l-sky-400'
  const boton =
    s.accion?.tipo === 'mantenimiento' ? 'Hacerlo ahora' :
    s.accion?.tipo === 'ejecucion' ? 'Ver resultado' :
    s.accion?.tipo === 'recordatorio' ? 'Listo' :
    s.accion?.tipo === 'tarea' ? 'Ver tarea' : 'Ir'
  return (
    <div className={`flex items-center gap-3 border border-border border-l-2 ${tono} bg-panel px-4 py-3`}>
      <div className="min-w-0 flex-1">
        <div className="text-sm text-white">{s.titulo}</div>
        {s.detalle && <div className="text-xs text-muted mt-0.5">{s.detalle}</div>}
      </div>
      {s.accion && <Button small variant="ghost" onClick={() => onAccion(s)}>{boton}</Button>}
    </div>
  )
}

export default function HoyPage({ perfil }: { perfil: Profile | null }) {
  const navigate = useNavigate()
  const { data: prog, recargar } = usePoll(api.programacion, 5000)
  const [agentes, setAgentes] = useState<Agente[]>([])
  const [pedido, setPedido] = useState('')
  const [agente, setAgente] = useState('agents-orchestrator')
  const [modo, setModo] = useState<Modo>('carpeta')
  const [enviando, setEnviando] = useState(false)
  const [recordatorio, setRecordatorio] = useState('')
  const { ejecutar, modal } = useAccionSugerencia(recargar)

  useEffect(() => {
    api.agents().then((r) => {
      setAgentes(r.agentes)
      if (!r.agentes.some((a) => a.nombre === 'agents-orchestrator') && r.agentes[0]) setAgente(r.agentes[0].nombre)
    })
  }, [])

  const pedir = async () => {
    if (!pedido.trim()) return
    setEnviando(true)
    try {
      const h = await api.newHilo(agente, modo)
      await api.sendHilo(h.id, pedido, modo)
      navigate(`/conversar/${h.id}`)
    } catch (e) {
      alert((e as Error).message)
      setEnviando(false)
    }
  }

  const recordatorios = prog?.sugerencias.filter((s) => s.tipo === 'recordatorio') ?? []
  const recomendaciones = prog?.sugerencias.filter((s) => s.tipo === 'recomendacion') ?? []
  const enCurso = [...(prog?.corriendo ?? []), ...(prog?.en_cola ?? [])]
  const fecha = new Date().toLocaleDateString('es', { weekday: 'long', day: 'numeric', month: 'long' })

  return (
    <div>
      <div className="mb-6">
        <div className="text-xs uppercase tracking-wider text-muted">{fecha}</div>
        <h1 className="text-2xl font-medium tracking-tight text-white mt-1">
          {saludo()}{perfil?.responsable ? `, ${perfil.responsable.split(' ')[0]}` : ''}.
        </h1>
        <p className="text-sm text-muted mt-1">
          {enCurso.length > 0 ? `${enCurso.length} trabajo(s) en marcha` : 'Nada corriendo ahora'}
          {recordatorios.length > 0 && ` · ${recordatorios.length} cosa(s) esperan tu atención`}
          {prog?.proximas[0] && ` · lo próximo: «${prog.proximas[0].titulo}» ${fechaLinda(prog.proximas[0].cuando)}`}
        </p>
      </div>

      <Panel className="p-4 mb-6">
        <div className="text-sm text-white mb-2">¿En qué te ayudo hoy?</div>
        <TextArea
          rows={2}
          placeholder="Ej: armá una propuesta para el cliente Pérez con lo que hablamos ayer · resumí los pendientes de la semana · preparame 3 ideas de posteo"
          value={pedido}
          onChange={(e) => setPedido(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) pedir() }}
        />
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <div className="w-60"><AgentSelect value={agente} onChange={setAgente} agentes={agentes} /></div>
          <ModoSelector value={modo} onChange={setModo} compact />
          <div className="flex-1" />
          <Button onClick={pedir} disabled={enviando || !pedido.trim()}>{enviando ? 'Enviando…' : 'Pedírselo'}</Button>
        </div>
      </Panel>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <section>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Te esperan</h2>
          <div className="space-y-2">
            {recordatorios.length === 0 && <EmptyState label="Nada pendiente de tu parte. 👌" />}
            {recordatorios.map((s) => <SugerenciaFila key={s.clave} s={s} onAccion={ejecutar} />)}
          </div>
          <form className="mt-2 flex gap-2" onSubmit={(e) => { e.preventDefault(); if (recordatorio.trim()) api.newRecordatorio(recordatorio, null).then(() => { setRecordatorio(''); recargar() }) }}>
            <Input placeholder="Anotar un recordatorio…" value={recordatorio} onChange={(e) => setRecordatorio(e.target.value)} />
            <Button type="submit" variant="ghost" disabled={!recordatorio.trim()}>Anotar</Button>
          </form>
        </section>

        <section>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">En marcha</h2>
          <div className="space-y-2">
            {enCurso.length === 0 && <EmptyState label="Ningún agente trabajando ahora." />}
            {enCurso.map((r) => (
              <button key={r.id} onClick={() => navigate(`/actividad?run=${r.id}`)} className="w-full text-left flex items-center gap-3 border border-border bg-panel px-4 py-3 hover:border-accent/40">
                <RunBadge estado={r.estado} />
                <span className="text-sm text-white truncate flex-1">{r.titulo}</span>
                <span className="text-[11px] text-muted">{r.agente || r.accion}</span>
              </button>
            ))}
          </div>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2 mt-6">Próximamente</h2>
          <div className="space-y-1">
            {(prog?.proximas ?? []).length === 0 && <EmptyState label="No hay nada programado."><Button small variant="ghost" onClick={() => navigate('/tareas?nueva=1')}>Programar una tarea</Button></EmptyState>}
            {(prog?.proximas ?? []).slice(0, 6).map((p) => (
              <div key={`${p.tarea_id}-${p.cuando}`} className="flex items-center gap-3 px-3 py-2 border-b border-border text-sm">
                <span className="text-muted w-32 shrink-0 text-xs">{fechaLinda(p.cuando)}</span>
                <span className="text-white truncate flex-1">{p.titulo}</span>
                <Badge tone={p.ejecucion === 'auto' ? 'accent' : 'default'}>{p.ejecucion === 'auto' ? 'se ejecuta sola' : 'recordatorio'}</Badge>
              </div>
            ))}
          </div>
        </section>
      </div>

      {recomendaciones.length > 0 && (
        <section className="mt-8">
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Recomendaciones para hoy</h2>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-2">
            {recomendaciones.map((s) => <SugerenciaFila key={s.clave} s={s} onAccion={ejecutar} />)}
          </div>
        </section>
      )}
      {modal}
    </div>
  )
}
