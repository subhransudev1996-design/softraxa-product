"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Card, CardBody, Spinner, StatCard } from "@/components/ui";
import { inr } from "@/lib/format";

type Dashboard = {
  total_clients: number;
  active_clients: number;
  trial_clients: number;
  expired_clients: number;
  suspended_clients: number;
  monthly_revenue: number;
  new_clients_this_month: number;
  plan_wise: { plan: string; clients: number }[];
  open_tickets: number;
};

type LeadStats = {
  open: number;
  overdue: number;
  convertedThisMonth: number;
  convRate: number | null;
};

export default function AdminDashboardPage() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [leads, setLeads] = useState<LeadStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase
      .rpc("get_admin_dashboard")
      .then(({ data, error }) => {
        if (error) setError(error.message);
        else setData(data as Dashboard);
      });
    // Lead/pipeline stats (table may not exist until migration 0026 is run —
    // in that case the query errors and the card simply doesn't render).
    supabase
      .from("leads")
      .select("status, follow_up_date, converted_at")
      .then(({ data: rows }) => {
        if (!rows) return;
        const today = new Date().toISOString().slice(0, 10);
        const monthStart = today.slice(0, 8) + "01";
        const open = rows.filter((r) => ["new", "contacted", "demo"].includes(r.status));
        const converted = rows.filter((r) => r.status === "converted");
        const closed = converted.length + rows.filter((r) => r.status === "lost").length;
        setLeads({
          open: open.length,
          overdue: open.filter((r) => r.follow_up_date && r.follow_up_date < today).length,
          convertedThisMonth: converted.filter((r) => (r.converted_at ?? "").slice(0, 10) >= monthStart).length,
          convRate: closed ? Math.round((converted.length / closed) * 100) : null,
        });
      });
  }, []);

  if (error) return <p className="text-red-600">{error}</p>;
  if (!data) return <Spinner />;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-zinc-900">Dashboard</h1>
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Total clients" value={data.total_clients} />
        <StatCard label="Active" value={data.active_clients} />
        <StatCard label="Trial" value={data.trial_clients} />
        <StatCard label="Expired" value={data.expired_clients} hint={`${data.suspended_clients} suspended`} />
        <StatCard label="Revenue this month" value={inr(data.monthly_revenue)} />
        <StatCard label="New clients this month" value={data.new_clients_this_month} />
        <StatCard label="Open support tickets" value={data.open_tickets} />
      </div>
      {leads && (
        <Card>
          <CardBody>
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold text-zinc-700">Sales pipeline</h2>
              <Link href="/leads" className="text-sm font-medium text-blue-700 hover:underline">
                Manage leads →
              </Link>
            </div>
            <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
              <StatCard label="Open leads" value={leads.open} />
              <StatCard label="Follow-ups overdue" value={leads.overdue} />
              <StatCard label="Converted this month" value={leads.convertedThisMonth} />
              <StatCard label="Conversion rate" value={leads.convRate === null ? "—" : `${leads.convRate}%`} />
            </div>
          </CardBody>
        </Card>
      )}
      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Clients by plan</h2>
          {data.plan_wise.length === 0 ? (
            <p className="text-sm text-zinc-500">No subscriptions yet.</p>
          ) : (
            <ul className="space-y-2">
              {data.plan_wise.map((p) => (
                <li key={p.plan} className="flex items-center justify-between text-sm">
                  <span>{p.plan}</span>
                  <span className="font-semibold">{p.clients}</span>
                </li>
              ))}
            </ul>
          )}
        </CardBody>
      </Card>
    </div>
  );
}
