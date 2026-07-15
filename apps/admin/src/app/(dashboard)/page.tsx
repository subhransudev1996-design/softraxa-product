"use client";

import { useEffect, useState } from "react";
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

export default function AdminDashboardPage() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    createClient()
      .rpc("get_admin_dashboard")
      .then(({ data, error }) => {
        if (error) setError(error.message);
        else setData(data as Dashboard);
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
