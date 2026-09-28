import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, AREA, fechaLinda, type Agente, type HiloDetalle, type Modo, type Run, type RunEvento } from '../api'
import { AgentSelect, EventLine, ModoSelector, RunBadge, useRunStream, usePoll } from '../components/run'
import { AutoScroll, Badge, Button, EmptyState, Panel, SectionHeader, TextArea } from '../components/ui'
import { Markdown } from '../components/markdown'

function Respuesta({ run, eventos: guardados }: { run: Run; eventos: RunEvento[] }) {
  const activo = run.estado === 'corriendo' || run.estado === 'en_cola'
  const { eventos: vivos } = useRunStream(activo ? run.id : null)
  const [pasos, setPasos] = useState(false)
  const eventos = activo ? vivos : guardados
  const final = [...eventos].reverse().find((e) => e.tipo === 'final')
  const herramientas = eventos.filter((e) => e.tipo === 'herramienta')
  const textos = eventos.filter((e) => e.tipo === 'texto')
  return (
    <div className="border border-border bg-panel px-4 py-3">
      <div className="flex items-center gap-2 mb-2">
        <span className="text-xs text-accent">{run.agente}</span>
        {activo && <RunBadge estado={run.estado} />}
        {run.estado === 'error' && <RunBadge estado="error" />}
        {herramientas.length > 0 && (
          <button onClick={() => setPasos(!pasos)} className="text-[11px] text-muted hover:text-white">
            {pasos ? 'ocultar' : 'ver'} {herramientas.length} paso(s)
          </button>
        )}
      </div>
      {(pasos || activo) && (
        <div className="space-y-1 mb-2 border-l border-border pl-3">
          {eventos.filter((e) => e.tipo === 'herramienta' || e.tipo === 'bloqueo' || (activo && e.tipo === 'sistema')).map((e) => <EventLine key={e.n} ev={e} detalle={false} />)}
        </div>
      )}
      {final ? <Markdown text={final.texto} /> : textos.length > 0 ? <Markdown text={textos[textos.length - 1].texto} /> : activo ? <div className="text-sm text-muted animate-pulse">Pensando…</div> : null}
      {!activo && run.estado === 'error' && !final && <div className="text-sm text-rose-300">{run.resultado}</div>}
      {!activo && run.bloqueos && (
        <div className="mt-2 text-xs text-amber-200 border border-amber-500/30 bg-amber-500/5 px-3 py-2">
          ⛔ Quedó pendiente de tu OK: <span className="font-mono">{run.bloqueos.split('\n').join(' · ')}</span>
        </div>
      )}
    </div>
  )
}

export default function ConversarPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const hiloId = id ? Number(id) : null
  const { data: lista, recargar: recargarLista } = usePoll(api.hilos, 8000)
  const [agentes, setAgentes] = useState<Agente[]>([])
  const [hilo, setHilo] = useState<HiloDetalle | null>(null)
  const hiloRef = useRef<HiloDetalle | null>(null)
  const [texto, setTexto] = useState('')
  const [modo, setModo] = useState<Modo>('carpeta')
  const [nuevoAgente, setNuevoAgente] = useState('agents-orchestrator')
  const [error, setError] = useState('')

  useEffect(() => { api.agents().then((r) => setAgentes(r.agentes)) }, [])

  // El hilo abierto se refresca mientras el agente está respondiendo
  useEffect(() => {
    if (!hiloId) { setHilo(null); return }
    let vivo = true
    const cargar = (conModo: boolean) =>
      api.hilo(hiloId).then((h) => {
        if (!vivo) return
        hiloRef.current = h
        setHilo(h)
        if (conModo) setModo(h.modo)
      }).catch(() => vivo && setHilo(null))
    cargar(true)
    const t = setInterval(() => {
      const h = hiloRef.current
      if (vivo && h && h.mensajes.some((m) => m.estado === 'corriendo' || m.estado === 'en_cola')) cargar(false)
    }, 2500)
    return () => { vivo = false; clearInterval(t) }
  }, [hiloId])

  const ocupado = hilo?.mensajes.some((m) => m.estado === 'corriendo' || m.estado === 'en_cola')

  const enviar = async () => {
    if (!texto.trim() || !hiloId) return
    setError('')
    try {
      await api.sendHilo(hiloId, texto, modo)
      setTexto('')
      const h = await api.hilo(hiloId)
      hiloRef.current = h
      setHilo(h)
      recargarLista()
    } catch (e) {
      setError((e as Error).message)
    }
  }

  const nueva = async () => {
    const h = await api.newHilo(nuevoAgente, 'carpeta')
    recargarLista()
    navigate(`/conversar/${h.id}`)
  }

  const agenteHilo = agentes.find((a) => a.nombre === hilo?.agente)

  return (
    <div>
      <SectionHeader title="Conversar" subtitle="Hablá con cualquier agente como con una persona del equipo. Cada conversación recuerda lo que se dijo." />
      <div className="grid grid-cols-[260px_1fr] gap-5 min-h-[70vh]">
        <div className="space-y-3">
          <Panel className="p-3 space-y-2">
            <div className="text-xs text-muted">Nueva conversación con</div>
            <AgentSelect value={nuevoAgente} onChange={setNuevoAgente} agentes={agentes} />
            <Button onClick={nueva}>Empezar</Button>
          </Panel>
          <div className="space-y-1">
            {lista?.hilos.map((h) => (
              <button
                key={h.id}
                onClick={() => navigate(`/conversar/${h.id}`)}
                className={`w-full text-left px-3 py-2 border transition-colors ${h.id === hiloId ? 'border-accent/60 bg-accent/5' : 'border-transparent hover:bg-panel-raised'}`}
              >
                <div className="text-sm text-white truncate">{h.titulo}</div>
                <div className="text-[11px] text-muted flex gap-2">
                  <span>{h.agente}</span>
                  <span>·</span>
                  <span>{fechaLinda(h.actualizado_en)}</span>
                  {(h.ultimo_estado === 'corriendo' || h.ultimo_estado === 'en_cola') && <span className="text-accent">· respondiendo</span>}
                </div>
              </button>
            ))}
            {lista && lista.hilos.length === 0 && <div className="text-xs text-muted px-3">Todavía no hay conversaciones.</div>}
          </div>
        </div>

        <div className="flex flex-col min-w-0">
          {!hilo ? (
            <EmptyState label="Elegí una conversación o empezá una nueva." />
          ) : (
            <>
              <div className="flex items-center justify-between gap-3 mb-3">
                <div className="min-w-0">
                  <div className="text-white text-sm font-medium truncate">{hilo.titulo}</div>
                  <div className="text-[11px] text-muted">
                    {hilo.agente}{agenteHilo && <> · {AREA[agenteHilo.dominio] ?? agenteHilo.dominio}</>} — {agenteHilo?.descripcion}
                  </div>
                </div>
                <Button small variant="quiet" onClick={() => api.deleteHilo(hilo.id).then(() => { recargarLista(); navigate('/conversar') })}>Borrar</Button>
              </div>
              <AutoScroll deps={JSON.stringify(hilo.mensajes.map((m) => [m.id, m.estado]))} className="flex-1 space-y-4 pr-1 max-h-[58vh]">
                {hilo.mensajes.length === 0 && <div className="text-sm text-muted">Escribí abajo lo que necesitás.</div>}
                {hilo.mensajes.map((m) => (
                  <div key={m.id} className="space-y-2">
                    <div className="flex justify-end">
                      <div className="max-w-[80%] bg-accent/10 border border-accent/30 px-4 py-2 text-sm text-white whitespace-pre-wrap">
                        {m.prompt}
                        <div className="text-[10px] text-muted mt-1 text-right">{m.modo === 'analizar' ? 'solo analizar' : 'puede trabajar'}</div>
                      </div>
                    </div>
                    <Respuesta run={m} eventos={m.eventos} />
                  </div>
                ))}
              </AutoScroll>
              <div className="mt-3 border border-border bg-panel p-3">
                <TextArea
                  rows={3}
                  placeholder={ocupado ? 'El agente está respondiendo…' : 'Escribí tu mensaje (Ctrl+Enter para enviar)'}
                  value={texto}
                  onChange={(e) => setTexto(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) enviar() }}
                  disabled={ocupado}
                />
                <div className="mt-2 flex items-center gap-3">
                  <ModoSelector value={modo} onChange={setModo} compact />
                  {error && <span className="text-xs text-rose-300">{error}</span>}
                  <div className="flex-1" />
                  <Badge>usa tu cuenta de Claude</Badge>
                  <Button onClick={enviar} disabled={ocupado || !texto.trim()}>Enviar</Button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
