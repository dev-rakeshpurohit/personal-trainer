import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'success';
const variants: Record<Variant, string> = {
  primary: 'bg-primary text-on-primary shadow-[0_8px_24px_-8px_rgb(var(--primary)/0.6)] active:brightness-95',
  secondary: 'bg-surface2 text-text active:bg-line',
  ghost: 'bg-transparent text-text active:bg-surface2',
  danger: 'bg-danger/15 text-danger active:bg-danger/25',
  success: 'bg-success text-on-primary active:brightness-95',
};

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: 'md' | 'lg' | 'xl';
  block?: boolean;
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'primary', size = 'md', block, className = '', type = 'button', ...rest },
  ref,
) {
  const sizes = { md: 'min-h-[48px] px-4 text-body', lg: 'min-h-[56px] px-5 text-[17px]', xl: 'min-h-[64px] px-6 text-[19px]' };
  return (
    <button
      ref={ref}
      type={type}
      className={`inline-flex items-center justify-center gap-2 rounded-btn font-semibold transition-[transform,filter,background-color] duration-150 ease-out active:scale-[0.98] disabled:opacity-40 ${variants[variant]} ${sizes[size]} ${block ? 'w-full' : ''} ${className}`}
      {...rest}
    />
  );
});

export function Card({ children, className = '', glow }: { children: ReactNode; className?: string; glow?: boolean }) {
  return (
    <section className={`rounded-card border border-line/50 ${glow ? 'card-glow' : 'bg-surface'} p-4 ${className}`}>
      {children}
    </section>
  );
}

export function Chip({
  children,
  active,
  onClick,
  className = '',
  ...rest
}: { children: ReactNode; active?: boolean; onClick?: () => void; className?: string } & Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  'onClick'
>) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={`inline-flex min-h-[40px] shrink-0 items-center gap-1.5 rounded-full border px-3.5 text-[15px] font-medium transition-colors ${
        active ? 'border-primary bg-primary/15 text-primary-ink' : 'border-line bg-surface2/60 text-text'
      } ${className}`}
      {...rest}
    >
      {children}
    </button>
  );
}

export function PageHeader({ title, right, sub }: { title: string; right?: ReactNode; sub?: ReactNode }) {
  return (
    <header className="pt-safe">
      <div className="flex items-end justify-between gap-3 px-4 pb-3 pt-4">
        <div className="min-w-0">
          {sub && <p className="text-caption font-medium text-muted">{sub}</p>}
          <h1 className="truncate text-[28px] font-bold leading-tight tracking-tight">{title}</h1>
        </div>
        {right}
      </div>
    </header>
  );
}

export function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-2 mt-6 flex items-center justify-between px-1">
      <h2 className="text-[13px] font-semibold uppercase tracking-wider text-muted">{children}</h2>
      {action}
    </div>
  );
}

export function Empty({ title, body, action }: { title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-card border border-dashed border-line px-6 py-10 text-center">
      <p className="text-body font-semibold">{title}</p>
      {body && <p className="text-caption text-muted">{body}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}
