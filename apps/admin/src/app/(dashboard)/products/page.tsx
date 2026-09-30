"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  Badge, Button, Card, CardBody, Input, Label, Select, Spinner, Table,
} from "@/components/ui";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Feature = { key: string; label: string };

// Turn a human label into a stable slug.
const toSlug = (s: string) =>
  s.trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");

export default function ProductsPage() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [editing, setEditing] = useState<any | null>(null);

  const load = useCallback(() => {
    supabase.from("software_products").select("*").order("sort_order")
      .then(({ data }) => setRows(data ?? []));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => { if (active) load(); });
    return () => { active = false; };
  }, [load]);

  function startEdit(p: any | null) {
    setEditing(p ?? {});
  }

  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const name = (fd.get("name") as string).trim();
    // Features are FIXED BY THE APP, not editable here — we never write the
    // `features` column from this form. (Dukania's list is seeded by migration
    // 0033 to match exactly what the Flutter app enforces.)
    const row = {
      name,
      slug: (fd.get("slug") as string).trim() || toSlug(name),
      tagline: (fd.get("tagline") as string) || "",
      status: fd.get("status") as string,
      trial_days: Number(fd.get("trial_days")) || 14,
    };
    if (editing?.id) {
      await supabase.from("software_products").update(row).eq("id", editing.id);
    } else {
      await supabase.from("software_products").insert(row);
    }
    setEditing(null);
    load();
  }

  if (!rows) return <Spinner />;

  const editingFeatures: Feature[] = Array.isArray(editing?.features) ? editing.features : [];

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">Software</h1>
          <p className="mt-1 text-sm text-zinc-500">The software Softraxa sells (Dukania and the ones to come). Each one defines its own feature list. For the products shops sell, see Master products.</p>
        </div>
        <Button onClick={() => startEdit(null)}>+ New product</Button>
      </div>

      {editing && (
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">
              {editing.id ? "Edit product" : "New product"}
            </h2>
            <form onSubmit={save} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label>Product name *</Label>
                  <Input name="name" required defaultValue={editing.name ?? ""} placeholder="Dukania" />
                </div>
                <div>
                  <Label>Slug (URL id, blank = auto)</Label>
                  <Input name="slug" defaultValue={editing.slug ?? ""} placeholder="dukania" />
                </div>
                <div className="col-span-2">
                  <Label>Tagline</Label>
                  <Input name="tagline" defaultValue={editing.tagline ?? ""} placeholder="Offline-first billing & inventory for real shops" />
                </div>
                <div>
                  <Label>Status</Label>
                  <Select name="status" defaultValue={editing.status ?? "coming_soon"}>
                    <option value="live">Live</option>
                    <option value="coming_soon">Coming soon</option>
                    <option value="retired">Retired</option>
                  </Select>
                </div>
                <div>
                  <Label>Trial days</Label>
                  <Input name="trial_days" type="number" defaultValue={editing.trial_days ?? 14} />
                </div>
              </div>

              {/* App-defined feature list — read only. Features come FROM the
                  app (what it actually enforces), not invented here. Plans pick
                  which of these to include. */}
              <div className="rounded-xl border border-zinc-200 bg-zinc-50/50 p-4">
                <Label>Features (defined by the app — not editable)</Label>
                <p className="mb-3 mt-1 text-xs text-zinc-500">
                  These are the capabilities the app actually supports for this product.
                  On the Plans page you choose which of these a plan includes; anything
                  a plan leaves out is hidden in the app for shops on that plan.
                </p>
                {editingFeatures.length === 0 ? (
                  <p className="text-sm text-zinc-400">
                    No app features registered for this product yet.
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {editingFeatures.map((f) => (
                      <span key={f.key} className="inline-flex items-center gap-1.5 rounded-lg border border-zinc-200 bg-white px-2.5 py-1 text-sm text-zinc-700">
                        {f.label}
                        <code className="text-[11px] text-zinc-400">{f.key}</code>
                      </span>
                    ))}
                  </div>
                )}
              </div>

              <div className="flex gap-2">
                <Button type="submit">Save product</Button>
                <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              </div>
            </form>
          </CardBody>
        </Card>
      )}

      <Card>
        <Table headers={["Product", "Slug", "Status", "Trial", "Features", ""]}>
          {rows.map((p) => (
            <tr key={p.id} className="hover:bg-zinc-50">
              <td className="px-4 py-3 font-medium">{p.name}</td>
              <td className="px-4 py-3 font-mono text-xs text-zinc-500">{p.slug}</td>
              <td className="px-4 py-3">
                <Badge color={p.status === "live" ? "green" : p.status === "retired" ? "zinc" : "blue"}>
                  {p.status === "coming_soon" ? "coming soon" : p.status}
                </Badge>
              </td>
              <td className="px-4 py-3">{p.trial_days}d</td>
              <td className="px-4 py-3">{Array.isArray(p.features) ? p.features.length : 0}</td>
              <td className="px-4 py-3 text-right">
                <button className="text-sm font-medium text-brand hover:underline" onClick={() => startEdit(p)}>Edit</button>
              </td>
            </tr>
          ))}
          {rows.length === 0 && (
            <tr><td colSpan={6} className="px-4 py-10 text-center text-zinc-500">No products yet.</td></tr>
          )}
        </Table>
      </Card>
    </div>
  );
}
