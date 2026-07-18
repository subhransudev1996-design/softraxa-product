"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Card, Select, Spinner, Table } from "@/components/ui";
import { dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function SupportPage() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [filter, setFilter] = useState("open");

  const load = useCallback(() => {
    let query = supabase
      .from("support_tickets")
      .select("*, businesses(id, name)")
      .order("created_at", { ascending: false })
      .limit(200);
    if (filter !== "all") query = query.eq("status", filter);
    query.then(({ data }) => setRows(data ?? []));
  }, [filter]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(load, [load]);

  async function setStatus(id: string, status: string) {
    await supabase.from("support_tickets").update({ status }).eq("id", id);
    load();
  }

  async function setNote(id: string, internal_note: string) {
    await supabase.from("support_tickets").update({ internal_note }).eq("id", id);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-zinc-900">Support tickets</h1>
        <Select value={filter} onChange={(e) => setFilter(e.target.value)} className="w-44">
          <option value="all">All</option>
          <option value="open">Open</option>
          <option value="in_progress">In progress</option>
          <option value="resolved">Resolved</option>
        </Select>
      </div>
      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <Table headers={["Client", "Subject", "Created", "Status", "Internal note"]}>
            {rows.map((t) => (
              <tr key={t.id} className="align-top hover:bg-zinc-50">
                <td className="px-4 py-3">
                  <Link href={`/clients/${t.businesses?.id}`} className="font-medium text-brand hover:underline">
                    {t.businesses?.name ?? "—"}
                  </Link>
                </td>
                <td className="px-4 py-3">
                  <p className="font-medium">{t.subject}</p>
                  <p className="text-xs text-zinc-500">{t.message}</p>
                </td>
                <td className="px-4 py-3 whitespace-nowrap">{dateTimeStr(t.created_at)}</td>
                <td className="px-4 py-3">
                  <Select
                    value={t.status}
                    onChange={(e) => setStatus(t.id, e.target.value)}
                    className="w-36"
                  >
                    <option value="open">Open</option>
                    <option value="in_progress">In progress</option>
                    <option value="resolved">Resolved</option>
                  </Select>
                </td>
                <td className="px-4 py-3">
                  <input
                    defaultValue={t.internal_note}
                    placeholder="Add note…"
                    onBlur={(e) => setNote(t.id, e.target.value)}
                    className="w-full rounded border border-zinc-200 px-2 py-1 text-xs"
                  />
                </td>
              </tr>
            ))}
            {rows.length === 0 && (
              <tr><td colSpan={5} className="px-4 py-10 text-center text-zinc-500">No tickets.</td></tr>
            )}
          </Table>
        </Card>
      )}
    </div>
  );
}
