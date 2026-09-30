"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Input, Label, Select, Spinner } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Feature = { key: string; label: string };

type Form = {
  id: string | null;
  name: string;
  description: string;
  highlights: string;
  software_id: string;
  monthly_price: string;
  yearly_price: string;
  user_limit: string;
  product_limit: string;
  invoice_limit: string;
  included: string[];
  sort_order: string;
  is_custom: boolean;
  is_trial: boolean;
  is_recommended: boolean;
  notes: string;
};

const str = (v: unknown) => (v === null || v === undefined ? "" : String(v));
const numOrNull = (v: string) => (v.trim() === "" ? null : Number(v));

const limitsText = (p: { user_limit: any; product_limit: any; invoice_limit: any }) =>
  [
    p.user_limit == null ? "Unlimited logins" : Number(p.user_limit) === 1 ? "Owner login only" : `${p.user_limit} logins`,
    p.product_limit == null ? "Unlimited products" : `${p.product_limit} products`,
    p.invoice_limit == null ? "Unlimited bills" : `${p.invoice_limit} bills a month`,
  ];

/**
 * Plans (migration 0055). Prices stay in this panel: the app shows a plan's
 * name, description, highlights, limits and features, never what it costs.
 * Every change goes through admin_save_plan and is logged.
 */
export default function PlansPage() {
  const supabase = createClient();
  const [plans, setPlans] = useState<any[] | null>(null);
  const [products, setProducts] = useState<any[]>([]);
  const [shops, setShops] = useState<Record<string, number>>({});
  const [form, setForm] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase.from("plans").select("*, software_products(name)").order("sort_order").order("name")
      .then(({ data }) => setPlans(data ?? []));
    supabase.from("software_products").select("id, name, slug, status, features")
      .eq("is_active", true).order("sort_order")
      .then(({ data }) => setProducts(data ?? []));
    // Shops per plan, by each shop's latest subscription.
    supabase.from("subscriptions").select("business_id, plan_id, created_at")
      .order("created_at", { ascending: false }).limit(5000)
      .then(({ data }) => {
        const seen = new Set<string>();
        const counts: Record<string, number> = {};
        for (const s of data ?? []) {
          if (seen.has(s.business_id)) continue;
          seen.add(s.business_id);
          if (s.plan_id) counts[s.plan_id] = (counts[s.plan_id] ?? 0) + 1;
        }
        setShops(counts);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  const defaultProduct = () => (products.find((x) => x.slug === "dukania") ?? products[0])?.id ?? "";

  function startEdit(p: any | null) {
    setFormError(null);
    setForm({
      id: p?.id ?? null,
      name: p?.name ?? "",
      description: p?.description ?? "",
      highlights: Array.isArray(p?.highlights) ? p.highlights.join("\n") : "",
      software_id: p?.software_id ?? defaultProduct(),
      monthly_price: p ? str(Number(p.monthly_price) || "") : "",
      yearly_price: p ? str(Number(p.yearly_price) || "") : "",
      user_limit: str(p?.user_limit),
      product_limit: str(p?.product_limit),
      invoice_limit: str(p?.invoice_limit),
      included: Array.isArray(p?.included_features) ? p.included_features : [],
      sort_order: str(p?.sort_order ?? (plans?.length ?? 0) + 1),
      is_custom: Boolean(p?.is_custom),
      is_trial: Boolean(p?.is_trial),
      is_recommended: Boolean(p?.is_recommended),
      notes: p?.notes ?? "",
    });
  }

  const set = <K extends keyof Form>(key: K, value: Form[K]) =>
    setForm((f) => (f ? { ...f, [key]: value } : f));

  const productFeatures: Feature[] = (() => {
    const list = products.find((p) => p.id === form?.software_id)?.features;
    return Array.isArray(list) ? list : [];
  })();
  const highlightLines = (form?.highlights ?? "").split("\n").map((l) => l.trim()).filter(Boolean);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    setFormError(null);
    if (!form.name.trim()) return setFormError("Give the plan a name");
    const valid = new Set(productFeatures.map((f) => f.key));
    setBusy(true);
    const { error } = await supabase.rpc("admin_save_plan", {
      p_id: form.id,
      p: {
        name: form.name.trim(),
        description: form.description.trim(),
        highlights: highlightLines,
        software_id: form.software_id || null,
        monthly_price: Number(form.monthly_price) || 0,
        yearly_price: Number(form.yearly_price) || 0,
        user_limit: numOrNull(form.user_limit),
        product_limit: numOrNull(form.product_limit),
        invoice_limit: numOrNull(form.invoice_limit),
        included_features: form.included.filter((k) => valid.has(k)),
        sort_order: Number(form.sort_order) || 0,
        is_custom: form.is_custom,
        is_trial: form.is_trial,
        is_recommended: form.is_recommended,
        notes: form.notes,
      },
    });
    setBusy(false);
    if (error) {
      return setFormError(
        error.message.includes("admin_save_plan") ? "Migration 0055 isn't applied to this database yet." : error.message,
      );
    }
    setNotice({
      ok: true,
      text: form.id ? `${form.name.trim()} saved — shops on it see the change the next time they open the app.` : `${form.name.trim()} created.`,
    });
    setForm(null);
    setRefresh((n) => n + 1);
  }

  async function toggleActive(p: any) {
    const { error } = await supabase.rpc("admin_set_plan_active", { p_id: p.id, p_active: !p.is_active });
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: p.is_active ? `${p.name} is hidden — shops on it keep it, but it's no longer offered.` : `${p.name} is offered again.` });
    setRefresh((n) => n + 1);
  }

  async function remove(p: any) {
    if (!window.confirm(`Delete the plan "${p.name}"? This can't be undone.`)) return;
    const { error } = await supabase.rpc("admin_delete_plan", { p_id: p.id });
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: `${p.name} deleted.` });
    setRefresh((n) => n + 1);
  }

  if (!plans) return <Spinner />;

  // Before migration 0055 there is no trial mark to warn about.
  const hasTrial = plans.some((p) => p.is_trial) || !plans.some((p) => "is_trial" in p);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">Plans</h1>
          <p className="text-sm text-zinc-500">
            The app shows a plan&apos;s name and details, never its price. Prices stay here — you tell each shop what it pays.
          </p>
        </div>
        <Button onClick={() => startEdit(null)}>+ New plan</Button>
      </div>

      <Notice notice={notice} />
      {!hasTrial && (
        <Notice notice={{ ok: false, text: "No plan is marked as the trial plan, so new shops start with no plan (owner login only). Edit a plan and tick “New shops start on this plan”." }} />
      )}

      <Card>
        <ul className="divide-y divide-zinc-100">
          {plans.map((p) => {
            const count = shops[p.id] ?? 0;
            const features = Array.isArray(p.included_features) ? p.included_features.length : 0;
            return (
              <li key={p.id} className={`flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between ${p.is_active ? "" : "opacity-60"}`}>
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-semibold text-ink">{p.name}</span>
                    {p.is_trial && <Badge color="blue">trial plan</Badge>}
                    {p.is_recommended && <Badge color="purple">recommended</Badge>}
                    {p.is_custom && <Badge color="orange">custom</Badge>}
                    {!p.is_active && <Badge>hidden</Badge>}
                  </div>
                  {p.description && <p className="text-sm text-zinc-600">{p.description}</p>}
                  <p className="mt-1 text-xs text-zinc-500">
                    {limitsText(p).join(" · ")} · {features === 0 ? "all features" : `${features} feature${features === 1 ? "" : "s"}`}
                  </p>
                </div>
                <div className="flex shrink-0 flex-wrap items-center gap-x-5 gap-y-2 text-sm">
                  <span className="tabular-nums text-zinc-700">
                    {Number(p.monthly_price) > 0 ? `${inr(p.monthly_price)}/month` : "—"}
                    {" · "}
                    {Number(p.yearly_price) > 0 ? `${inr(p.yearly_price)}/year` : "—"}
                  </span>
                  <Link href="/clients" className="text-zinc-500 hover:underline">
                    {count} shop{count === 1 ? "" : "s"}
                  </Link>
                  <span className="space-x-3">
                    <button className="font-medium text-brand hover:underline" onClick={() => startEdit(p)}>Edit</button>
                    <button className="font-medium text-zinc-500 hover:underline" onClick={() => toggleActive(p)}>
                      {p.is_active ? "Hide" : "Show"}
                    </button>
                    {count === 0 && !p.is_trial && (
                      <button className="font-medium text-red-600 hover:underline" onClick={() => remove(p)}>Delete</button>
                    )}
                  </span>
                </div>
              </li>
            );
          })}
          {plans.length === 0 && <li className="px-5 py-10 text-center text-sm text-zinc-500">No plans yet.</li>}
        </ul>
      </Card>

      {form && (
        <Modal title={form.id ? `Edit plan — ${form.name}` : "New plan"} onClose={() => setForm(null)} wide>
          <form onSubmit={save} className="space-y-5">
            <Section title="Shown in the app">
              <div>
                <Label>Plan name *</Label>
                <Input value={form.name} onChange={(e) => set("name", e.target.value)} maxLength={40} placeholder="e.g. Basic" />
              </div>
              <div>
                <Label>Short description</Label>
                <Input value={form.description} onChange={(e) => set("description", e.target.value)} placeholder="e.g. Billing and stock for one counter" />
              </div>
              <div>
                <Label>Highlights — one per line (up to 8)</Label>
                <textarea
                  value={form.highlights}
                  onChange={(e) => set("highlights", e.target.value)}
                  rows={3}
                  placeholder={"e.g. Works on phone and computer\nWhatsApp support"}
                  className="w-full rounded-xl border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10"
                />
              </div>
            </Section>

            <Section title="Price — only you see this">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div>
                  <Label>Monthly price ₹</Label>
                  <Input type="number" min={0} step="0.01" value={form.monthly_price} onChange={(e) => set("monthly_price", e.target.value)} placeholder="0" />
                </div>
                <div>
                  <Label>Yearly price ₹</Label>
                  <Input type="number" min={0} step="0.01" value={form.yearly_price} onChange={(e) => set("yearly_price", e.target.value)} placeholder="0" />
                </div>
              </div>
              <p className="text-xs text-zinc-500">Used to fill in the amount when you renew a shop. You can change the amount for any shop at that moment.</p>
            </Section>

            <Section title="Limits — leave empty for unlimited">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div>
                  <Label>Logins (owner + staff)</Label>
                  <Input type="number" min={1} value={form.user_limit} onChange={(e) => set("user_limit", e.target.value)} placeholder="Unlimited" />
                </div>
                <div>
                  <Label>Products</Label>
                  <Input type="number" min={1} value={form.product_limit} onChange={(e) => set("product_limit", e.target.value)} placeholder="Unlimited" />
                </div>
                <div>
                  <Label>Bills a month</Label>
                  <Input type="number" min={1} value={form.invoice_limit} onChange={(e) => set("invoice_limit", e.target.value)} placeholder="Unlimited" />
                </div>
              </div>
            </Section>

            <Section title="Features">
              {products.length > 1 && (
                <div>
                  <Label>Product</Label>
                  <Select value={form.software_id} onChange={(e) => setForm({ ...form, software_id: e.target.value, included: [] })}>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>{p.name}{p.status !== "live" ? " (coming soon)" : ""}</option>
                    ))}
                  </Select>
                </div>
              )}
              {productFeatures.length === 0 ? (
                <p className="text-sm text-zinc-500">
                  This product has no features listed yet. Add them on the{" "}
                  <Link href="/products" className="text-brand hover:underline">Products</Link> page.
                </p>
              ) : (
                <>
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <p className="text-xs text-zinc-500">
                      {form.included.length === 0 ? "Nothing ticked = everything is included." : `${form.included.length} of ${productFeatures.length} included — the rest are switched off in the app.`}
                    </p>
                    <span className="space-x-3 text-xs font-semibold">
                      <button type="button" className="text-brand hover:underline" onClick={() => set("included", productFeatures.map((f) => f.key))}>Tick all</button>
                      <button type="button" className="text-zinc-500 hover:underline" onClick={() => set("included", [])}>Clear</button>
                    </span>
                  </div>
                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                    {productFeatures.map((f) => (
                      <label key={f.key} className="flex items-center gap-2 rounded-lg border border-zinc-200 px-3 py-2 text-sm hover:bg-zinc-50">
                        <input
                          type="checkbox"
                          checked={form.included.includes(f.key)}
                          onChange={() => set("included", form.included.includes(f.key) ? form.included.filter((k) => k !== f.key) : [...form.included, f.key])}
                        />
                        {f.label}
                      </label>
                    ))}
                  </div>
                </>
              )}
            </Section>

            <Section title="Options">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <div>
                  <Label>Order in the app</Label>
                  <Input type="number" value={form.sort_order} onChange={(e) => set("sort_order", e.target.value)} />
                </div>
              </div>
              <Check checked={form.is_recommended} onChange={(v) => set("is_recommended", v)} label="Recommended" hint="Marked “Recommended” in the app." />
              <Check checked={form.is_custom} onChange={(v) => set("is_custom", v)} label="Custom plan" hint="Made for one client — not offered to other shops in the app." />
              <Check checked={form.is_trial} onChange={(v) => set("is_trial", v)} label="New shops start on this plan" hint="The free trial. Only one plan can have this; ticking it here moves it from the other plan." />
              <div>
                <Label>Private notes — only you see these</Label>
                <Input value={form.notes} onChange={(e) => set("notes", e.target.value)} />
              </div>
            </Section>

            <div className="rounded-xl bg-zinc-50 p-4">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-zinc-500">How shops see it in the app</p>
              <div className="rounded-xl border border-zinc-200 bg-white p-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-base font-bold text-ink">{form.name.trim() || "Plan name"}</span>
                  {form.is_recommended && <Badge color="purple">recommended</Badge>}
                </div>
                {form.description.trim() && <p className="text-sm text-zinc-600">{form.description.trim()}</p>}
                <p className="mt-2 text-xs font-medium text-zinc-600">
                  {limitsText({ user_limit: numOrNull(form.user_limit), product_limit: numOrNull(form.product_limit), invoice_limit: numOrNull(form.invoice_limit) }).join(" · ")}
                </p>
                {highlightLines.length > 0 && (
                  <ul className="mt-2 space-y-0.5 text-sm font-medium text-ink">
                    {highlightLines.map((h, i) => <li key={i}>★ {h}</li>)}
                  </ul>
                )}
                <p className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs">
                  {productFeatures.map((f) => {
                    const on = form.included.length === 0 || form.included.includes(f.key);
                    return (
                      <span key={f.key} className={on ? "text-emerald-700" : "text-zinc-400 line-through"}>
                        {on ? "✓ " : ""}{f.label}
                      </span>
                    );
                  })}
                </p>
              </div>
              {(form.is_custom || form.is_trial) && (
                <p className="mt-2 text-xs text-zinc-500">
                  {form.is_trial ? "The trial plan" : "A custom plan"} isn&apos;t in the list of plans a shop can ask for; a shop on it sees it as its own plan.
                </p>
              )}
            </div>

            {formError && <p className="text-sm font-medium text-red-600">{formError}</p>}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setForm(null)}>Cancel</Button>
              <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save plan"}</Button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-3">
      <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">{title}</p>
      {children}
    </div>
  );
}

function Check({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint: string }) {
  return (
    <label className="flex items-start gap-2.5 text-sm">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} className="mt-1" />
      <span>
        <span className="font-semibold text-ink">{label}</span>
        <span className="block text-xs text-zinc-500">{hint}</span>
      </span>
    </label>
  );
}
