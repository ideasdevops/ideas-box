import { useEffect, useState } from 'react'
import { api, AREA, ESTADO_RUN, type Agente, type Modo, type Run, type RunEvento } from '../api'
import { AutoScroll, Badge, Button, Pulse, Select } from './ui'
import { Markdown } from './markdown'

// --- sondeo simple (los datos del panel cambian solos: ejecuciones, programación) ------
export function usePoll<T>(fn: () => Promise<T>, ms: number, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tick, setTick] = useState(0)
  useEffect(() => {
    let vivo = true
    const cargar = () => fn().then((d) => vivo && (setData(d), setError(null))).catch((e) => vivo && setError(String(e.message || e)))
    cargar()
    const h = setInterval(cargar, ms)
    return () => {
      vivo = false
      clearInterval(h)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick])
  return { data, error, recargar: () => setTick((t) => t + 1) }
}

export function RunBadge({ estado }: { estado: Run['estado'] }) {
  const tone = { en_cola: 'default', corriendo: 'accent', ok: 'ok', error: 'danger', cancelado: 'default' } as const
  return (
    <Badge tone={tone[estado]}>
      {estado === 'corriendo' && <Pulse />} {ESTADO_RUN[estado]}
    </Badge>
  )
}

export function ModoSelector({ value, onChange, compact = false }: { value: Modo; onChange: (m: Modo) => void; compact?: boolean }) {
  const ops: { v: Modo; t: string; d: string }[] = [
    { v: 'carpeta', t: 'Puede trabajar', d: 'Crea y edita archivos dentro de la carpeta de la empresa.' },
    { v: 'analizar', t: 'Solo analizar', d: 'Lee y propone; no toca ningún archivo.' },
  ]
  return (
    <div className={compact ? 'flex gap-1' : 'grid grid-cols-2 gap-2'}>
      {ops.map((o) => (
        <button
          key={o.v}
          type="button"
          onClick={() => onChange(o.v)}
          title={o.d}
          className={`text-left border px-3 ${compact ? 'py-1 text-xs' : 'py-2'} transition-colors ${value === o.v ? 'border-accent bg-accent/10 text-accent' : 'border-border text-muted hover:text-white'}`}
        >
          <div className={compact ? '' : 'text-sm'}>{o.t}</div>
          {!compact && <div className="text-[11px] text-muted mt-0.5">{o.d}</div>}
        </button>
      ))}
    </div>
  )
}

export function AgentSelect({ value, onChange, agentes, allowEmpty = false }: { value: string; onChange: (v: string) => void; agentes: Agente[]; allowEmpty?: boolean }) {
  const porArea = agentes.reduce<Record<string, Agente[]>>((acc, a) => ((acc[a.dominio] ??= []).push(a), acc), {})
  return (
    <Select value={value} onChange={(e) => onChange(e.target.value)}>
      {allowEmpty && <option value="">Sin agente (Claude general)</option>}
      {Object.entries(porArea).map(([area, items]) => (
        <optgroup key={area} label={AREA[area] ?? area}>
          {items.map((a) => <option key={a.nombre} value={a.nombre}>{a.nombre}</option>)}
        </optgroup>
      ))}
    </Select>
  )
}

// --- salida en vivo de una ejecución ------------------------------------------------------
export function useRunStream(runId: number | null) {
  const [eventos, setEventos] = useState<RunEvento[]>([])
  const [fin, setFin] = useState<Run['estado'] | null>(null)
  useEffect(() => {
    setEventos([])
    setFin(null)
    if (!runId) return
    const es = new EventSource(`/api/runs/${runId}/stream`)
    es.onmessage = (m) => {
      const ev = JSON.parse(m.data) as RunEvento
      if (ev.tipo === 'fin') {
        setFin(ev.estado ?? 'ok')
        es.close()
        return
      }
      setEventos((prev) => (prev.some((p) => p.n === ev.n) ? prev : [...prev, ev]))
    }
    es.onerror = () => es.close()
    return () => es.close()
  }, [runId])
  return { eventos, fin }
}

export function EventLine({ ev, detalle }: { ev: RunEvento; detalle: boolean }) {
  const hora = <span className="text-[10px] text-muted/70 w-14 shrink-0 font-mono pt-0.5">{ev.t}</span>
  switch (ev.tipo) {
    case 'texto':
    case 'final':
      if (ev.tipo === 'final' && !detalle) return null
      return (
        <div className="flex gap-2">
          {hora}
          <Markdown text={ev.texto} className="flex-1 min-w-0" />
        </div>
      )
    case 'herramienta':
      return (
        <div className="flex gap-2 text-xs">
          {hora}
          <span className="text-sky-300 shrink-0">⚙ {ev.herramienta}</span>
          <span className="text-muted font-mono truncate">{ev.texto}</span>
        </div>
      )
    case 'resultado':
      if (!detalle) return null
      return (
        <div className="flex gap-2 text-[11px]">
          {hora}
          <span className={`font-mono whitespace-pre-wrap break-all ${ev.error ? 'text-rose-300' : 'text-muted/80'}`}>↳ {ev.texto}</span>
        </div>
      )
    case 'bloqueo':
      return (
        <div className="flex gap-2 text-xs">
          {hora}
          <span className="text-amber-300">⛔ Necesita tu OK: <span className="font-mono">{ev.texto}</span></span>
        </div>
      )
    case 'error':
      return <div className="flex gap-2 text-sm">{hora}<span className="text-rose-300">{ev.texto}</span></div>
    case 'linea': {
      const tone = ev.texto.startsWith('✓') ? 'text-emerald-400' : ev.texto.startsWith('✗') ? 'text-rose-400' : ev.texto.startsWith('!') ? 'text-amber-300' : 'text-white/80'
      return <div className={`font-mono text-xs whitespace-pre-wrap break-all ${tone}`}>{ev.texto}</div>
    }
    default:
      return <div className="flex gap-2 text-xs text-muted">{hora}<span>{ev.texto}</span></div>
  }
}

// Vista completa de una ejecución: estado, salida en vivo, resultado y bloqueos
export function RunView({ runId, onChanged }: { runId: number; onChanged?: () => void }) {
  const [run, setRun] = useState<Run | null>(null)
  const [detalle, setDetalle] = useState(false)
  const { eventos, fin } = useRunStream(runId)
  useEffect(() => {
    api.run(runId).then(setRun).catch(() => setRun(null))
  }, [runId, fin])
  if (!run) return <div className="text-sm text-muted">Cargando…</div>
  const estado = fin ?? run.estado
  const activo = estado === 'corriendo' || estado === 'en_cola'
  const final = [...eventos].reverse().find((e) => e.tipo === 'final')
  return (
    <div className="flex flex-col gap-3 min-h-0">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm text-white font-medium">{run.titulo}</span>
            <RunBadge estado={estado} />
            {run.tipo !== 'mantenimiento' && <Badge>{run.modo === 'carpeta' ? 'puede trabajar' : 'solo analiza'}</Badge>}
            {run.origen === 'programada' && <Badge tone="info">programada</Badge>}
          </div>
          <div className="text-[11px] text-muted mt-1">
            {run.agente && <>agente {run.agente} · </>}
            {run.inicio ? `empezó ${run.inicio.slice(11, 16)}` : `pedida ${run.creada_en.slice(11, 16)}`}
            {run.fin && ` · terminó ${run.fin.slice(11, 16)}`}
            {run.costo_usd != null && run.costo_usd > 0 && ` · USD ${run.costo_usd.toFixed(3)}`}
            {run.turnos != null && ` · ${run.turnos} pasos`}
          </div>
        </div>
        <div className="flex gap-1.5 shrink-0">
          {run.tipo !== 'mantenimiento' && <Button small variant="quiet" onClick={() => setDetalle(!detalle)}>{detalle ? 'Menos detalle' : 'Más detalle'}</Button>}
          {activo && <Button small variant="danger" onClick={() => api.cancelRun(run.id).then(onChanged)}>Cancelar</Button>}
          {!activo && !run.revisado && run.tipo === 'tarea' && (
            <Button small variant="ghost" onClick={() => api.reviewedRun(run.id).then(() => { setRun({ ...run, revisado: 1 }); onChanged?.() })}>Marcar revisada</Button>
          )}
        </div>
      </div>
      <AutoScroll deps={eventos.length} className="bg-ink border border-border p-3 space-y-2 max-h-[55vh] min-h-32">
        {eventos.length === 0 && <div className="text-xs text-muted">Esperando…</div>}
        {eventos.map((ev) => <EventLine key={ev.n} ev={ev} detalle={detalle || run.tipo === 'mantenimiento'} />)}
        {activo && <div className="text-accent text-xs animate-pulse">▍</div>}
      </AutoScroll>
      {!activo && final && run.tipo !== 'mantenimiento' && !detalle && (
        <div className="border border-border bg-panel-raised p-4">
          <div className="text-[11px] uppercase tracking-wider text-muted mb-2">Resultado</div>
          <Markdown text={final.texto} />
        </div>
      )}
      {!activo && run.bloqueos && (
        <div className="border border-amber-500/30 bg-amber-500/5 p-3 text-xs text-amber-200">
          <div className="font-medium mb-1">Quedó pendiente de tu aprobación</div>
          <div className="text-amber-100/80 mb-1">El agente quiso hacer esto y el panel no lo permite solo. Si corresponde, hacelo vos o pedíselo en una sesión con Claude.</div>
          <ul className="list-disc pl-4 font-mono">{run.bloqueos.split('\n').map((b) => <li key={b}>{b}</li>)}</ul>
        </div>
      )}
    </div>
  )
}
