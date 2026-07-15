"use client";

import { ReactNode } from "react";

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-xl border border-zinc-200 bg-white shadow-sm ${className}`}>
      {children}
    </div>
  );
}

export function CardBody({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`p-5 ${className}`}>{children}</div>;
}

export function StatCard({ label, value, hint }: { label: string; value: string | number; hint?: string }) {
  return (
    <Card>
      <CardBody>
        <p className="text-xs font-medium uppercase tracking-wide text-zinc-500">{label}</p>
        <p className="mt-1 text-2xl font-bold text-zinc-900">{value}</p>
        {hint && <p className="mt-1 text-xs text-zinc-400">{hint}</p>}
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
    primary: "bg-blue-700 text-white hover:bg-blue-800",
    outline: "border border-zinc-300 text-zinc-700 hover:bg-zinc-50",
    danger: "bg-red-600 text-white hover:bg-red-700",
    ghost: "text-zinc-600 hover:bg-zinc-100",
  }[variant];
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-50 ${styles} ${className}`}
    >
      {children}
    </button>
  );
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 ${props.className ?? ""}`}
    />
  );
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm outline-none focus:border-blue-600 ${props.className ?? ""}`}
    />
  );
}

export function Label({ children }: { children: ReactNode }) {
  return <label className="mb-1 block text-xs font-medium text-zinc-600">{children}</label>;
}

export function Badge({ children, color = "zinc" }: { children: ReactNode; color?: string }) {
  const colors: Record<string, string> = {
    green: "bg-green-100 text-green-800",
    red: "bg-red-100 text-red-800",
    orange: "bg-orange-100 text-orange-800",
    blue: "bg-blue-100 text-blue-800",
    purple: "bg-purple-100 text-purple-800",
    zinc: "bg-zinc-100 text-zinc-700",
  };
  return (
    <span className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase ${colors[color] ?? colors.zinc}`}>
      {children}
    </span>
  );
}

export const subscriptionBadge = (status?: string) =>
  ({ active: "green", trial: "blue", expired: "red", suspended: "orange" }[status ?? ""] ?? "zinc");

export function Table({ headers, children }: { headers: string[]; children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-zinc-200 text-xs uppercase tracking-wide text-zinc-500">
            {headers.map((h) => (
              <th key={h} className="px-4 py-3 font-medium">{h}</th>
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
      <div className="h-7 w-7 animate-spin rounded-full border-2 border-zinc-300 border-t-blue-700" />
    </div>
  );
}

export function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button
      type="button"
      onClick={() => onChange(!checked)}
      className="flex w-full items-center justify-between rounded-lg px-1 py-2 text-sm hover:bg-zinc-50"
    >
      <span className="text-zinc-700">{label}</span>
      <span
        className={`relative inline-flex h-5 w-9 items-center rounded-full transition ${checked ? "bg-blue-700" : "bg-zinc-300"}`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white transition ${checked ? "translate-x-4.5" : "translate-x-0.5"}`}
        />
      </span>
    </button>
  );
}
