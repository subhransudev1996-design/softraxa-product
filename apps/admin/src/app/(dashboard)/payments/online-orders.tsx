"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Card, CardBody, Table } from "@/components/ui";
import { dateTimeStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const STATUS: Record<string, [string, string]> = {
  paid: ["Paid", "green"],
  created: ["Not paid", "zinc"],
  failed: ["Problem", "red"],
};

/**
 * Checkouts on dukania.in/pay (migration 0105), newest first. "Not paid"
 * is a checkout the shop opened and left; "Problem" needs a look (the
 * amount paid didn't match), with Razorpay's payment ID to find it there.
 */
export function OnlineOrders() {
  const [rows, setRows] = useState<any[] | null>(null);

  useEffect(() => {
    createClient().from("online_orders").select("*, businesses(id, name)").order("created_at", { ascending: false }).limit(30)
      .then(({ data, error }) => setRows(error ? [] : data ?? []));
  }, []);

  if (!rows || rows.length === 0) return null;
  return (
    <Card>
      <CardBody>
        <h2 className="mb-3 text-sm font-semibold text-zinc-700">Online checkouts (Razorpay)</h2>
        <Table headers={["When", "Shop", "For", "Amount", "Status", "Razorpay"]}>
          {rows.map((o) => {
            const [label, color] = STATUS[o.status] ?? [o.status, "zinc"];
            const what = o.kind === "plan"
              ? `${o.quote?.plan ?? "Plan"}${o.quote?.extra_staff ? ` + ${o.quote.extra_staff} staff` : ""}${o.quote?.ai_addon ? " + AI" : ""}`
              : o.quote?.addon === "ai" ? "AI assistant" : `${o.quote?.quantity ?? ""} staff login(s)`;
            return (
              <tr key={o.id}>
                <td className="whitespace-nowrap px-4 py-3 text-xs">{dateTimeStr(o.created_at)}</td>
                <td className="px-4 py-3">
                  <Link href={`/clients/${o.businesses?.id}`} className="font-medium text-brand hover:underline">{o.businesses?.name ?? "—"}</Link>
                </td>
                <td className="px-4 py-3 text-xs">
                  {what}
                  {o.quote?.code && <span className="block text-zinc-500">Code {o.quote.code}</span>}
                </td>
                <td className="whitespace-nowrap px-4 py-3 font-semibold">{inr(o.amount)}</td>
                <td className="px-4 py-3">
                  <Badge color={color}>{label}</Badge>
                  {o.error && <span className="mt-1 block max-w-56 text-xs text-red-600">{o.error}</span>}
                </td>
                <td className="px-4 py-3 font-mono text-xs">{o.rzp_payment_id || o.rzp_order_id}</td>
              </tr>
            );
          })}
        </Table>
      </CardBody>
    </Card>
  );
}
