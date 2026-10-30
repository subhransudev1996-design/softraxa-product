"use client";

import { ReactNode } from "react";

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`rounded-lg border border-zinc-200 bg-white ${className}`}>{children}</div>;
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
      <CardBody className="!p-4">
        <div className="flex items-start justify-between gap-2">
          <p className="text-[13px] font-medium text-zinc-500">{label}</p>
          {icon && <span className="shrink-0 text-zinc-400">{icon}</span>}
        </div>
        <p className="mt-1 text-2xl font-semibold tracking-tight text-ink tabular-nums">{value}</p>
        {hint && <p className="mt-0.5 text-xs text-zinc-500">{hint}</p>}
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
    primary: "bg-brand text-white hover:bg-brand-deep focus-visible:ring-brand",
    outline: "border border-zinc-300 bg-white text-zinc-800 hover:bg-zinc-50 focus-visible:ring-zinc-400",
    danger: "bg-red-600 text-white hover:bg-red-700 focus-visible:ring-red-500",
    ghost: "text-zinc-600 hover:bg-zinc-100 hover:text-ink focus-visible:ring-zinc-400",
  }[variant];
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex min-h-9 cursor-pointer items-center gap-2 rounded-md px-3.5 py-1.5 text-sm font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 ${styles} ${className}`}
    >
      {children}
    </button>
  );
}

export function Input(props: React.ComponentProps<"input">) {
  return (
    <input
      {...props}
      className={`min-h-9 w-full rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-ink outline-none transition-colors placeholder:text-zinc-400 focus:border-brand focus:ring-2 focus:ring-brand/20 disabled:bg-zinc-50 disabled:text-zinc-500 ${props.className ?? ""}`}
    />
  );
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`min-h-9 w-full cursor-pointer rounded-md border border-zinc-300 bg-white px-3 py-1.5 text-sm text-ink outline-none transition-colors focus:border-brand focus:ring-2 focus:ring-brand/20 ${props.className ?? ""}`}
    />
  );
}

export function Label({ children }: { children: ReactNode }) {
  return (
    <label className="mb-1 block text-[13px] font-medium text-zinc-700">{children}</label>
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
      className={`inline-block rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${colors[color] ?? colors.zinc}`}
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
      <table className="w-full text-left text-sm text-zinc-700 [&_tbody_tr]:transition-colors [&_tbody_tr:hover]:bg-zinc-50">
        <thead>
          <tr className="border-b border-zinc-200 bg-zinc-50 text-xs text-zinc-500">
            {headers.map((h, i) => (
              <th key={`${h}-${i}`} className="whitespace-nowrap px-4 py-2.5 font-medium">
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
      <div className="h-6 w-6 animate-spin rounded-full border-2 border-zinc-200 border-t-brand" />
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
      className="flex w-full cursor-pointer items-center justify-between rounded-md px-1.5 py-2 text-sm transition-colors hover:bg-zinc-50"
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
        <h1 className="text-xl font-semibold tracking-tight text-ink">{title}</h1>
        {subtitle && <p className="mt-0.5 text-sm text-zinc-500">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}
