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
  subscriptions: { status: string; expiry_date: string; plans: { name: string } | null }[];
};

export default function ClientsPage() {
  const [rows, setRows] = useState<ClientRow[] | null>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    const supabase = createClient();
    let query = supabase
      .from("businesses")
      .select("id, name, owner_name, business_type, phone, is_active, created_at, subscriptions(status, expiry_date, plans(name))")
      .order("created_at", { ascending: false });
    if (search.trim()) query = query.ilike("name", `%${search.trim()}%`);
    query.then(({ data }) => setRows((data as unknown as ClientRow[]) ?? []));
  }, [search]);

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
          <Table headers={["Business", "Owner", "Type", "Plan", "Status", "Expires", ""]}>
            {rows.map((c) => {
              const sub = c.subscriptions?.[0];
              return (
                <tr key={c.id} className="hover:bg-zinc-50">
                  <td className="px-4 py-3 font-medium text-zinc-900">
                    {c.name}
                    {!c.is_active && <span className="ml-2"><Badge color="red">disabled</Badge></span>}
                  </td>
                  <td className="px-4 py-3">{c.owner_name || "—"}</td>
                  <td className="px-4 py-3 capitalize">{c.business_type}</td>
                  <td className="px-4 py-3">{sub?.plans?.name ?? "—"}</td>
                  <td className="px-4 py-3">
                    <Badge color={subscriptionBadge(sub?.status)}>{sub?.status ?? "none"}</Badge>
                  </td>
                  <td className="px-4 py-3">{dateStr(sub?.expiry_date)}</td>
                  <td className="px-4 py-3 text-right">
                    <Link href={`/clients/${c.id}`} className="text-sm font-medium text-blue-700 hover:underline">
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
