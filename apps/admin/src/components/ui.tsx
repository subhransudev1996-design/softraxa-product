"use client";

import { ReactNode } from "react";

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={`rounded-2xl border border-zinc-200/70 bg-white shadow-[0_1px_2px_rgba(23,34,59,0.04),0_8px_24px_-12px_rgba(23,34,59,0.12)] transition-shadow duration-200 hover:shadow-[0_1px_2px_rgba(23,34,59,0.04),0_12px_32px_-12px_rgba(23,34,59,0.18)] ${className}`}
    >
      {children}
    </div>
  );
}

export function CardBody({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`p-5 ${className}`}>{children}</div>;
}

export function StatCard({
  label,
  value,
  hint,
  icon,
}: {
  label: string;
  value: string | number;
  hint?: string;
  icon?: ReactNode;
}) {
  return (
    <Card>
      <CardBody className="relative overflow-hidden">
        <span className="absolute inset-x-0 top-0 h-0.5 bg-gradient-to-r from-brand via-[#a78bfa] to-transparent opacity-70" />
        <div className="flex items-start justify-between gap-2">
          <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-zinc-400">{label}</p>
          {icon && (
            <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-brand-tint text-brand">
              {icon}
            </span>
          )}
        </div>
        <p className="mt-1.5 text-[28px] font-extrabold leading-8 tracking-tight text-ink tabular-nums">
          {value}
        </p>
        {hint && <p className="mt-1 text-xs font-medium text-zinc-400">{hint}</p>}
      </CardBody>
    </Card>
  );
}

export function Button({
  children,
  onClick,
  type = "button",
  variant = "primary",
  disabled,
  className = "",
}: {
  children: ReactNode;
  onClick?: () => void;
  type?: "button" | "submit";
  variant?: "primary" | "outline" | "danger" | "ghost";
  disabled?: boolean;
  className?: string;
}) {
  const styles = {
    primary:
      "bg-brand text-white shadow-[0_4px_14px_-4px_rgba(124,58,237,0.5)] hover:bg-brand-deep focus-visible:ring-brand",
    outline:
      "border border-zinc-300 bg-white text-zinc-700 hover:border-zinc-400 hover:bg-zinc-50 focus-visible:ring-zinc-400",
    danger:
      "bg-red-600 text-white shadow-[0_4px_14px_-4px_rgba(220,38,38,0.5)] hover:bg-red-700 focus-visible:ring-red-500",
    ghost: "text-zinc-600 hover:bg-zinc-100 focus-visible:ring-zinc-400",
  }[variant];
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-semibold transition-all duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50 ${styles} ${className}`}
    >
      {children}
    </button>
  );
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-ink shadow-[inset_0_1px_2px_rgba(23,34,59,0.03)] outline-none transition placeholder:text-zinc-400 focus:border-brand focus:ring-4 focus:ring-brand/10 ${props.className ?? ""}`}
    />
  );
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`w-full rounded-xl border border-zinc-200 bg-white px-3.5 py-2 text-sm text-ink outline-none transition focus:border-brand focus:ring-4 focus:ring-brand/10 ${props.className ?? ""}`}
    />
  );
}

export function Label({ children }: { children: ReactNode }) {
  return (
    <label className="mb-1.5 block text-xs font-semibold text-zinc-500">{children}</label>
  );
}

export function Badge({ children, color = "zinc" }: { children: ReactNode; color?: string }) {
  const colors: Record<string, string> = {
    green: "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
    red: "bg-red-50 text-red-700 ring-red-600/20",
    orange: "bg-orange-50 text-orange-700 ring-orange-600/20",
    blue: "bg-blue-50 text-blue-700 ring-blue-600/20",
    purple: "bg-violet-50 text-violet-700 ring-violet-600/20",
    zinc: "bg-zinc-100 text-zinc-600 ring-zinc-500/20",
  };
  return (
    <span
      className={`inline-block rounded-full px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wide ring-1 ring-inset ${colors[color] ?? colors.zinc}`}
    >
      {children}
    </span>
  );
}

export const subscriptionBadge = (status?: string) =>
  ({ active: "green", trial: "blue", expired: "red", suspended: "orange" }[status ?? ""] ?? "zinc");

export function Table({ headers, children }: { headers: string[]; children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm text-zinc-700">
        <thead>
          <tr className="border-b border-zinc-200/80 bg-zinc-50/50 text-[11px] uppercase tracking-[0.1em] text-zinc-400">
            {headers.map((h, i) => (
              <th key={`${h}-${i}`} className="px-4 py-3 font-semibold first:rounded-tl-2xl last:rounded-tr-2xl">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-100">{children}</tbody>
      </table>
    </div>
  );
}

export function Spinner() {
  return (
    <div className="flex justify-center py-12">
      <div className="h-8 w-8 animate-spin rounded-full border-[3px] border-zinc-200 border-t-brand" />
    </div>
  );
}

export function Toggle({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
  label: string;
}) {
  return (
    <button
      type="button"
      onClick={() => onChange(!checked)}
      className="flex w-full items-center justify-between rounded-lg px-1.5 py-2 text-sm transition hover:bg-zinc-50"
    >
      <span className="font-medium text-zinc-700">{label}</span>
      <span
        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors duration-200 ${checked ? "bg-brand" : "bg-zinc-300"}`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white shadow-sm transition-transform duration-200 ${checked ? "translate-x-4.5" : "translate-x-0.5"}`}
        />
      </span>
    </button>
  );
}

/** Consistent page heading: title + optional subtitle + right-aligned actions. */
export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-[26px] font-extrabold tracking-tight text-ink">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-zinc-500">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
