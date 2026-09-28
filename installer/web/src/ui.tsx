// Mismo sistema visual que el panel de tareas (vendor/panel/frontend/src/components/ui.tsx),
// más los controles de formulario que el asistente necesita.
import type { ReactNode } from 'react'

export function Panel({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`bg-panel border border-border ${className}`}>{children}</div>
}

export function SectionHeader({ title, subtitle }: { title: string; subtitle?: ReactNode }) {
  return (
    <div className="mb-6">
      <h1 className="text-xl font-medium tracking-tight text-white">{title}</h1>
      {subtitle && <p className="text-sm text-muted mt-1 max-w-2xl">{subtitle}</p>}
    </div>
  )
}

export function Badge({ children, tone = 'default' }: { children: ReactNode; tone?: 'default' | 'accent' | 'ok' | 'warn' | 'danger' }) {
  const tones: Record<string, string> = {
    default: 'bg-panel-raised text-muted border-border',
    accent: 'bg-accent/10 text-accent border-accent/30',
    ok: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30',
    warn: 'bg-amber-500/10 text-amber-400 border-amber-500/30',
    danger: 'bg-rose-500/10 text-rose-400 border-rose-500/30',
  }
  return <span className={`inline-flex items-center text-[11px] font-medium px-2 py-0.5 border whitespace-nowrap ${tones[tone]}`}>{children}</span>
}

export function Button({
  children,
  onClick,
  variant = 'primary',
  disabled = false,
  type = 'button',
}: {
  children: ReactNode
  onClick?: () => void
  variant?: 'primary' | 'ghost' | 'danger'
  disabled?: boolean
  type?: 'button' | 'submit'
}) {
  const variants: Record<string, string> = {
    primary: 'bg-accent text-black hover:bg-accent-dim hover:text-white',
    ghost: 'bg-transparent border border-border text-white hover:bg-panel-raised',
    danger: 'bg-transparent border border-rose-500/40 text-rose-400 hover:bg-rose-500/10',
  }
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`text-sm font-medium px-4 py-2 transition-colors disabled:opacity-40 disabled:cursor-not-allowed ${variants[variant]}`}
    >
      {children}
    </button>
  )
}

export function Modal({ title, children, footer }: { title: string; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-6">
      <div className="bg-panel border border-border max-w-lg w-full shadow-2xl">
        <div className="px-5 py-3 border-b border-border text-sm font-medium text-white">{title}</div>
        <div className="p-5">{children}</div>
        {footer && <div className="px-5 py-3 border-t border-border flex justify-end gap-2">{footer}</div>}
      </div>
    </div>
  )
}

export function TextField({
  label,
  value,
  onChange,
  placeholder,
  hint,
  secret = false,
  required = false,
  autoFocus = false,
  mono = false,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
  hint?: ReactNode
  secret?: boolean
  required?: boolean
  autoFocus?: boolean
  mono?: boolean
}) {
  return (
    <label className="block">
      <span className="text-[13px] text-white">
        {label}
        {required && <span className="text-accent"> *</span>}
      </span>
      <input
        type={secret ? 'password' : 'text'}
        value={value}
        autoFocus={autoFocus}
        autoComplete="off"
        spellCheck={false}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className={`mt-1 w-full bg-ink border border-border px-3 py-2 text-sm text-white placeholder:text-muted/60 focus:outline-none focus:border-accent ${mono ? 'font-mono' : ''}`}
      />
      {hint && <span className="block text-[12px] text-muted mt-1">{hint}</span>}
    </label>
  )
}

export function SelectField({
  label,
  value,
  onChange,
  options,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  options: { value: string; label: string }[]
}) {
  return (
    <label className="block">
      <span className="text-[13px] text-white">{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full bg-ink border border-border px-3 py-2 text-sm text-white focus:outline-none focus:border-accent"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  )
}

// Tarjeta seleccionable (casilla o radio): todo el bloque es clickeable
export function ChoiceCard({
  checked,
  onChange,
  title,
  children,
  badges,
  disabled = false,
  radio = false,
}: {
  checked: boolean
  onChange: (v: boolean) => void
  title: ReactNode
  children?: ReactNode
  badges?: ReactNode
  disabled?: boolean
  radio?: boolean
}) {
  return (
    <div
      className={`border transition-colors ${checked ? 'border-accent/60 bg-accent/5' : 'border-border bg-panel'} ${
        disabled ? 'opacity-60' : 'hover:border-accent/40'
      }`}
    >
      <button
        type="button"
        disabled={disabled}
        onClick={() => onChange(radio ? true : !checked)}
        className="w-full text-left px-4 py-3 flex items-start gap-3 disabled:cursor-not-allowed"
      >
        <span
          className={`mt-0.5 shrink-0 w-4 h-4 border flex items-center justify-center ${radio ? 'rounded-full' : ''} ${
            checked ? 'border-accent bg-accent' : 'border-muted/60'
          }`}
        >
          {checked && (radio ? <span className="w-1.5 h-1.5 rounded-full bg-ink" /> : <span className="text-ink text-[11px] font-bold leading-none">✓</span>)}
        </span>
        <span className="flex-1 min-w-0">
          <span className="flex items-center gap-2 flex-wrap">
            <span className="text-sm text-white">{title}</span>
            {badges}
          </span>
        </span>
      </button>
      {children && <div className="px-4 pb-3 pl-11 -mt-1">{children}</div>}
    </div>
  )
}

export function Spinner() {
  return <span className="inline-block w-3 h-3 border-2 border-accent border-t-transparent rounded-full animate-spin" />
}

export function Callout({ children, tone = 'default' }: { children: ReactNode; tone?: 'default' | 'warn' | 'danger' | 'ok' }) {
  const tones: Record<string, string> = {
    default: 'border-border bg-panel-raised text-muted',
    warn: 'border-amber-500/30 bg-amber-500/5 text-amber-200',
    danger: 'border-rose-500/30 bg-rose-500/5 text-rose-200',
    ok: 'border-emerald-500/30 bg-emerald-500/5 text-emerald-200',
  }
  return <div className={`border px-4 py-3 text-[13px] leading-relaxed ${tones[tone]}`}>{children}</div>
}
