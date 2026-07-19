"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner, Table,
} from "@/components/ui";
import { inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Feature = { key: string; label: string };

export default function PlansPage() {
  const supabase = createClient();
  const [plans, setPlans] = useState<any[] | null>(null);
  const [products, setProducts] = useState<any[]>([]);
  const [editing, setEditing] = useState<any | null>(null);
  // form-controlled bits that depend on the chosen product
  const [softwareId, setSoftwareId] = useState<string>("");
  const [included, setIncluded] = useState<string[]>([]);

  const load = useCallback(() => {
    supabase.from("plans").select("*, software_products(name)").order("monthly_price")
      .then(({ data }) => setPlans(data ?? []));
    supabase.from("software_products").select("id, name, status, features")
      .eq("is_active", true).order("sort_order")
      .then(({ data }) => setProducts(data ?? []));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => { if (active) load(); });
    return () => { active = false; };
  }, [load]);

  function startEdit(p: any | null) {
    setEditing(p ?? {});
    setSoftwareId(p?.software_id ?? (products.find((x) => x.status === "live") ?? products[0])?.id ?? "");
    setIncluded(Array.isArray(p?.included_features) ? p.included_features : []);
  }

  const selectedProduct = products.find((p) => p.id === softwareId);
  const productFeatures: Feature[] = Array.isArray(selectedProduct?.features) ? selectedProduct.features : [];

  function toggleFeature(key: string) {
    setIncluded((arr) => (arr.includes(key) ? arr.filter((k) => k !== key) : [...arr, key]));
  }

  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    // Only keep included keys that still exist on the chosen product.
    const validKeys = new Set(productFeatures.map((f) => f.key));
    const row = {
      name: fd.get("name") as string,
      software_id: softwareId || null,
      monthly_price: Number(fd.get("monthly_price")) || 0,
      yearly_price: Number(fd.get("yearly_price")) || 0,
      product_limit: fd.get("product_limit") ? Number(fd.get("product_limit")) : null,
      invoice_limit: fd.get("invoice_limit") ? Number(fd.get("invoice_limit")) : null,
      user_limit: fd.get("user_limit") ? Number(fd.get("user_limit")) : null,
      included_features: included.filter((k) => validKeys.has(k)),
      is_custom: fd.get("is_custom") === "on",
      notes: (fd.get("notes") as string) || "",
    };
    let planId = editing?.id as string | undefined;
    if (planId) {
      await supabase.from("plans").update(row).eq("id", planId);
    } else {
      const { data: inserted } = await supabase.from("plans").insert(row).select("id").single();
      planId = inserted?.id;
    }
    // Push the (possibly changed) feature set onto every shop already on this
    // plan, so existing clients update immediately.
    if (planId) {
      await supabase.rpc("resync_plan_features", { p_plan: planId });
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
        <Button onClick={() => startEdit(null)}>+ New plan</Button>
      </div>

      {editing && (
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">
              {editing.id ? "Edit plan" : "New plan"}
            </h2>
            <form onSubmit={save} className="space-y-4">
              <div className="grid grid-cols-3 gap-4">
                <div className="col-span-3">
                  <Label>Plan name *</Label>
                  <Input name="name" required defaultValue={editing.name ?? ""} />
                </div>

                <div className="col-span-3">
                  <Label>Product *</Label>
                  <Select value={softwareId} onChange={(e) => { setSoftwareId(e.target.value); setIncluded([]); }}>
                    {products.length === 0 && <option value="">— no products yet —</option>}
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}{p.status !== "live" ? " (coming soon)" : ""}
                      </option>
                    ))}
                  </Select>
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
                  <Label>Max staff logins (blank = unlimited)</Label>
                  <Input name="user_limit" type="number" defaultValue={editing.user_limit ?? ""} />
                </div>
                <div>
                  <Label>Product limit (blank = unlimited)</Label>
                  <Input name="product_limit" type="number" defaultValue={editing.product_limit ?? ""} />
                </div>
                <div>
                  <Label>Invoice limit / month</Label>
                  <Input name="invoice_limit" type="number" defaultValue={editing.invoice_limit ?? ""} />
                </div>

                <div className="col-span-3">
                  <Label>Notes</Label>
                  <Input name="notes" defaultValue={editing.notes ?? ""} />
                </div>
              </div>

              {/* Feature picker — from the chosen product's master list */}
              <div className="rounded-xl border border-zinc-200 p-4">
                <Label>Included features</Label>
                {productFeatures.length === 0 ? (
                  <p className="mt-1 text-sm text-zinc-400">
                    This product has no features defined yet. Add them on the{" "}
                    <a href="/products" className="text-brand hover:underline">Products</a> page first.
                  </p>
                ) : (
                  <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-3">
                    {productFeatures.map((f) => (
                      <label key={f.key} className="flex items-center gap-2 rounded-lg border border-zinc-200 px-3 py-2 text-sm hover:bg-zinc-50">
                        <input
                          type="checkbox"
                          checked={included.includes(f.key)}
                          onChange={() => toggleFeature(f.key)}
                        />
                        {f.label}
                      </label>
                    ))}
                  </div>
                )}
              </div>

              <div className="flex gap-2">
                <Button type="submit">Save plan</Button>
                <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              </div>
            </form>
          </CardBody>
        </Card>
      )}

      <Card>
        <Table headers={["Plan", "Product", "Monthly", "Yearly", "Users", "Features", "Status", ""]}>
          {plans.map((p) => (
            <tr key={p.id} className="hover:bg-zinc-50">
              <td className="px-4 py-3 font-medium">
                {p.name} {p.is_custom && <Badge color="purple">custom</Badge>}
              </td>
              <td className="px-4 py-3">{p.software_products?.name ?? "—"}</td>
              <td className="px-4 py-3">{inr(p.monthly_price)}</td>
              <td className="px-4 py-3">{inr(p.yearly_price)}</td>
              <td className="px-4 py-3">{p.user_limit ?? "∞"}</td>
              <td className="px-4 py-3">{Array.isArray(p.included_features) ? p.included_features.length : 0}</td>
              <td className="px-4 py-3">
                <Badge color={p.is_active ? "green" : "zinc"}>{p.is_active ? "active" : "hidden"}</Badge>
              </td>
              <td className="space-x-3 px-4 py-3 text-right">
                <button className="text-sm font-medium text-brand hover:underline" onClick={() => startEdit(p)}>Edit</button>
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
