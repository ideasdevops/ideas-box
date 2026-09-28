import { useEffect, useMemo, useState } from 'react'
import { api, slugify, token } from './api'
import type { DataRoot, Info, Mcp } from './api'
import { Badge, Button, Callout, ChoiceCard, Panel, SectionHeader, SelectField, Spinner, TextField } from './ui'
import Progress from './Progress'

type McpAnswer = { id: string; on: boolean; creds: Record<string, string>; label: string; login: boolean }
type Answers = {
  resume: boolean
  empresa: { nombre: string; slug: string; rubro: string; sitio: string; responsable: string; idioma: string; tz: string }
  dataRoot: string
  packs: { id: string; on: boolean }[]
  mcps: McpAnswer[]
  extras: { media: boolean; docker: boolean; panel: boolean; shortcuts: boolean }
}

const STEPS = [
  { id: 'bienvenida', label: 'Bienvenida' },
  { id: 'empresa', label: 'Tu empresa' },
  { id: 'datos', label: 'Dónde guardar' },
  { id: 'habilidades', label: 'Habilidades' },
  { id: 'conectores', label: 'Conectores' },
  { id: 'extras', label: 'Extras' },
  { id: 'revisar', label: 'Revisar e instalar' },
] as const
type StepId = (typeof STEPS)[number]['id']

const OS_LABEL: Record<string, string> = { mac: 'Mac', linux: 'Linux', wsl: 'Windows (Ubuntu en WSL)' }

export default function App() {
  const [info, setInfo] = useState<Info | null>(null)
  const [error, setError] = useState('')
  const [step, setStep] = useState<StepId>('bienvenida')
  const [installing, setInstalling] = useState(false)
  const [a, setA] = useState<Answers | null>(null)

  useEffect(() => {
    if (!token) {
      setError('Abrí el asistente desde el enlace que muestra la terminal (incluye una clave de acceso).')
      return
    }
    api
      .info()
      .then((i) => {
        setInfo(i)
        setA(initialAnswers(i))
        // Recargar la página a mitad de instalación vuelve directo al progreso
        if (i.status !== 'idle') setInstalling(true)
      })
      .catch((e) => setError(String(e.message || e)))
  }, [])

  if (error) return <Centered><Callout tone="danger">{error}</Callout></Centered>
  if (!info || !a) return <Centered><Spinner /> <span className="text-sm text-muted ml-2">Preparando el asistente…</span></Centered>
  if (installing) {
    return (
      <Shell info={info} current={null}>
        <Progress info={info} answers={a} onEdit={() => { setStep('revisar'); setInstalling(false) }} />
      </Shell>
    )
  }

  const upd = (f: (x: Answers) => Answers) => setA((x) => (x ? f(x) : x))
  const idx = STEPS.findIndex((s) => s.id === step)
  const go = (d: number) => setStep(STEPS[Math.min(STEPS.length - 1, Math.max(0, idx + d))].id)
  const start = async (resume: boolean) => {
    try {
      await api.start({ ...a, resume })
      setInstalling(true)
    } catch (e) {
      setError(String((e as Error).message || e))
    }
  }

  return (
    <Shell info={info} current={step} onJump={(s) => STEPS.findIndex((x) => x.id === s) < idx && setStep(s)}>
      {step === 'bienvenida' && <Bienvenida info={info} onResume={() => start(true)} onNext={() => go(1)} />}
      {step === 'empresa' && <Empresa a={a} setA={upd} onBack={() => go(-1)} onNext={() => go(1)} />}
      {step === 'datos' && <Datos a={a} setA={upd} onBack={() => go(-1)} onNext={() => go(1)} />}
      {step === 'habilidades' && <Habilidades info={info} a={a} setA={upd} onBack={() => go(-1)} onNext={() => go(1)} />}
      {step === 'conectores' && <Conectores info={info} a={a} setA={upd} onBack={() => go(-1)} onNext={() => go(1)} />}
      {step === 'extras' && <Extras info={info} a={a} setA={upd} onBack={() => go(-1)} onNext={() => go(1)} />}
      {step === 'revisar' && <Revisar info={info} a={a} onBack={() => go(-1)} onInstall={() => start(false)} />}
    </Shell>
  )
}

function initialAnswers(i: Info): Answers {
  const p = i.profile
  return {
    resume: false,
    empresa: {
      nombre: p.EMPRESA_NOMBRE || '',
      slug: p.EMPRESA_SLUG || '',
      rubro: p.EMPRESA_RUBRO || '',
      sitio: p.EMPRESA_SITIO || '',
      responsable: p.EMPRESA_RESPONSABLE || '',
      idioma: p.EMPRESA_IDIOMA || 'es',
      tz: p.EMPRESA_TZ || i.timezone || 'UTC',
    },
    dataRoot: p.DATA_ROOT || '',
    packs: i.packs.filter((x) => x.tier !== 'core').map((x) => ({ id: x.id, on: x.tier === 'negocio' })),
    mcps: i.mcps.map((m) => ({ id: m.id, on: m.tier === 'core' || (m.recommended && !m.installed), creds: {}, label: '', login: true })),
    extras: { media: true, docker: false, panel: !i.panelInstalled, shortcuts: true },
  }
}

// --- Marco: barra lateral de pasos, como la navegación del panel ------------------------

function Shell({ info, current, onJump, children }: { info: Info; current: StepId | null; onJump?: (s: StepId) => void; children: React.ReactNode }) {
  const idx = current ? STEPS.findIndex((s) => s.id === current) : STEPS.length
  return (
    <div className="min-h-screen flex">
      <aside className="w-60 shrink-0 border-r border-border bg-panel flex flex-col">
        <div className="px-5 py-5 border-b border-border flex items-center gap-3">
          <img src="/favicon.svg" alt="" className="w-8 h-8" />
          <div>
            <div className="text-[13px] uppercase tracking-wider text-muted">Ideas Box</div>
            <div className="text-white font-medium">Instalación</div>
          </div>
        </div>
        <nav className="flex-1 px-2 py-3 space-y-0.5">
          {STEPS.map((s, i) => {
            const done = i < idx
            const active = s.id === current
            return (
              <button
                key={s.id}
                type="button"
                onClick={() => onJump?.(s.id)}
                disabled={!done || !onJump}
                className={`w-full text-left px-3 py-2 text-sm flex items-center gap-2 border-l-2 transition-colors ${
                  active
                    ? 'bg-accent/10 text-accent border-accent'
                    : done
                      ? 'text-white border-transparent hover:bg-panel-raised'
                      : 'text-muted border-transparent'
                }`}
              >
                <span className={`w-5 text-[11px] ${done ? 'text-emerald-400' : ''}`}>{done ? '✓' : i + 1}</span>
                {s.label}
              </button>
            )
          })}
          <div
            className={`px-3 py-2 text-sm flex items-center gap-2 border-l-2 ${
              current === null ? 'bg-accent/10 text-accent border-accent' : 'text-muted border-transparent'
            }`}
          >
            <span className="w-5 text-[11px]">{STEPS.length + 1}</span>Instalando
          </div>
        </nav>
        <div className="px-5 py-4 border-t border-border text-[11px] text-muted leading-relaxed">
          {info.osPretty}
          {info.version && <> · v{info.version}</>}
          <br />
          Todo queda en tu equipo: nada de lo que escribas acá sale de él.
        </div>
      </aside>
      <main className="flex-1 p-8 max-w-4xl">{children}</main>
    </div>
  )
}

function Centered({ children }: { children: React.ReactNode }) {
  return <div className="min-h-screen flex items-center justify-center p-8"><div className="max-w-lg flex items-center">{children}</div></div>
}

function Nav({ onBack, onNext, nextLabel = 'Siguiente', nextDisabled = false, hint }: { onBack?: () => void; onNext: () => void; nextLabel?: string; nextDisabled?: boolean; hint?: string }) {
  return (
    <div className="mt-8 pt-5 border-t border-border flex items-center gap-3">
      {onBack && <Button variant="ghost" onClick={onBack}>Atrás</Button>}
      <div className="flex-1 text-[12px] text-muted text-right">{hint}</div>
      <Button onClick={onNext} disabled={nextDisabled}>{nextLabel}</Button>
    </div>
  )
}

type StepProps = { a: Answers; setA: (f: (a: Answers) => Answers) => void; onBack: () => void; onNext: () => void }

// --- 1 · Bienvenida ------------------------------------------------------------------------

function Bienvenida({ info, onResume, onNext }: { info: Info; onResume: () => void; onNext: () => void }) {
  return (
    <>
      <SectionHeader
        title="Bienvenido a Ideas Box"
        subtitle="En unos minutos tu equipo queda listo para operar tu empresa con agentes de IA: cada área con su agente, memoria compartida y conexión con tus herramientas."
      />
      {info.resume.length > 0 && (
        <Panel className="p-5 mb-6 border-accent/40">
          <div className="text-sm text-white font-medium">Tu instalación anterior quedó a mitad</div>
          <p className="text-[13px] text-muted mt-1">
            Ya estaba completo: {info.resume.map((r) => r.label.toLowerCase()).join(', ')}. Podés seguir desde ahí con las
            respuestas que ya diste.
          </p>
          <div className="mt-4 flex gap-2">
            <Button onClick={onResume}>Retomar la instalación</Button>
            <Button variant="ghost" onClick={onNext}>Empezar de nuevo</Button>
          </div>
        </Panel>
      )}
      <div className="grid grid-cols-2 gap-3">
        {[
          ['Te vamos a preguntar', 'El nombre y el rubro de tu empresa, dónde guardar la información y qué herramientas querés conectar.'],
          ['Tené a mano', 'Las claves de las herramientas que vayas a conectar. Ninguna es obligatoria: se pueden sumar después.'],
          ['Mientras se instala', 'Vas a ver el avance acá. Si hace falta la contraseña de tu equipo, la pide una ventana del sistema.'],
          ['Tarda', 'Entre 10 y 25 minutos, según tu conexión y cuántos conectores elijas.'],
        ].map(([t, d]) => (
          <Panel key={t} className="p-4">
            <div className="text-[13px] text-white font-medium">{t}</div>
            <div className="text-[13px] text-muted mt-1 leading-relaxed">{d}</div>
          </Panel>
        ))}
      </div>
      {info.dryRun && <div className="mt-4"><Callout tone="warn">Modo de prueba: se muestra qué haría el instalador, sin modificar nada.</Callout></div>}
      <Nav onNext={onNext} nextLabel={info.resume.length ? 'Empezar de nuevo' : 'Empezar'} hint={`Detectado: ${OS_LABEL[info.os]}`} />
    </>
  )
}

// --- 2 · Empresa ---------------------------------------------------------------------------

function Empresa({ a, setA, onBack, onNext }: StepProps) {
  const e = a.empresa
  const [slugTouched, setSlugTouched] = useState(Boolean(e.slug))
  const [advanced, setAdvanced] = useState(false)
  const set = (k: keyof Answers['empresa'], v: string) =>
    setA((x) => {
      const emp = { ...x.empresa, [k]: v }
      if (k === 'nombre' && !slugTouched) emp.slug = slugify(v)
      return { ...x, empresa: emp }
    })
  const ok = e.nombre.trim().length > 0 && slugify(e.slug || e.nombre).length > 0
  return (
    <>
      <SectionHeader title="Tu empresa" subtitle="Con esto se personalizan los agentes, la documentación y la memoria. Queda solo en tu equipo." />
      <div className="space-y-4 max-w-xl">
        <TextField label="Nombre de la empresa" value={e.nombre} onChange={(v) => set('nombre', v)} required autoFocus placeholder="Ej: Ferretería Ñandú" />
        <TextField
          label="¿A qué se dedica?"
          value={e.rubro}
          onChange={(v) => set('rubro', v)}
          placeholder="Ej: panadería con venta online y reparto propio"
          hint="Una línea. Cuanto más concreta, mejor entienden el contexto los agentes."
        />
        <div className="grid grid-cols-2 gap-4">
          <TextField label="Sitio web (opcional)" value={e.sitio} onChange={(v) => set('sitio', v)} placeholder="tuempresa.com" />
          <TextField label="Quién lo va a usar (opcional)" value={e.responsable} onChange={(v) => set('responsable', v)} placeholder="Tu nombre" />
        </div>
        <button type="button" onClick={() => setAdvanced(!advanced)} className="text-[13px] text-muted hover:text-white">
          {advanced ? '▾' : '▸'} Opciones avanzadas
        </button>
        {advanced && (
          <div className="grid grid-cols-[1fr_1fr_1.4fr] gap-4">
            <TextField
              label="Identificador"
              value={e.slug}
              mono
              onChange={(v) => {
                setSlugTouched(true)
                set('slug', v)
              }}
              hint="Para carpetas y conectores"
            />
            <SelectField label="Idioma de los agentes" value={e.idioma} onChange={(v) => set('idioma', v)} options={[{ value: 'es', label: 'Español' }, { value: 'en', label: 'English' }]} />
            <TextField label="Zona horaria" value={e.tz} onChange={(v) => set('tz', v)} mono />
          </div>
        )}
      </div>
      <Nav onBack={onBack} onNext={() => { setA((x) => ({ ...x, empresa: { ...x.empresa, slug: slugify(x.empresa.slug || x.empresa.nombre) } })); onNext() }} nextDisabled={!ok} hint={ok ? '' : 'Falta el nombre de la empresa'} />
    </>
  )
}

// --- 3 · Dónde guardar ---------------------------------------------------------------------

function Datos({ a, setA, onBack, onNext }: StepProps) {
  const [opts, setOpts] = useState<DataRoot[] | null>(null)
  const [custom, setCustom] = useState(false)
  const [customPath, setCustomPath] = useState('')
  useEffect(() => {
    api.dataroots(a.empresa.slug).then((r) => {
      setOpts(r.options)
      const known = r.options.some((o) => o.path === a.dataRoot)
      if (a.dataRoot && !known) {
        setCustom(true)
        setCustomPath(a.dataRoot)
      } else if (!a.dataRoot) {
        const rec = r.options.find((o) => o.recommended) || r.options[0]
        if (rec) setA((x) => ({ ...x, dataRoot: rec.path }))
      }
    }).catch(() => setOpts([]))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const chosen = custom ? customPath.trim() : a.dataRoot
  const valid = chosen.startsWith('/')
  return (
    <>
      <SectionHeader
        title="¿Dónde guardamos la información?"
        subtitle="Es la carpeta de tu empresa: ahí viven la memoria de los agentes, clientes, proyectos y todo lo que generen. Conviene un lugar que respaldes y que no se sincronice solo con la nube."
      />
      {!opts ? (
        <div className="text-sm text-muted flex items-center gap-2"><Spinner /> Revisando tu equipo…</div>
      ) : (
        <div className="space-y-2">
          {opts.map((o) => (
            <ChoiceCard
              key={o.path}
              radio
              checked={!custom && a.dataRoot === o.path}
              onChange={() => { setCustom(false); setA((x) => ({ ...x, dataRoot: o.path })) }}
              title={<span className="font-mono text-[13px]">{o.path}</span>}
              badges={<>{o.recommended && <Badge tone="accent">recomendado</Badge>}{o.exists && <Badge tone="ok">ya existe</Badge>}</>}
            >
              <div className="text-[12px] text-muted">{o.label} · {o.free} libres</div>
            </ChoiceCard>
          ))}
          <ChoiceCard radio checked={custom} onChange={() => setCustom(true)} title="Otra carpeta (la escribo yo)">
            {custom && (
              <div className="mt-1 max-w-xl">
                <TextField label="Ruta completa" value={customPath} onChange={setCustomPath} mono placeholder="/ruta/a/la/carpeta" hint="Empieza con /. Si no existe, se crea." />
              </div>
            )}
          </ChoiceCard>
        </div>
      )}
      <Nav
        onBack={onBack}
        onNext={() => { setA((x) => ({ ...x, dataRoot: chosen })); onNext() }}
        nextDisabled={!valid}
        hint={valid ? '' : 'Elegí una carpeta (ruta completa, empieza con /)'}
      />
    </>
  )
}

// --- 4 · Habilidades -----------------------------------------------------------------------

function Habilidades({ info, a, setA, onBack, onNext }: StepProps & { info: Info }) {
  const on = (id: string) => a.packs.find((p) => p.id === id)?.on ?? false
  const toggle = (id: string, v: boolean) => setA((x) => ({ ...x, packs: x.packs.map((p) => (p.id === id ? { ...p, on: v } : p)) }))
  const groups: [string, string, string][] = [
    ['core', 'Siempre incluidas', 'Base de todos los agentes.'],
    ['negocio', 'Recomendadas', 'Marketing, criterio de diseño y más: suman mucho y pesan poco.'],
    ['opcional', 'Opcionales', 'Colecciones grandes; se pueden sumar después desde el menú.'],
  ]
  return (
    <>
      <SectionHeader title="Habilidades" subtitle="Paquetes de conocimiento que usan tus agentes (procedimientos, criterios, recetas). Se descargan de sus autores originales." />
      <div className="space-y-6">
        {groups.map(([tier, title, desc]) => {
          const items = info.packs.filter((p) => p.tier === tier)
          if (!items.length) return null
          return (
            <section key={tier}>
              <div className="text-[13px] text-white font-medium">{title}</div>
              <div className="text-[12px] text-muted mb-2">{desc}</div>
              <div className="space-y-2">
                {items.map((p) => (
                  <ChoiceCard key={p.id} checked={tier === 'core' || on(p.id)} disabled={tier === 'core'} onChange={(v) => toggle(p.id, v)} title={p.id} badges={<Badge>{p.domain}</Badge>}>
                    <div className="text-[12px] text-muted">{p.desc}</div>
                  </ChoiceCard>
                ))}
              </div>
            </section>
          )
        })}
      </div>
      <Nav onBack={onBack} onNext={onNext} />
    </>
  )
}

// --- 5 · Conectores ------------------------------------------------------------------------

function Conectores({ info, a, setA, onBack, onNext }: StepProps & { info: Info }) {
  const byId = useMemo(() => Object.fromEntries(info.mcps.map((m) => [m.id, m])), [info])
  const ans = (id: string) => a.mcps.find((m) => m.id === id)
  const patch = (id: string, p: Partial<McpAnswer>) => setA((x) => ({ ...x, mcps: x.mcps.map((m) => (m.id === id ? { ...m, ...p } : m)) }))
  const suggested = new Set(info.mcps.map((m) => m.suggest).filter(Boolean))
  const recommended = info.mcps.filter((m) => m.recommended)
  const negocio = info.mcps.filter((m) => m.tier === 'negocio' && !m.recommended)
  const core = info.mcps.filter((m) => m.tier === 'core')
  const opcional = info.mcps.filter((m) => m.tier === 'opcional' && !suggested.has(m.id))

  const card = (m: Mcp) => {
    const x = ans(m.id)
    if (!x) return null
    const sub = m.suggest ? byId[m.suggest] : null
    const subAns = sub ? ans(sub.id) : null
    return (
      <ChoiceCard
        key={m.id}
        checked={m.installed || x.on}
        disabled={m.installed}
        onChange={(v) => patch(m.id, { on: v })}
        title={m.title}
        badges={<>{m.installed && <Badge tone="ok">ya instalado</Badge>}{m.recommended && !m.installed && <Badge tone="accent">recomendado</Badge>}</>}
      >
        <div className="text-[12px] text-muted">{m.desc}</div>
        {x.on && !m.installed && (
          <div className="mt-3 space-y-3 max-w-xl">
            {m.multi && (
              <TextField
                label={m.instancePrompt || 'Etiqueta de esta cuenta'}
                value={x.label}
                onChange={(v) => patch(m.id, { label: v })}
                placeholder={a.empresa.slug}
                hint="Sirve para distinguirla si después sumás otra. Más cuentas: desde el menú, «Conectar una herramienta»."
              />
            )}
            {m.fields.map((f) => (
              <TextField
                key={f.key}
                label={f.prompt}
                value={x.creds[f.key] || ''}
                secret={f.secret}
                mono={f.secret}
                onChange={(v) => patch(m.id, { creds: { ...x.creds, [f.key]: v } })}
                hint={f.secret ? 'Se guarda solo en tu equipo, con acceso restringido. Si la dejás vacía, la cargás después.' : undefined}
              />
            ))}
            {m.login && (
              <label className="flex items-center gap-2 text-[13px] text-white">
                <input type="checkbox" checked={x.login} onChange={(e) => patch(m.id, { login: e.target.checked })} className="accent-[var(--color-accent)]" />
                Conectar mi cuenta durante la instalación (se abre el navegador)
              </label>
            )}
            {sub && subAns && !sub.installed && (
              <label className="flex items-start gap-2 text-[13px] text-white">
                <input type="checkbox" className="mt-0.5 accent-[var(--color-accent)]" checked={subAns.on} onChange={(e) => patch(sub.id, { on: e.target.checked })} />
                <span>
                  Sumar también {sub.title.split(' — ')[0]}
                  <span className="block text-[12px] text-muted">{sub.desc}</span>
                </span>
              </label>
            )}
            {m.notes && <div className="text-[12px] text-muted">{m.notes}</div>}
          </div>
        )}
      </ChoiceCard>
    )
  }

  return (
    <>
      <SectionHeader
        title="Conectores"
        subtitle="Le dan a tus agentes acceso a tus herramientas. Elegí solo las que uses: el resto se suma después desde el menú de Ideas Box."
      />
      <section>
        <div className="text-[13px] text-white font-medium">Siempre incluidos</div>
        <div className="text-[12px] text-muted mb-2">La base de todos los agentes.</div>
        <div className="space-y-2">
          {core.map((m) => {
            const x = ans(m.id)
            return (
              <ChoiceCard key={m.id} checked disabled={false} onChange={() => {}} title={m.title} badges={m.installed ? <Badge tone="ok">ya instalado</Badge> : undefined}>
                <div className="text-[12px] text-muted">{m.desc}</div>
                {x && !m.installed && m.fields.length > 0 && (
                  <div className="mt-3 space-y-3 max-w-xl">
                    {m.fields.map((f) => (
                      <TextField
                        key={f.key}
                        label={`${f.prompt} — opcional`}
                        value={x.creds[f.key] || ''}
                        secret={f.secret}
                        mono={f.secret}
                        onChange={(v) => patch(m.id, { creds: { ...x.creds, [f.key]: v } })}
                        hint="Sin ella, el conector se instala igual y la cargás después desde el menú."
                      />
                    ))}
                  </div>
                )}
              </ChoiceCard>
            )
          })}
        </div>
      </section>
      <section className="mt-6">
        <div className="text-[13px] text-white font-medium">Recomendados para crear contenido con IA</div>
        <div className="text-[12px] text-muted mb-2">Voz, imagen y video. Son servicios pagos por uso: los agentes estiman el gasto y piden permiso antes de generar.</div>
        <div className="space-y-2">{recommended.map(card)}</div>
      </section>
      <section className="mt-6">
        <div className="text-[13px] text-white font-medium">Herramientas de tu negocio</div>
        <div className="text-[12px] text-muted mb-2">Atención, servidores, redes sociales y video.</div>
        <div className="space-y-2">{negocio.map(card)}</div>
      </section>
      {opcional.length > 0 && (
        <p className="mt-6 text-[12px] text-muted">
          Disponibles después, desde el menú: {opcional.map((m) => m.title.split(' — ')[0]).join(', ')}.
        </p>
      )}
      <Nav onBack={onBack} onNext={onNext} />
    </>
  )
}

// --- 6 · Extras ----------------------------------------------------------------------------

function Extras({ info, a, setA, onBack, onNext }: StepProps & { info: Info }) {
  const set = (k: keyof Answers['extras'], v: boolean) => setA((x) => ({ ...x, extras: { ...x.extras, [k]: v } }))
  return (
    <>
      <SectionHeader title="Extras" subtitle="Todo esto se puede cambiar después." />
      <div className="space-y-2">
        <ChoiceCard checked={a.extras.panel || info.panelInstalled} disabled={info.panelInstalled} onChange={(v) => set('panel', v)} title="Panel de tareas y programación" badges={info.panelInstalled ? <Badge tone="ok">ya instalado</Badge> : <Badge tone="accent">recomendado</Badge>}>
          <div className="text-[12px] text-muted">Un tablero en tu navegador para programar tareas a los agentes. Suma unos minutos a la instalación.</div>
        </ChoiceCard>
        <ChoiceCard checked={a.extras.shortcuts} onChange={(v) => set('shortcuts', v)} title="Accesos en el Escritorio">
          <div className="text-[12px] text-muted">«Ideas Box» (el menú), «Archivos Ideas Box» (lo que generan tus agentes) y, si lo instalás, «Panel Ideas Box».</div>
        </ChoiceCard>
        <ChoiceCard checked={a.extras.media} onChange={(v) => set('media', v)} title="Herramientas de video e imagen">
          <div className="text-[12px] text-muted">ffmpeg e ImageMagick, que usan los agentes de contenido para editar.</div>
        </ChoiceCard>
        {info.os !== 'mac' && (
          <ChoiceCard checked={a.extras.docker} onChange={(v) => set('docker', v)} title="Docker">
            <div className="text-[12px] text-muted">Solo si vas a levantar servicios propios en este equipo.</div>
          </ChoiceCard>
        )}
      </div>
      <Nav onBack={onBack} onNext={onNext} />
    </>
  )
}

// --- 7 · Revisar -----------------------------------------------------------------------------

function Revisar({ info, a, onBack, onInstall }: { info: Info; a: Answers; onBack: () => void; onInstall: () => void }) {
  const [busy, setBusy] = useState(false)
  const packs = a.packs.filter((p) => p.on).map((p) => p.id)
  const mcps = a.mcps.filter((m) => m.on && info.mcps.find((x) => x.id === m.id)?.tier !== 'core').map((m) => info.mcps.find((x) => x.id === m.id)?.title.split(' — ')[0] || m.id)
  const rows: [string, string][] = [
    ['Empresa', `${a.empresa.nombre}${a.empresa.rubro ? ' · ' + a.empresa.rubro : ''}`],
    ['Carpeta de datos', a.dataRoot],
    ['Habilidades', ['las básicas', ...packs].join(', ')],
    ['Conectores', mcps.length ? mcps.join(', ') : 'solo los básicos'],
    ['Extras', [a.extras.panel && 'panel de tareas', a.extras.shortcuts && 'accesos en el Escritorio', a.extras.media && 'video e imagen', a.extras.docker && 'Docker'].filter(Boolean).join(', ') || 'ninguno'],
  ]
  return (
    <>
      <SectionHeader title="Revisá y arrancamos" subtitle="Si algo no te convence, volvé al paso con el menú de la izquierda." />
      <Panel>
        {rows.map(([k, v]) => (
          <div key={k} className="flex gap-4 px-5 py-3 border-b border-border last:border-b-0">
            <div className="w-40 shrink-0 text-[13px] text-muted">{k}</div>
            <div className={`text-[13px] text-white ${k === 'Carpeta de datos' ? 'font-mono' : ''}`}>{v}</div>
          </div>
        ))}
      </Panel>
      {!info.skipDeps && (
        <div className="mt-4">
          <Callout>
            Primero se instalan los programas que Ideas Box necesita (Node, Claude Code y otros).{' '}
            {info.os === 'wsl' ? 'La contraseña de tu usuario ya la pediste en la terminal.' : 'Si hace falta tu contraseña de administrador, la pide una ventana del sistema: no pasa por esta página.'}
          </Callout>
        </div>
      )}
      <Nav onBack={onBack} onNext={() => { setBusy(true); onInstall() }} nextLabel={busy ? 'Arrancando…' : 'Instalar Ideas Box'} nextDisabled={busy} />
    </>
  )
}
