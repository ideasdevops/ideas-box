import { useEffect, useState } from 'react'
import { api, AREA, type Skill, type SkillFicha } from '../api'
import { Badge, Chips, EmptyState, Input, Modal, Panel, SectionHeader } from '../components/ui'
import { Markdown } from '../components/markdown'

function Ficha({ s, onClose }: { s: Skill; onClose: () => void }) {
  const [f, setF] = useState<SkillFicha | null>(null)
  useEffect(() => { api.skill(s.dominio, s.carpeta).then(setF) }, [s])
  return (
    <Modal title={s.nombre} wide onClose={onClose}>
      <div className="flex gap-2 mb-3 flex-wrap">
        <Badge tone="accent">{AREA[s.dominio] ?? s.dominio}</Badge>
        <Badge>{s.origen === 'propia' ? 'propia' : `pack ${s.origen}`}</Badge>
        <span className="text-[11px] text-muted font-mono">{s.dominio}/{s.carpeta}</span>
      </div>
      <p className="text-sm text-white/85 mb-4">{s.descripcion}</p>
      {!f ? <div className="text-sm text-muted">Cargando…</div> : (
        <>
          <div className="text-xs text-muted mb-4">
            {f.agentes.length ? <>La usan: {f.agentes.map((a) => <Badge key={a}>{a}</Badge>)}</> : 'Ningún agente la menciona explícitamente: cualquiera puede usarla si el pedido lo amerita.'}
          </div>
          <div className="border border-border bg-panel-raised p-4 max-h-[55vh] overflow-y-auto"><Markdown text={f.contenido} /></div>
        </>
      )}
    </Modal>
  )
}

export default function SkillsPage() {
  const [skills, setSkills] = useState<Skill[] | null>(null)
  const [area, setArea] = useState('todas')
  const [origen, setOrigen] = useState('todas')
  const [q, setQ] = useState('')
  const [abierta, setAbierta] = useState<Skill | null>(null)
  useEffect(() => { api.skills().then((r) => setSkills(r.skills)) }, [])
  if (!skills) return <EmptyState label="Cargando…" />

  const areas = [...new Set(skills.map((s) => s.dominio))]
  const origenes = [...new Set(skills.map((s) => s.origen))].sort((a, b) => (a === 'propia' ? -1 : b === 'propia' ? 1 : a.localeCompare(b)))
  const filtradas = skills.filter((s) =>
    (area === 'todas' || s.dominio === area) && (origen === 'todas' || s.origen === origen) &&
    (!q || `${s.nombre} ${s.descripcion}`.toLowerCase().includes(q.toLowerCase())))
  const grupos = areas.map((a) => [a, filtradas.filter((s) => s.dominio === a)] as const).filter(([, v]) => v.length)

  return (
    <div>
      <SectionHeader title="Habilidades" subtitle={`${skills.length} procedimientos que tus agentes saben seguir. Las propias son de Ideas Box o creadas por tu empresa; el resto viene de packs abiertos.`}
        action={<Input placeholder="Buscar…" value={q} onChange={(e) => setQ(e.target.value)} className="!w-64" />} />
      <div className="space-y-2 mb-5">
        <Chips value={area} onChange={setArea} options={[{ value: 'todas', label: 'Todas las áreas' }, ...areas.map((a) => ({ value: a, label: `${AREA[a] ?? a} (${skills.filter((s) => s.dominio === a).length})` }))]} />
        <Chips value={origen} onChange={setOrigen} options={[{ value: 'todas', label: 'Todos los orígenes' }, ...origenes.map((o) => ({ value: o, label: o === 'propia' ? 'Propias' : `Pack ${o}` }))]} />
      </div>
      {grupos.length === 0 && <EmptyState label="Ninguna habilidad coincide." />}
      <div className="space-y-6">
        {grupos.map(([a, items]) => (
          <section key={a}>
            <div className="text-xs uppercase tracking-wider text-muted mb-2">{AREA[a] ?? a} · {items.length}</div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-2">
              {items.map((s) => (
                <button key={`${s.dominio}/${s.carpeta}`} onClick={() => setAbierta(s)} className="text-left">
                  <Panel className="p-3 h-full hover:border-accent/50 transition-colors">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm text-white truncate">{s.nombre}</span>
                      <Badge tone={s.origen === 'propia' ? 'accent' : 'default'}>{s.origen === 'propia' ? 'propia' : s.origen}</Badge>
                    </div>
                    <p className="text-xs text-muted leading-relaxed line-clamp-2 mt-1">{s.descripcion}</p>
                  </Panel>
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>
      {abierta && <Ficha s={abierta} onClose={() => setAbierta(null)} />}
    </div>
  )
}
