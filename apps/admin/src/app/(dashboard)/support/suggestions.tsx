"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { dateStr } from "@/lib/format";
import { SUGGESTION_STATUSES, suggestionStatusOf } from "@/lib/support";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Editing = { id: string | null; title: string; details: string; status: string; note: string; was: string; shops: string[] };

/** Shops that asked for this (one vote per shop, however many requests). */
const shopsOf = (s: any): string[] =>
  Array.from(new Set((s.support_tickets ?? []).map((t: any) => t.businesses?.name ?? "A shop")));

/**
 * The suggestions board (migration 0099): every idea the shops sent, with
 * one vote per shop. Marking one done tells each of those shops in the app.
 */
export function SuggestionsBoard() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [filter, setFilter] = useState<string>("open");
  const [editing, setEditing] = useState<Editing | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase
      .from("suggestions")
      .select("*, support_tickets(id, business_id, businesses(name))")
      .order("created_at", { ascending: false })
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setRows(data ?? []);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  async function save() {
    if (!editing) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("admin_save_suggestion", {
      p_id: editing.id, p_title: editing.title, p_details: editing.details, p_status: editing.status, p_note: editing.note,
    });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: error.message });
    const told: string[] = (data as any)?.told ?? [];
    // Each shop told in its request also gets a notification on its phones.
    for (const id of told) supabase.functions.invoke("support-push", { body: { ticket_id: id } }).catch(() => {});
    setNotice({
      ok: true,
      text: told.length ? `Saved. ${told.length} request${told.length === 1 ? "" : "s"} told that it's done.` : "Saved.",
    });
    setEditing(null);
    setRefresh((n) => n + 1);
  }

  if (!rows) return <Spinner />;

  const shown = rows
    .filter((s) => (filter === "open" ? !["done", "declined"].includes(s.status) : filter === "all" || s.status === filter))
    .sort((a, b) => shopsOf(b).length - shopsOf(a).length);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">Suggestions board</h1>
          <p className="text-sm text-zinc-500">
            What the shops are asking for, most wanted first. Put a request here from its Support window.
          </p>
        </div>
        <Button onClick={() => setEditing({ id: null, title: "", details: "", status: "new", note: "", was: "new", shops: [] })}>
          New suggestion
        </Button>
      </div>
      <Notice notice={notice} />
      <div className="flex flex-wrap gap-2">
        {[["open", "Open"], ...SUGGESTION_STATUSES.map((s) => [s.key, s.label]), ["all", "All"]].map(([key, label]) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            aria-pressed={filter === key}
            className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${filter === key ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}
          >
            {label}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 gap-3">
        {shown.map((s) => {
          const shops = shopsOf(s);
          const st = suggestionStatusOf(s.status);
          return (
            <Card key={s.id}>
              <button
                onClick={() => setEditing({ id: s.id, title: s.title, details: s.details, status: s.status, note: s.done_note, was: s.status, shops })}
                className="w-full text-left"
              >
                <CardBody className="flex items-start gap-4">
                  <div className="grid w-14 shrink-0 place-items-center rounded-xl bg-violet-50 py-2 text-violet-700">
                    <span className="text-xl font-extrabold leading-6">{shops.length}</span>
                    <span className="text-[10px] font-semibold uppercase">shop{shops.length === 1 ? "" : "s"}</span>
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-bold text-ink">{s.title}</p>
                      <Badge color={st.color}>{st.label}</Badge>
                    </div>
                    {s.details && <p className="mt-0.5 line-clamp-2 text-sm text-zinc-600">{s.details}</p>}
                    <p className="mt-1 truncate text-xs text-zinc-400">
                      {shops.length ? shops.join(", ") : "No shop yet"} · since {dateStr(s.created_at)}
                      {s.done_at ? ` · done ${dateStr(s.done_at)}` : ""}
                    </p>
                  </div>
                </CardBody>
              </button>
            </Card>
          );
        })}
        {shown.length === 0 && (
          <Card><CardBody><p className="text-center text-sm text-zinc-500">Nothing here.</p></CardBody></Card>
        )}
      </div>

      {editing && (
        <Modal title={editing.id ? editing.title || "Suggestion" : "New suggestion"} onClose={() => setEditing(null)}>
          <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
            <div>
              <Label>Title</Label>
              <Input required value={editing.title} onChange={(e) => setEditing({ ...editing, title: e.target.value })} />
            </div>
            <div>
              <Label>Details</Label>
              <textarea
                rows={3}
                value={editing.details}
                onChange={(e) => setEditing({ ...editing, details: e.target.value })}
                className="w-full rounded-xl border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10"
              />
            </div>
            <div>
              <Label>Status</Label>
              <Select value={editing.status} onChange={(e) => setEditing({ ...editing, status: e.target.value })}>
                {SUGGESTION_STATUSES.map((s) => <option key={s.key} value={s.key}>{s.label}</option>)}
              </Select>
            </div>
            {editing.status === "done" && (
              <div>
                <Label>A line for the shops (optional)</Label>
                <Input
                  value={editing.note}
                  onChange={(e) => setEditing({ ...editing, note: e.target.value })}
                  placeholder="e.g. Turn it on in Settings → Display."
                />
                {editing.was !== "done" && editing.shops.length > 0 && (
                  <p className="mt-2 rounded-xl bg-emerald-50 px-3 py-2 text-xs text-emerald-800">
                    On save, {editing.shops.length} shop{editing.shops.length === 1 ? "" : "s"} ({editing.shops.join(", ")}) get
                    &quot;your suggestion is now in Dukania&quot; in their request, and it&apos;s marked resolved.
                  </p>
                )}
              </div>
            )}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit" disabled={busy || !editing.title.trim()}>{busy ? "Saving…" : "Save"}</Button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
