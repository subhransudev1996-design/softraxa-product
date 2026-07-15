"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, CardBody, Input, Label, Spinner, Table,
} from "@/components/ui";
import { inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function PlansPage() {
  const supabase = createClient();
  const [plans, setPlans] = useState<any[] | null>(null);
  const [editing, setEditing] = useState<any | null>(null);

  const load = useCallback(() => {
    supabase.from("plans").select("*").order("monthly_price")
      .then(({ data }) => setPlans(data ?? []));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(load, [load]);

  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const row = {
      name: fd.get("name") as string,
      monthly_price: Number(fd.get("monthly_price")) || 0,
      yearly_price: Number(fd.get("yearly_price")) || 0,
      product_limit: fd.get("product_limit") ? Number(fd.get("product_limit")) : null,
      invoice_limit: fd.get("invoice_limit") ? Number(fd.get("invoice_limit")) : null,
      is_custom: fd.get("is_custom") === "on",
      notes: (fd.get("notes") as string) || "",
    };
    if (editing?.id) {
      await supabase.from("plans").update(row).eq("id", editing.id);
    } else {
      await supabase.from("plans").insert(row);
    }
    setEditing(null);
    load();
  }

  async function toggleActive(plan: any) {
    await supabase.from("plans").update({ is_active: !plan.is_active }).eq("id", plan.id);
    load();
  }

  if (!plans) return <Spinner />;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-zinc-900">Plans</h1>
        <Button onClick={() => setEditing({})}>+ New plan</Button>
      </div>

      {editing && (
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">
              {editing.id ? "Edit plan" : "New plan"}
            </h2>
            <form onSubmit={save} className="grid grid-cols-3 gap-4">
              <div className="col-span-3">
                <Label>Plan name *</Label>
                <Input name="name" required defaultValue={editing.name ?? ""} />
              </div>
              <div>
                <Label>Monthly price ₹</Label>
                <Input name="monthly_price" type="number" step="0.01" defaultValue={editing.monthly_price ?? ""} />
              </div>
              <div>
                <Label>Yearly price ₹</Label>
                <Input name="yearly_price" type="number" step="0.01" defaultValue={editing.yearly_price ?? ""} />
              </div>
              <div className="flex items-end gap-2 pb-2">
                <input id="is_custom" name="is_custom" type="checkbox" defaultChecked={editing.is_custom} />
                <label htmlFor="is_custom" className="text-sm">Custom plan</label>
              </div>
              <div>
                <Label>Product limit (blank = unlimited)</Label>
                <Input name="product_limit" type="number" defaultValue={editing.product_limit ?? ""} />
              </div>
              <div>
                <Label>Invoice limit / month</Label>
                <Input name="invoice_limit" type="number" defaultValue={editing.invoice_limit ?? ""} />
              </div>
              <div>
                <Label>Notes</Label>
                <Input name="notes" defaultValue={editing.notes ?? ""} />
              </div>
              <div className="col-span-3 flex gap-2">
                <Button type="submit">Save plan</Button>
                <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              </div>
            </form>
          </CardBody>
        </Card>
      )}

      <Card>
        <Table headers={["Plan", "Monthly", "Yearly", "Products", "Invoices/mo", "Status", ""]}>
          {plans.map((p) => (
            <tr key={p.id} className="hover:bg-zinc-50">
              <td className="px-4 py-3 font-medium">
                {p.name} {p.is_custom && <Badge color="purple">custom</Badge>}
              </td>
              <td className="px-4 py-3">{inr(p.monthly_price)}</td>
              <td className="px-4 py-3">{inr(p.yearly_price)}</td>
              <td className="px-4 py-3">{p.product_limit ?? "∞"}</td>
              <td className="px-4 py-3">{p.invoice_limit ?? "∞"}</td>
              <td className="px-4 py-3">
                <Badge color={p.is_active ? "green" : "zinc"}>{p.is_active ? "active" : "hidden"}</Badge>
              </td>
              <td className="space-x-3 px-4 py-3 text-right">
                <button className="text-sm font-medium text-blue-700 hover:underline" onClick={() => setEditing(p)}>Edit</button>
                <button className="text-sm font-medium text-zinc-500 hover:underline" onClick={() => toggleActive(p)}>
                  {p.is_active ? "Hide" : "Show"}
                </button>
              </td>
            </tr>
          ))}
        </Table>
      </Card>
    </div>
  );
}
