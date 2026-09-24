import type { ReactNode } from 'react'

export function Panel({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div className={`bg-panel border border-border ${className}`}>{children}</div>
  )
}

export function SectionHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <div className="flex items-end justify-between mb-6">
      <div>
        <h1 className="text-xl font-medium tracking-tight text-white">{title}</h1>
        {subtitle && <p className="text-sm text-muted mt-1">{subtitle}</p>}
      </div>
      {action}
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
  return (
    <span className={`inline-flex items-center text-[11px] font-medium px-2 py-0.5 border ${tones[tone]}`}>
      {children}
    </span>
  )
}

export function EmptyState({ label }: { label: string }) {
  return <div className="text-sm text-muted py-8 text-center border border-dashed border-border">{label}</div>
}

export function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-6" onClick={onClose}>
      <div
        className="bg-panel border border-border max-w-2xl w-full max-h-[80vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-5 py-3 border-b border-border">
          <span className="text-sm font-medium text-white">{title}</span>
          <button onClick={onClose} className="text-muted hover:text-white text-sm">
            Cerrar
          </button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  )
}

export function Button({
  children,
  onClick,
  variant = 'primary',
  type = 'button',
}: {
  children: ReactNode
  onClick?: () => void
  variant?: 'primary' | 'ghost' | 'danger'
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
      className={`text-sm font-medium px-3 py-1.5 transition-colors ${variants[variant]}`}
    >
      {children}
    </button>
  )
}
