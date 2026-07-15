"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Card, Spinner, Table } from "@/components/ui";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function PaymentsPage() {
  const [rows, setRows] = useState<any[] | null>(null);

  useEffect(() => {
    createClient()
      .from("subscription_payments")
      .select("*, businesses(id, name)")
      .order("payment_date", { ascending: false })
      .limit(200)
      .then(({ data }) => setRows(data ?? []));
  }, []);

  if (!rows) return <Spinner />;
  const total = rows.reduce((s, r) => s + Number(r.amount), 0);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-zinc-900">Subscription payments</h1>
        <p className="text-sm text-zinc-500">Showing {rows.length} • Total {inr(total)}</p>
      </div>
      <Card>
        <Table headers={["Date", "Client", "Amount", "Mode", "Note"]}>
          {rows.map((p) => (
            <tr key={p.id} className="hover:bg-zinc-50">
              <td className="px-4 py-3">{dateStr(p.payment_date)}</td>
              <td className="px-4 py-3">
                <Link href={`/clients/${p.businesses?.id}`} className="font-medium text-blue-700 hover:underline">
                  {p.businesses?.name ?? "—"}
                </Link>
              </td>
              <td className="px-4 py-3 font-semibold">{inr(p.amount)}</td>
              <td className="px-4 py-3 uppercase">{p.payment_mode}</td>
              <td className="px-4 py-3 text-zinc-500">{p.note}</td>
            </tr>
          ))}
          {rows.length === 0 && (
            <tr><td colSpan={5} className="px-4 py-10 text-center text-zinc-500">No payments recorded yet.</td></tr>
          )}
        </Table>
      </Card>
    </div>
  );
}
