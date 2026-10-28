"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Card, Input, Select, Spinner, Table } from "@/components/ui";
import { memberName, useTeam } from "@/components/me";
import { dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function AuditPage() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [action, setAction] = useState("");
  // Who did it: shop logins show the shop; team members show their name (0098).
  const team = useTeam();
  const [person, setPerson] = useState("");

  useEffect(() => {
    const supabase = createClient();
    let query = supabase
      .from("audit_logs")
      .select("*, businesses(name)")
      .order("created_at", { ascending: false })
      .limit(300);
    if (action.trim()) query = query.ilike("action", `%${action.trim()}%`);
    if (person) query = query.eq("user_id", person);
    query.then(({ data }) => setRows(data ?? []));
  }, [action, person]);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-zinc-900">Audit logs</h1>
      <div className="flex flex-col gap-3 sm:flex-row">
        <Input
          placeholder="Filter by action (e.g. invoice.created, login)…"
          value={action}
          onChange={(e) => setAction(e.target.value)}
          className="max-w-sm"
        />
        <Select value={person} onChange={(e) => setPerson(e.target.value)} className="max-w-xs">
          <option value="">Everyone</option>
          {team.map((m) => (
            <option key={m.id} value={m.id}>{m.name || m.email}{m.active ? "" : " (removed)"}</option>
          ))}
        </Select>
      </div>
      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <Table headers={["Time", "Who", "Client", "Action", "Entity", "Details"]}>
            {rows.map((l) => (
              <tr key={l.id} className="hover:bg-zinc-50">
                <td className="px-4 py-3 whitespace-nowrap">{dateTimeStr(l.created_at)}</td>
                <td className="px-4 py-3 whitespace-nowrap font-medium">
                  {memberName(team, l.user_id) ?? (l.user_id ? <span className="text-zinc-400">Shop login</span> : <span className="text-zinc-400">System</span>)}
                </td>
                <td className="px-4 py-3">{l.businesses?.name ?? "—"}</td>
                <td className="px-4 py-3"><Badge color="blue">{l.action}</Badge></td>
                <td className="px-4 py-3 text-zinc-500">{l.entity}</td>
                <td className="max-w-md truncate px-4 py-3 text-xs text-zinc-500">
                  {JSON.stringify(l.details)}
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={6} className="px-4 py-10 text-center text-zinc-500">No activity logged yet.</td></tr>
            )}
          </Table>
        </Card>
      )}
    </div>
  );
}
