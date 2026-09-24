import { useEffect, useState } from 'react'
import { api, type Skill } from '../api'
import { Badge, Panel, SectionHeader, EmptyState } from '../components/ui'

export default function SkillsPage() {
  const [skills, setSkills] = useState<Skill[] | null>(null)
  const [q, setQ] = useState('')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const handle = setTimeout(() => {
      api.skills(q || undefined).then((r) => setSkills(r.skills)).catch((e) => setError(String(e)))
    }, 150)
    return () => clearTimeout(handle)
  }, [q])

  return (
    <div>
      <SectionHeader
        title="Catálogo de skills"
        subtitle={skills ? `${skills.length} skill(s)` : 'Cargando...'}
        action={
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Buscar por nombre o descripción..."
            className="bg-panel-raised border border-border px-3 py-1.5 text-sm text-white placeholder:text-muted w-72 focus:outline-none focus:border-accent"
          />
        }
      />
      {error && <EmptyState label={`Error: ${error}`} />}
      {!error && skills && skills.length === 0 && <EmptyState label="Sin resultados" />}
      <div className="space-y-2">
        {skills?.map((s) => (
          <Panel key={`${s.dominio}/${s.carpeta}`} className="p-3 flex items-start gap-3">
            <Badge tone="accent">{s.dominio}</Badge>
            <div className="min-w-0">
              <div className="text-sm font-medium text-white">{s.nombre}</div>
              <p className="text-xs text-muted leading-relaxed line-clamp-2">{s.descripcion}</p>
            </div>
          </Panel>
        ))}
      </div>
    </div>
  )
}
