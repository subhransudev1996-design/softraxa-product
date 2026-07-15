"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Card, Input, Spinner, Table } from "@/components/ui";
import { dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function AuditPage() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [action, setAction] = useState("");

  useEffect(() => {
    const supabase = createClient();
    let query = supabase
      .from("audit_logs")
      .select("*, businesses(name)")
      .order("created_at", { ascending: false })
      .limit(300);
    if (action.trim()) query = query.ilike("action", `%${action.trim()}%`);
    query.then(({ data }) => setRows(data ?? []));
  }, [action]);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-zinc-900">Audit logs</h1>
      <Input
        placeholder="Filter by action (e.g. invoice.created, login)…"
        value={action}
        onChange={(e) => setAction(e.target.value)}
        className="max-w-sm"
      />
      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <Table headers={["Time", "Client", "Action", "Entity", "Details"]}>
            {rows.map((l) => (
              <tr key={l.id} className="hover:bg-zinc-50">
                <td className="px-4 py-3 whitespace-nowrap">{dateTimeStr(l.created_at)}</td>
                <td className="px-4 py-3">{l.businesses?.name ?? "—"}</td>
                <td className="px-4 py-3"><Badge color="blue">{l.action}</Badge></td>
                <td className="px-4 py-3 text-zinc-500">{l.entity}</td>
                <td className="max-w-md truncate px-4 py-3 text-xs text-zinc-500">
                  {JSON.stringify(l.details)}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-10 text-center text-zinc-500">No activity logged yet.</td></tr>
            )}
          </Table>
        </Card>
      )}
    </div>
  );
}
