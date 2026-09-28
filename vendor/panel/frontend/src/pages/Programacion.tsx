import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api, fechaLinda, type Proxima } from '../api'
import { RunBadge, RunView, usePoll } from '../components/run'
import { Badge, Button, EmptyState, Input, Modal, Panel, SectionHeader } from '../components/ui'
import { SugerenciaFila, useAccionSugerencia } from './Hoy'

function porDia(items: Proxima[]) {
  const grupos: Record<string, Proxima[]> = {}
  for (const p of items) {
    const d = new Date(p.cuando)
    const hoy = new Date()
    const manana = new Date(hoy.getTime() + 86400000)
    const clave = d.toDateString() === hoy.toDateString() ? 'Hoy' : d.toDateString() === manana.toDateString() ? 'Mañana'
      : d.toLocaleDateString('es', { weekday: 'long', day: 'numeric', month: 'long' })
    ;(grupos[clave] ??= []).push(p)
  }
  return Object.entries(grupos)
}

export function localAhoraMas(horas: number) {
  const d = new Date(Date.now() + horas * 3600000)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16)
}

export default function ProgramacionPage() {
  const navigate = useNavigate()
  const { data: p, recargar } = usePoll(api.programacion, 4000)
  const [runVisible, setRunVisible] = useState<number | null>(null)
  const [texto, setTexto] = useState('')
  const [cuando, setCuando] = useState('')
  const { ejecutar, modal } = useAccionSugerencia(recargar)

  if (!p) return <EmptyState label="Cargando…" />
  const recomendaciones = p.sugerencias.filter((s) => s.tipo === 'recomendacion')

  return (
    <div>
      <SectionHeader
        title="Programación"
        subtitle="Qué está trabajando tu equipo ahora, qué espera turno, qué viene y qué conviene hacer."
        action={<Button onClick={() => navigate('/tareas?nueva=1')}>+ Programar una tarea</Button>}
      />

      {!p.autostart && p.proximas.some((x) => x.ejecucion === 'auto') && (
        <div className="mb-5 border border-amber-500/30 bg-amber-500/5 px-4 py-3 flex items-center gap-3">
          <div className="text-sm text-amber-100 flex-1">Las tareas que se ejecutan solas necesitan el panel abierto. Activá el arranque automático para no depender de acordarte.</div>
          <Button small onClick={() => api.autostart(true).then(recargar).catch((e) => alert(e.message))}>Activarlo</Button>
        </div>
      )}

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <section>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">En curso</h2>
          {p.corriendo.length === 0 && <EmptyState label="Ningún agente trabajando ahora." />}
          <div className="space-y-2">
            {p.corriendo.map((r) => (
              <Panel key={r.id} className="p-3">
                <div className="flex items-center gap-2">
                  <RunBadge estado={r.estado} />
                  <span className="text-sm text-white truncate flex-1">{r.titulo}</span>
                  <span className="text-[11px] text-muted">{r.agente || r.accion} · desde {r.inicio?.slice(11, 16)}</span>
                  <Button small variant="ghost" onClick={() => setRunVisible(r.id)}>Mirar</Button>
                </div>
              </Panel>
            ))}
          </div>

          <h2 className="text-xs uppercase tracking-wider text-muted mb-2 mt-6">En la fila</h2>
          {p.en_cola.length === 0 && <EmptyState label="Nada esperando turno." />}
          <div className="space-y-1">
            {p.en_cola.map((r, i) => (
              <div key={r.id} className="flex items-center gap-3 px-3 py-2 border border-border text-sm">
                <span className="text-muted text-xs w-5">{i + 1}.</span>
                <span className="text-white truncate flex-1">{r.titulo}</span>
                {r.origen === 'programada' && <Badge tone="info">programada</Badge>}
                <Button small variant="quiet" onClick={() => api.cancelRun(r.id).then(recargar)}>Sacar de la fila</Button>
              </div>
            ))}
          </div>

          {p.vencidas.length > 0 && (
            <>
              <h2 className="text-xs uppercase tracking-wider text-rose-300 mb-2 mt-6">Vencidas (esperan que las lances)</h2>
              <div className="space-y-1">
                {p.vencidas.map((t) => (
                  <div key={t.id} className="flex items-center gap-3 px-3 py-2 border border-rose-500/30 bg-rose-500/5 text-sm">
                    <span className="text-white truncate flex-1">{t.titulo}</span>
                    <span className="text-[11px] text-muted">{fechaLinda(t.programada_para)}</span>
                    <Button small onClick={() => api.runTask(t.id).then(({ run_id }) => { setRunVisible(run_id); recargar() }).catch((e) => alert(e.message))}>Lanzar</Button>
                    <Button small variant="ghost" onClick={() => api.updateTask(t.id, { estado: 'hecho' }).then(recargar)}>Hecha</Button>
                  </div>
                ))}
              </div>
            </>
          )}

          <h2 className="text-xs uppercase tracking-wider text-muted mb-2 mt-6">Terminadas hace poco</h2>
          <div className="space-y-1">
            {p.recientes.map((r) => (
              <button key={r.id} onClick={() => setRunVisible(r.id)} className="w-full text-left flex items-center gap-3 px-3 py-2 border border-border hover:border-accent/40 text-sm">
                <RunBadge estado={r.estado} />
                <span className="text-white truncate flex-1">{r.titulo}</span>
                <span className="text-[11px] text-muted">{fechaLinda(r.fin)}</span>
              </button>
            ))}
          </div>
        </section>

        <section>
          <h2 className="text-xs uppercase tracking-wider text-muted mb-2">Próximas (14 días)</h2>
          {p.proximas.length === 0 && <EmptyState label="No hay nada programado." />}
          <div className="space-y-4">
            {porDia(p.proximas).map(([dia, items]) => (
              <div key={dia}>
                <div className="text-xs text-white mb-1 capitalize">{dia}</div>
                <div className="space-y-1">
                  {items.map((x) => (
                    <div key={`${x.tarea_id}-${x.cuando}`} className="flex items-center gap-3 px-3 py-2 border border-border text-sm">
                      <span className="text-muted text-xs w-12">{x.cuando.slice(11, 16)}</span>
                      <span className="text-white truncate flex-1">{x.titulo}</span>
                      {x.recurrencia !== 'ninguna' && <span className="text-[11px] text-muted">↻</span>}
                      <Badge tone={x.ejecucion === 'auto' ? 'accent' : 'default'}>{x.ejecucion === 'auto' ? 'sola' : 'recordar'}</Badge>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>

          <h2 className="text-xs uppercase tracking-wider text-muted mb-2 mt-6">Recordatorios</h2>
          <form className="flex gap-2 mb-2" onSubmit={(e) => { e.preventDefault(); if (texto.trim()) api.newRecordatorio(texto, cuando || null).then(() => { setTexto(''); setCuando(''); recargar() }) }}>
            <Input placeholder="Qué recordar" value={texto} onChange={(e) => setTexto(e.target.value)} />
            <Input type="datetime-local" value={cuando} onChange={(e) => setCuando(e.target.value)} className="!w-56" />
            <Button type="submit" variant="ghost" disabled={!texto.trim()}>Anotar</Button>
          </form>
          <div className="space-y-1">
            {p.recordatorios.length === 0 && <div className="text-xs text-muted">Sin recordatorios.</div>}
            {p.recordatorios.map((r) => (
              <div key={r.id} className="flex items-center gap-3 px-3 py-2 border border-border text-sm">
                <span className="text-white flex-1">{r.texto}</span>
                {r.cuando && <span className="text-[11px] text-muted">{fechaLinda(r.cuando)}</span>}
                <Button small variant="ghost" onClick={() => api.doneRecordatorio(r.id).then(recargar)}>Listo</Button>
              </div>
            ))}
          </div>

          <h2 className="text-xs uppercase tracking-wider text-muted mb-2 mt-6">Recomendaciones</h2>
          <div className="space-y-2">
            {recomendaciones.length === 0 && <div className="text-xs text-muted">Todo en orden por ahora.</div>}
            {recomendaciones.map((s) => <SugerenciaFila key={s.clave} s={s} onAccion={ejecutar} />)}
          </div>
        </section>
      </div>
      {runVisible && <Modal title="Ejecución" wide onClose={() => { setRunVisible(null); recargar() }}><RunView runId={runVisible} onChanged={recargar} /></Modal>}
      {modal}
    </div>
  )
}
