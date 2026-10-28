"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Input, Label, Select, Spinner, Table, Toggle } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Editing = { code: string; kind: string; value: string; max_uses: string; valid_until: string; plan_ids: string[]; note: string };

/**
 * Promo codes for plans (migration 0101): an amount or a % off the website
 * price. The team enters the code when recording a sale; the app shows no
 * prices, so codes go out on WhatsApp, posts and ads.
 */
export function PromoCodes() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [plans, setPlans] = useState<any[]>([]);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    const db = createClient();
    db.from("promo_codes").select("*, promo_redemptions(discount)").order("created_at", { ascending: false })
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setRows(data ?? []);
      });
    db.from("plans").select("id, name").gt("list_price", 0).order("sort_order").then(({ data }) => setPlans(data ?? []));
  }, [refresh]);

  async function save() {
    if (!editing) return;
    const { error } = await createClient().from("promo_codes").insert({
      code: editing.code.trim().toUpperCase(),
      kind: editing.kind,
      value: Number(editing.value),
      max_uses: editing.max_uses ? Number(editing.max_uses) : null,
      valid_until: editing.valid_until || null,
      plan_ids: editing.plan_ids.length ? editing.plan_ids : null,
      note: editing.note.trim(),
    });
    if (error) {
      return setNotice({ ok: false, text: error.message.includes("promo_codes_code_key") ? "That code already exists." : error.message });
    }
    setNotice({ ok: true, text: `${editing.code.toUpperCase()} is ready. Enter it when you record a sale.` });
    setEditing(null);
    setRefresh((n) => n + 1);
  }

  async function setActive(p: any, active: boolean) {
    const { error } = await createClient().from("promo_codes").update({ active }).eq("id", p.id);
    if (error) return setNotice({ ok: false, text: error.message });
    setRefresh((n) => n + 1);
  }

  if (!rows) return <Spinner />;
  const today = new Date().toISOString().slice(0, 10);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-zinc-600">Off the website price. Used when you record a sale (Clients → Record a sale).</p>
        <Button onClick={() => setEditing({ code: "", kind: "amount", value: "", max_uses: "", valid_until: "", plan_ids: [], note: "" })}>
          New promo code
        </Button>
      </div>
      <Notice notice={notice} />
      <Card>
        <Table headers={["Code", "Off", "For", "Used", "Ends", "Given away", "On"]}>
          {rows.map((p) => {
            const ended = (p.valid_until && p.valid_until < today) || (p.max_uses && p.used_count >= p.max_uses);
            const given = (p.promo_redemptions ?? []).reduce((s: number, r: any) => s + Number(r.discount), 0);
            return (
              <tr key={p.id}>
                <td className="px-4 py-3">
                  <span className="font-mono font-bold text-ink">{p.code}</span>
                  {p.note && <span className="block text-xs text-zinc-500">{p.note}</span>}
                </td>
                <td className="px-4 py-3">{p.kind === "amount" ? inr(p.value) : `${Number(p.value)}%`}</td>
                <td className="px-4 py-3 text-xs">
                  {p.plan_ids ? p.plan_ids.map((id: string) => plans.find((x) => x.id === id)?.name ?? "?").join(", ") : "Every plan"}
                </td>
                <td className="px-4 py-3 tabular-nums">{p.used_count}{p.max_uses ? ` / ${p.max_uses}` : ""}</td>
                <td className="px-4 py-3">{p.valid_until ? dateStr(p.valid_until) : "—"}</td>
                <td className="px-4 py-3 tabular-nums">{inr(given)}</td>
                <td className="px-4 py-3">
                  {ended ? <Badge color="zinc">Finished</Badge> : <Toggle checked={p.active} onChange={(v) => setActive(p, v)} label={p.active ? "On" : "Off"} />}
                </td>
              </tr>
            );
          })}
          {rows.length === 0 && (
            <tr><td colSpan={7} className="px-4 py-10 text-center text-zinc-500">No promo codes yet.</td></tr>
          )}
        </Table>
      </Card>

      {editing && (
        <Modal title="New promo code" onClose={() => setEditing(null)}>
          <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
            <div>
              <Label>Code (3–20 letters, numbers, - or _)</Label>
              <Input required value={editing.code} pattern="[A-Za-z0-9_-]{3,20}"
                onChange={(e) => setEditing({ ...editing, code: e.target.value.toUpperCase() })} placeholder="DIWALI500" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <Label>Off</Label>
                <Select value={editing.kind} onChange={(e) => setEditing({ ...editing, kind: e.target.value })}>
                  <option value="amount">₹ amount</option>
                  <option value="percent">% of the price</option>
                </Select>
              </div>
              <div>
                <Label>{editing.kind === "amount" ? "₹" : "%"}</Label>
                <Input required type="number" min={1} max={editing.kind === "percent" ? 100 : undefined} value={editing.value}
                  onChange={(e) => setEditing({ ...editing, value: e.target.value })} />
              </div>
              <div>
                <Label>Uses (empty = no limit)</Label>
                <Input type="number" min={1} value={editing.max_uses} onChange={(e) => setEditing({ ...editing, max_uses: e.target.value })} />
              </div>
              <div>
                <Label>Last day (optional)</Label>
                <Input type="date" value={editing.valid_until} onChange={(e) => setEditing({ ...editing, valid_until: e.target.value })} />
              </div>
            </div>
            <div>
              <Label>For the plans (none ticked = every plan)</Label>
              <div className="flex flex-wrap gap-3 text-sm">
                {plans.map((p) => (
                  <label key={p.id} className="flex items-center gap-2">
                    <input type="checkbox" checked={editing.plan_ids.includes(p.id)}
                      onChange={(e) => setEditing({
                        ...editing,
                        plan_ids: e.target.checked ? [...editing.plan_ids, p.id] : editing.plan_ids.filter((x) => x !== p.id),
                      })} />
                    {p.name}
                  </label>
                ))}
              </div>
            </div>
            <div>
              <Label>Note (only the team sees it)</Label>
              <Input value={editing.note} onChange={(e) => setEditing({ ...editing, note: e.target.value })} placeholder="e.g. Diwali Facebook ad" />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit" disabled={!editing.code.trim() || !editing.value}>Create</Button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
