"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, Input, Spinner, Table, subscriptionBadge,
} from "@/components/ui";
import { dateStr } from "@/lib/format";

type ClientRow = {
  id: string;
  name: string;
  owner_name: string;
  business_type: string;
  phone: string;
  is_active: boolean;
  created_at: string;
  subscriptions: { status: string; expiry_date: string; plans: { name: string } | null; software: { name: string } | null }[];
};

export default function ClientsPage() {
  const [rows, setRows] = useState<ClientRow[] | null>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    const supabase = createClient();
    let query = supabase
      .from("businesses")
      .select("id, name, owner_name, business_type, phone, is_active, created_at, subscriptions(status, expiry_date, plans(name), software:software_products(name))")
      .order("created_at", { ascending: false });
    if (search.trim()) query = query.ilike("name", `%${search.trim()}%`);
    query.then(({ data }) => setRows((data as unknown as ClientRow[]) ?? []));
  }, [search]);

  async function toggleStatus(clientId: string, isCurrentlyActive: boolean) {
    const res = await fetch("/api/clients/toggle-status", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ businessId: clientId, suspend: isCurrentlyActive }),
    });
    if (res.ok) {
      // Reload rows
      const supabase = createClient();
      const { data } = await supabase
        .from("businesses")
        .select("id, name, owner_name, business_type, phone, is_active, created_at, subscriptions(status, expiry_date, plans(name), software:software_products(name))")
        .order("created_at", { ascending: false });
      setRows((data as unknown as ClientRow[]) ?? []);
    } else {
      const err = await res.json().catch(() => ({}));
      window.alert(err.error || "Failed to update client status");
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-zinc-900">Clients</h1>
        <Link href="/clients/new">
          <Button>+ New client</Button>
        </Link>
      </div>
      <Input
        placeholder="Search business name…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="max-w-sm"
      />
      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <Table headers={["Business", "Owner", "Software", "Plan", "Status", "Expires", "Actions"]}>
            {rows.map((c) => {
              const sub = c.subscriptions?.[0];
              const displayStatus = !c.is_active ? "suspended" : (sub?.status ?? "none");
              return (
                <tr key={c.id} className="hover:bg-zinc-50">
                  <td className="px-4 py-3 font-medium text-zinc-900">
                    {c.name}
                    {!c.is_active && <span className="ml-2"><Badge color="red">suspended</Badge></span>}
                  </td>
                  <td className="px-4 py-3">{c.owner_name || "—"}</td>
                  <td className="px-4 py-3">{sub?.software?.name ?? "—"}</td>
                  <td className="px-4 py-3">{sub?.plans?.name ?? "—"}</td>
                  <td className="px-4 py-3">
                    <Badge color={subscriptionBadge(displayStatus)}>{displayStatus}</Badge>
                  </td>
                  <td className="px-4 py-3">{dateStr(sub?.expiry_date)}</td>
                  <td className="px-4 py-3 text-right flex items-center justify-end gap-3">
                    <button
                      onClick={() => toggleStatus(c.id, c.is_active)}
                      className={`text-xs font-semibold px-2.5 py-1 rounded-md transition-colors ${
                        c.is_active
                          ? "bg-red-50 text-red-700 hover:bg-red-100 border border-red-200"
                          : "bg-green-50 text-green-700 hover:bg-green-100 border border-green-200"
                      }`}
                    >
                      {c.is_active ? "Suspend" : "Activate"}
                    </button>
                    <Link href={`/clients/${c.id}`} className="text-sm font-medium text-brand hover:underline">
                      Manage
                    </Link>
                  </td>
                </tr>
              );
            })}
            {rows.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-10 text-center text-zinc-500">
                  No clients yet.
                </td>
              </tr>
            )}
          </Table>
        </Card>
      )}
    </div>
  );
}
