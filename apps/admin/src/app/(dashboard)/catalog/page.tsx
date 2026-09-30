"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Input, Label, Select, Spinner } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { BUSINESS_TYPES, businessTypeLabel } from "@/lib/business-types";

/* eslint-disable @typescript-eslint/no-explicit-any */

const GST_RATES = ["0", "3", "5", "12", "18", "28"];

const FILTERS = [
  ["", "All", "all"],
  ["pending", "Waiting for you", "pending"],
  ["published", "Offered to shops", "published"],
  ["hidden", "Hidden", "hidden"],
] as const;

type Form = {
  id: string | null;
  name: string;
  brand: string;
  category: string;
  unit_name: string;
  unit_short: string;
  allow_decimal: boolean;
  hsn_code: string;
  gst_rate: string;
  barcode: string;
  business_type: string;
  description: string;
  secondary_unit_name: string;
  conversion_factor: string;
  track_serial: boolean;
  track_pieces: boolean;
  warranty_months: string;
};

const str = (v: unknown) => (v === null || v === undefined ? "" : String(v));
const pct = (v: unknown) => String(Number(v ?? 0));

const notApplied = (message: string) =>
  /get_admin_master_products|admin_save_master_product|admin_merge_master_products|admin_set_/.test(message)
    ? "Migration 0057 isn't applied to this database yet."
    : message;

/**
 * The master product list (migration 0057): every product a shop adds joins
 * it with its details and without its prices; other shops pick from it
 * while adding a product. Here SOFTRAXA adds, corrects, approves, hides and
 * merges entries. Every change is logged.
 */
export default function CatalogPage() {
  const supabase = createClient();
  const [data, setData] = useState<any | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [typed, setTyped] = useState("");
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<string>("");
  const [form, setForm] = useState<Form | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [merging, setMerging] = useState<any | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase.rpc("get_admin_master_products", { p_search: search, p_status: status, p_limit: 300 })
      .then(({ data, error }) => {
        if (error) setError(notApplied(error.message));
        else setData(data);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, status, refresh]);

  function startEdit(m: any | null) {
    setFormError(null);
    setForm({
      id: m?.id ?? null,
      name: m?.name ?? "",
      brand: m?.brand ?? "",
      category: m?.category ?? "",
      unit_name: m?.unit_name ?? "Piece",
      unit_short: m?.unit_short ?? "pcs",
      allow_decimal: Boolean(m?.allow_decimal),
      hsn_code: m?.hsn_code ?? "",
      gst_rate: m ? pct(m.gst_rate) : "18",
      barcode: m?.barcode ?? "",
      business_type: m?.business_type ?? "",
      description: m?.description ?? "",
      secondary_unit_name: m?.secondary_unit_name ?? "",
      conversion_factor: str(m?.conversion_factor),
      track_serial: Boolean(m?.track_serial),
      track_pieces: Boolean(m?.track_pieces),
      warranty_months: str(m?.warranty_months),
    });
  }

  const set = <K extends keyof Form>(key: K, value: Form[K]) =>
    setForm((f) => (f ? { ...f, [key]: value } : f));

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    setFormError(null);
    if (form.name.trim().length < 3) return setFormError("Give the product a name (3 letters or more)");
    setBusy(true);
    const { id, ...fields } = form;
    const { error } = await supabase.rpc("admin_save_master_product", {
      p_id: id,
      p: {
        ...fields,
        gst_rate: Number(form.gst_rate) || 0,
        conversion_factor: form.conversion_factor.trim() === "" ? null : Number(form.conversion_factor),
        warranty_months: form.warranty_months.trim() === "" ? null : Number(form.warranty_months),
      },
    });
    setBusy(false);
    if (error) return setFormError(notApplied(error.message));
    setNotice({ ok: true, text: `${form.name.trim()} saved — shops can now pick it while adding a product.` });
    setForm(null);
    setRefresh((n) => n + 1);
  }

  async function setRowStatus(m: any, next: string) {
    const { error } = await supabase.rpc("admin_set_master_product_status", { p_id: m.id, p_status: next });
    setNotice(error
      ? { ok: false, text: notApplied(error.message) }
      : { ok: true, text: next === "hidden" ? `${m.name} is hidden — shops are no longer offered it.` : `${m.name} is offered to shops.` });
    setRefresh((n) => n + 1);
  }

  async function setAutoPublish(on: boolean) {
    const { error } = await supabase.rpc("admin_set_catalog_auto_publish", { p_on: on });
    setNotice(error
      ? { ok: false, text: notApplied(error.message) }
      : { ok: true, text: on ? "New products from shops are offered to other shops at once." : "New products from shops now wait here until you approve them." });
    setRefresh((n) => n + 1);
  }

  if (error) return <p className="text-red-600">{error}</p>;
  if (!data) return <Spinner />;

  const rows: any[] = data.rows ?? [];
  const counts = data.counts ?? {};
  const auto = data.auto_publish !== false;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">Master products</h1>
          <p className="max-w-2xl text-sm text-zinc-500">
            Every product a shop adds joins this list with its details, never its prices. The next shop picks it by
            name instead of typing everything again.
          </p>
        </div>
        <Button onClick={() => startEdit(null)}>+ Add product</Button>
      </div>

      <Notice notice={notice} />

      <Card>
        <div className="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-semibold text-ink">When a shop adds a new product</p>
            <p className="text-xs text-zinc-500">
              {auto ? "It is offered to other shops at once. You can hide or correct it here any time." : "It waits here. Other shops see it only after you approve it."}
            </p>
          </div>
          <div className="flex shrink-0 gap-2">
            {([[true, "Offer it at once"], [false, "I approve first"]] as const).map(([on, label]) => (
              <button
                key={label}
                onClick={() => auto !== on && setAutoPublish(on)}
                aria-pressed={auto === on}
                className={`rounded-xl border px-4 py-2 text-sm font-semibold ${auto === on ? "border-brand bg-brand-tint text-brand" : "border-zinc-200 text-zinc-600"}`}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      </Card>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-wrap gap-2">
          {FILTERS.map(([value, label, key]) => (
            <button
              key={key}
              onClick={() => setStatus(value)}
              aria-pressed={status === value}
              className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${status === value ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}
            >
              {label} ({counts[key] ?? 0})
            </button>
          ))}
        </div>
        <form
          className="flex gap-2"
          onSubmit={(e) => { e.preventDefault(); setSearch(typed.trim()); }}
        >
          <Input value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Name, brand or barcode" className="sm:w-64" />
          <Button type="submit" variant="outline">Search</Button>
        </form>
      </div>

      <Card>
        <ul className="divide-y divide-zinc-100">
          {rows.map((m) => (
            <li key={m.id} className={`flex flex-col gap-3 px-5 py-4 lg:flex-row lg:items-center lg:justify-between ${m.status === "hidden" ? "opacity-60" : ""}`}>
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold text-ink">{m.name}</span>
                  {m.status === "pending" && <Badge color="orange">waiting for you</Badge>}
                  {m.status === "hidden" && <Badge>hidden</Badge>}
                  {m.verified && <Badge color="green">checked</Badge>}
                </div>
                <p className="mt-0.5 text-xs text-zinc-500">
                  {[
                    m.brand, m.category,
                    m.unit_name && `${m.unit_name}${m.unit_short ? ` (${m.unit_short})` : ""}`,
                    m.hsn_code ? `HSN ${m.hsn_code}` : "no HSN",
                    `GST ${pct(m.gst_rate)}%`,
                    m.barcode && `barcode ${m.barcode}`,
                    m.business_type && businessTypeLabel(m.business_type),
                  ].filter(Boolean).join(" · ")}
                </p>
                <p className="text-xs text-zinc-400">
                  {m.source === "softraxa" ? "Added by you" : `Added by ${m.source_shop ?? "a shop"}`}
                  {" · "}
                  {Number(m.shops) === 0 ? "no shop has it" : `in ${m.shops} shop${Number(m.shops) === 1 ? "" : "s"}`}
                </p>
              </div>
              <div className="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-2 text-sm font-medium">
                {m.status === "pending" && (
                  <button className="text-emerald-700 hover:underline" onClick={() => setRowStatus(m, "published")}>Approve</button>
                )}
                <button className="text-brand hover:underline" onClick={() => startEdit(m)}>Edit</button>
                <button className="text-zinc-500 hover:underline" onClick={() => setMerging(m)}>Merge</button>
                {m.status === "hidden"
                  ? <button className="text-zinc-500 hover:underline" onClick={() => setRowStatus(m, "published")}>Show</button>
                  : <button className="text-zinc-500 hover:underline" onClick={() => setRowStatus(m, "hidden")}>Hide</button>}
              </div>
            </li>
          ))}
          {rows.length === 0 && (
            <li className="px-5 py-10 text-center text-sm text-zinc-500">
              {search || status ? "Nothing matches." : "The list is empty. It fills as shops add products — or add some yourself."}
            </li>
          )}
        </ul>
      </Card>
      {rows.length >= 300 && <p className="text-xs text-zinc-500">Showing the newest 300. Search to find older ones.</p>}

      {form && (
        <Modal title={form.id ? `Edit — ${form.name}` : "Add a product to the list"} onClose={() => setForm(null)} wide>
          <form onSubmit={save} className="space-y-4">
            <p className="rounded-xl bg-zinc-50 px-4 py-3 text-xs text-zinc-600">
              No prices here: each shop enters its own. What you save is marked as checked, and shops can no longer change it.
            </p>
            <div>
              <Label>Product name *</Label>
              <Input value={form.name} onChange={(e) => set("name", e.target.value)} placeholder="e.g. Samsung Galaxy A15 5G 8GB/128GB" />
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <Label>Brand</Label>
                <Input value={form.brand} onChange={(e) => set("brand", e.target.value)} />
              </div>
              <div>
                <Label>Category</Label>
                <Input value={form.category} onChange={(e) => set("category", e.target.value)} />
              </div>
              <div>
                <Label>Unit</Label>
                <Input value={form.unit_name} onChange={(e) => set("unit_name", e.target.value)} placeholder="Piece" />
              </div>
              <div>
                <Label>Unit short name</Label>
                <Input value={form.unit_short} onChange={(e) => set("unit_short", e.target.value)} placeholder="pcs" />
              </div>
              <div>
                <Label>HSN code</Label>
                <Input value={form.hsn_code} onChange={(e) => set("hsn_code", e.target.value.replace(/\D/g, ""))} maxLength={8} placeholder="4, 6 or 8 digits" className="font-mono" />
              </div>
              <div>
                <Label>GST %</Label>
                <Select value={form.gst_rate} onChange={(e) => set("gst_rate", e.target.value)}>
                  {(GST_RATES.includes(form.gst_rate) ? GST_RATES : [...GST_RATES, form.gst_rate]).map((r) => (
                    <option key={r} value={r}>{r}%</option>
                  ))}
                </Select>
              </div>
              <div>
                <Label>Barcode</Label>
                <Input value={form.barcode} onChange={(e) => set("barcode", e.target.value.trim())} className="font-mono" />
              </div>
              <div>
                <Label>Kind of shop (shown first to these shops)</Label>
                <Select value={form.business_type} onChange={(e) => set("business_type", e.target.value)}>
                  <option value="">Any shop</option>
                  {BUSINESS_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
                </Select>
              </div>
              <div>
                <Label>Bulk unit (optional)</Label>
                <Input value={form.secondary_unit_name} onChange={(e) => set("secondary_unit_name", e.target.value)} placeholder="e.g. Box, Bag, Rod" />
              </div>
              <div>
                <Label>1 bulk unit = how many units?</Label>
                <Input type="number" min={0} step="0.001" value={form.conversion_factor} onChange={(e) => set("conversion_factor", e.target.value)} />
              </div>
              <div>
                <Label>Warranty (months)</Label>
                <Input type="number" min={0} value={form.warranty_months} onChange={(e) => set("warranty_months", e.target.value)} />
              </div>
            </div>
            <div>
              <Label>Description (optional)</Label>
              <Input value={form.description} onChange={(e) => set("description", e.target.value)} />
            </div>
            <div className="space-y-2 text-sm">
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={form.allow_decimal} onChange={(e) => set("allow_decimal", e.target.checked)} />
                Sold in fractions (kg, metre, litre)
              </label>
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={form.track_serial} onChange={(e) => set("track_serial", e.target.checked)} />
                Track IMEI / serial numbers
              </label>
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={form.track_pieces} onChange={(e) => set("track_pieces", e.target.checked)} />
                Track cut pieces (rods, sheets, rolls)
              </label>
            </div>
            {formError && <p className="text-sm font-medium text-red-600">{formError}</p>}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setForm(null)}>Cancel</Button>
              <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save product"}</Button>
            </div>
          </form>
        </Modal>
      )}

      {merging && (
        <MergeDialog
          from={merging}
          onClose={() => setMerging(null)}
          onDone={(text) => {
            setMerging(null);
            setNotice({ ok: true, text });
            setRefresh((n) => n + 1);
          }}
        />
      )}
    </div>
  );
}

/** Two entries for the same product: move every shop's product to the one kept. */
function MergeDialog({ from, onClose, onDone }: { from: any; onClose: () => void; onDone: (text: string) => void }) {
  const supabase = createClient();
  const [typed, setTyped] = useState("");
  const [search, setSearch] = useState(String(from.name).split(" ").slice(0, 2).join(" "));
  const [rows, setRows] = useState<any[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    supabase.rpc("get_admin_master_products", { p_search: search, p_status: "", p_limit: 30 })
      .then(({ data }) => setRows(((data?.rows ?? []) as any[]).filter((r) => r.id !== from.id)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  async function merge(into: any) {
    if (!window.confirm(`Keep "${into.name}" and remove "${from.name}"? Shops that have "${from.name}" keep their product; it just points to the one you keep. This can't be undone.`)) return;
    setBusy(true);
    const { error } = await supabase.rpc("admin_merge_master_products", { p_from: from.id, p_into: into.id });
    setBusy(false);
    if (error) return setError(notApplied(error.message));
    onDone(`"${from.name}" was merged into "${into.name}".`);
  }

  return (
    <Modal title={`Merge “${from.name}” into…`} onClose={onClose}>
      <div className="space-y-4 text-sm">
        <p className="text-zinc-600">Choose the entry to keep. “{from.name}” is removed from the list.</p>
        <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); setSearch(typed.trim()); }}>
          <Input value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Search the list" />
          <Button type="submit" variant="outline">Search</Button>
        </form>
        {error && <p className="font-medium text-red-600">{error}</p>}
        {!rows ? <Spinner /> : (
          <ul className="divide-y divide-zinc-100 rounded-xl border border-zinc-200">
            {rows.map((r) => (
              <li key={r.id}>
                <button disabled={busy} onClick={() => merge(r)} className="flex w-full flex-col px-4 py-3 text-left hover:bg-zinc-50 disabled:opacity-50">
                  <span className="font-semibold text-ink">{r.name}</span>
                  <span className="text-xs text-zinc-500">
                    {[r.brand, r.category, r.hsn_code && `HSN ${r.hsn_code}`, `in ${r.shops} shop${Number(r.shops) === 1 ? "" : "s"}`].filter(Boolean).join(" · ")}
                  </span>
                </button>
              </li>
            ))}
            {rows.length === 0 && <li className="px-4 py-6 text-center text-zinc-500">Nothing found — try another search.</li>}
          </ul>
        )}
      </div>
    </Modal>
  );
}
