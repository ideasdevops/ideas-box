import { useEffect, useRef, type ReactNode } from 'react'

export function Panel({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`bg-panel border border-border ${className}`}>{children}</div>
}

export function SectionHeader({ title, subtitle, action }: { title: string; subtitle?: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex items-end justify-between gap-4 mb-6">
      <div className="min-w-0">
        <h1 className="text-xl font-medium tracking-tight text-white">{title}</h1>
        {subtitle && <p className="text-sm text-muted mt-1 max-w-3xl">{subtitle}</p>}
      </div>
      {action && <div className="shrink-0 flex gap-2">{action}</div>}
    </div>
  )
}

export function Badge({ children, tone = 'default' }: { children: ReactNode; tone?: 'default' | 'accent' | 'ok' | 'warn' | 'danger' | 'info' }) {
  const tones: Record<string, string> = {
    default: 'bg-panel-raised text-muted border-border',
    accent: 'bg-accent/10 text-accent border-accent/30',
    ok: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30',
    warn: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
    danger: 'bg-rose-500/10 text-rose-400 border-rose-500/30',
    info: 'bg-sky-500/10 text-sky-300 border-sky-500/30',
  }
  return <span className={`inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 border whitespace-nowrap ${tones[tone]}`}>{children}</span>
}

export function EmptyState({ label, children }: { label: string; children?: ReactNode }) {
  return (
    <div className="text-sm text-muted py-8 px-4 text-center border border-dashed border-border">
      {label}
      {children && <div className="mt-3">{children}</div>}
    </div>
  )
}

export function Modal({ title, onClose, children, wide = false }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-6" onClick={onClose}>
      <div className={`bg-panel border border-border w-full max-h-[85vh] flex flex-col ${wide ? 'max-w-4xl' : 'max-w-2xl'}`} onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between px-5 py-3 border-b border-border shrink-0">
          <span className="text-sm font-medium text-white truncate pr-4">{title}</span>
          <button onClick={onClose} className="text-muted hover:text-white text-sm">Cerrar</button>
        </div>
        <div className="p-5 overflow-y-auto">{children}</div>
      </div>
    </div>
  )
}

export function Button({
  children, onClick, variant = 'primary', type = 'button', disabled = false, small = false, title,
}: {
  children: ReactNode
  onClick?: () => void
  variant?: 'primary' | 'ghost' | 'danger' | 'quiet'
  type?: 'button' | 'submit'
  disabled?: boolean
  small?: boolean
  title?: string
}) {
  const variants: Record<string, string> = {
    primary: 'bg-accent text-black hover:bg-accent-dim hover:text-white',
    ghost: 'bg-transparent border border-border text-white hover:bg-panel-raised',
    danger: 'bg-transparent border border-rose-500/40 text-rose-400 hover:bg-rose-500/10',
    quiet: 'bg-transparent text-muted hover:text-white',
  }
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      title={title}
      className={`${small ? 'text-xs px-2 py-1' : 'text-sm px-3 py-1.5'} font-medium transition-colors whitespace-nowrap disabled:opacity-40 disabled:cursor-not-allowed ${variants[variant]}`}
    >
      {children}
    </button>
  )
}

export function Tabs<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { value: T; label: ReactNode }[] }) {
  return (
    <div className="flex border-b border-border mb-5">
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className={`px-4 py-2 text-sm -mb-px border-b-2 transition-colors ${value === o.value ? 'border-accent text-accent' : 'border-transparent text-muted hover:text-white'}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

export function Chips<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { value: T; label: ReactNode }[] }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className={`text-xs px-2.5 py-1 border transition-colors ${value === o.value ? 'border-accent text-accent bg-accent/10' : 'border-border text-muted hover:text-white'}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

const inputCls = 'w-full bg-panel-raised border border-border px-3 py-2 text-sm text-white placeholder:text-muted focus:outline-none focus:border-accent'

export function Field({ label, hint, children }: { label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <label className="block">
      <span className="text-xs text-muted">{label}</span>
      <div className="mt-1">{children}</div>
      {hint && <span className="block text-[11px] text-muted mt-1">{hint}</span>}
    </label>
  )
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={`${inputCls} ${props.className ?? ''}`} />
}

export function TextArea(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={`${inputCls} ${props.className ?? ''}`} />
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return <select {...props} className={`${inputCls} ${props.className ?? ''}`} />
}

export function Spinner() {
  return <span className="inline-block w-3 h-3 border-2 border-accent border-t-transparent rounded-full animate-spin align-middle" />
}

export function Pulse({ tone = 'accent' }: { tone?: 'accent' | 'ok' }) {
  return (
    <span className="relative inline-flex w-2 h-2">
      <span className={`absolute inline-flex h-full w-full rounded-full opacity-60 animate-ping ${tone === 'ok' ? 'bg-emerald-400' : 'bg-accent'}`} />
      <span className={`relative inline-flex rounded-full w-2 h-2 ${tone === 'ok' ? 'bg-emerald-400' : 'bg-accent'}`} />
    </span>
  )
}

// Contenedor que baja solo al final cuando llega contenido nuevo (salvo que la persona haya subido)
export function AutoScroll({ children, className = '', deps }: { children: ReactNode; className?: string; deps: unknown }) {
  const ref = useRef<HTMLDivElement>(null)
  const pegado = useRef(true)
  useEffect(() => {
    if (ref.current && pegado.current) ref.current.scrollTop = ref.current.scrollHeight
  }, [deps])
  return (
    <div
      ref={ref}
      onScroll={(e) => {
        const el = e.currentTarget
        pegado.current = el.scrollHeight - el.scrollTop - el.clientHeight < 40
      }}
      className={`overflow-y-auto ${className}`}
    >
      {children}
    </div>
  )
}
