"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { memberName, useTeam } from "@/components/me";
import { dateStr, dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Health levels from admin_shop_health() (migration 0102). */
export const LEVELS = {
  healthy: { label: "Healthy", color: "green", bar: "bg-emerald-500" },
  watch: { label: "Needs attention", color: "orange", bar: "bg-amber-400" },
  risk: { label: "At risk", color: "red", bar: "bg-red-500" },
} as const;
export const levelOf = (l: string) => LEVELS[l as keyof typeof LEVELS] ?? LEVELS.watch;

export const CONTACT_KINDS: [string, string][] = [
  ["call", "Phone call"],
  ["whatsapp", "WhatsApp"],
  ["visit", "Shop visit"],
  ["training", "Training"],
  ["note", "Note"],
];
export const OUTCOMES: [string, string][] = [
  ["", "—"],
  ["happy", "Happy"],
  ["neutral", "Okay"],
  ["unhappy", "Unhappy"],
  ["no_answer", "No answer"],
];
export const outcomeLabel = (o: string) => OUTCOMES.find(([k]) => k === o)?.[1] ?? o;

/** A score bar, 0–100. */
export function ScoreBar({ score, level }: { score: number; level: string }) {
  return (
    <span className="flex items-center gap-2">
      <span className="h-2 w-16 rounded-full bg-zinc-100">
        <span className={`block h-2 rounded-full ${levelOf(level).bar}`} style={{ width: `${score}%` }} />
      </span>
      <b className="tabular-nums text-ink">{score}</b>
    </span>
  );
}

/** Log a call, visit or WhatsApp with a shop, with an optional follow-up date. */
export function LogContactDialog({ shop, onClose, onSaved }: {
  shop: { id: string; name: string }; onClose: () => void; onSaved: () => void;
}) {
  const [kind, setKind] = useState("call");
  const [outcome, setOutcome] = useState("");
  const [note, setNote] = useState("");
  const [followUp, setFollowUp] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setBusy(true);
    const { error } = await createClient().rpc("admin_log_contact", {
      p_business: shop.id,
      p: { kind, outcome, note, follow_up_date: followUp || null },
    });
    setBusy(false);
    if (error) return setError(error.message);
    onSaved();
  }

  return (
    <Modal title={`Contact — ${shop.name}`} onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label>How</Label>
            <Select value={kind} onChange={(e) => setKind(e.target.value)}>
              {CONTACT_KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </Select>
          </div>
          <div>
            <Label>How did it go?</Label>
            <Select value={outcome} onChange={(e) => setOutcome(e.target.value)}>
              {OUTCOMES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </Select>
          </div>
        </div>
        <div>
          <Label>What was said</Label>
          <textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)}
            placeholder="e.g. Showed how to print on A5; wants barcode labels"
            className="w-full rounded-md border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10" />
        </div>
        <div className="max-w-xs">
          <Label>Follow up on (optional)</Label>
          <Input type="date" value={followUp} onChange={(e) => setFollowUp(e.target.value)} />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={busy}>{busy ? "Saving…" : "Save"}</Button>
        </div>
      </form>
    </Modal>
  );
}

/** On a client's page: health score, why, onboarding steps and the call log. */
export function ShopSuccessCard({ businessId, name }: { businessId: string; name: string }) {
  const [health, setHealth] = useState<any>(null);
  const [contacts, setContacts] = useState<any[]>([]);
  const [logging, setLogging] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const team = useTeam();

  const load = useCallback(() => {
    const db = createClient();
    db.rpc("admin_shop_health", { p_business: businessId }).then(({ data, error }) => {
      if (error) return setNotice({ ok: false, text: error.message.includes("admin_shop_health") ? "Migration 0102 isn't applied to this database yet." : error.message });
      setHealth((data as any[])?.[0] ?? null);
    });
    db.from("client_contacts").select("*").eq("business_id", businessId).order("created_at", { ascending: false }).limit(20)
      .then(({ data }) => setContacts(data ?? []));
  }, [businessId]);

  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => { if (active) load(); });
    return () => { active = false; };
  }, [load]);

  const steps: any[] = health?.steps ?? [];
  const done = steps.filter((s) => s.done).length;

  return (
    <Card>
      <CardBody className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <h2 className="text-sm font-semibold text-zinc-700">Health</h2>
            {health && <ScoreBar score={health.score} level={health.level} />}
            {health && <Badge color={levelOf(health.level).color}>{levelOf(health.level).label}</Badge>}
          </div>
          <Button variant="outline" onClick={() => setLogging(true)}>Log a call or visit</Button>
        </div>
        <Notice notice={notice} />
        {health && (
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <div>
              <p className="mb-1 text-[13px] font-medium text-zinc-500">Why</p>
              {health.reasons.length === 0 ? (
                <p className="text-sm text-emerald-700">Nothing to worry about.</p>
              ) : (
                <ul className="list-disc space-y-0.5 pl-5 text-sm text-zinc-700">
                  {health.reasons.map((r: string) => <li key={r}>{r}</li>)}
                </ul>
              )}
              <p className="mt-2 text-xs text-zinc-500">
                {health.bills_30d} bills in 30 days · {health.products} products · {health.staff} staff
                {health.nps !== null ? ` · would recommend ${health.nps}/10` : ""}
              </p>
            </div>
            <div>
              <p className="mb-1 text-[13px] font-medium text-zinc-500">Getting started ({done}/{steps.length})</p>
              <ul className="space-y-0.5 text-sm">
                {steps.map((s) => (
                  <li key={s.key} className={s.done ? "text-zinc-500" : "font-medium text-ink"}>
                    {s.done ? "✓" : "○"} {s.label}
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <p className="mb-1 text-[13px] font-medium text-zinc-500">Calls and visits</p>
              {contacts.length === 0 ? (
                <p className="text-sm text-zinc-500">None logged yet.</p>
              ) : (
                <ul className="space-y-2 text-sm">
                  {contacts.slice(0, 5).map((c) => (
                    <li key={c.id}>
                      <span className="text-xs text-zinc-500">
                        {dateTimeStr(c.created_at)}{memberName(team, c.created_by) ? ` · ${memberName(team, c.created_by)}` : ""}
                      </span>
                      <span className="block text-zinc-700">
                        {CONTACT_KINDS.find(([k]) => k === c.kind)?.[1]}{c.outcome ? ` — ${outcomeLabel(c.outcome)}` : ""}
                        {c.note ? `: ${c.note}` : ""}
                      </span>
                      {c.follow_up_date && !c.follow_up_done && (
                        <span className="text-xs font-semibold text-amber-700">Follow up {dateStr(c.follow_up_date)}</span>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        )}
      </CardBody>
      {logging && (
        <LogContactDialog
          shop={{ id: businessId, name }}
          onClose={() => setLogging(false)}
          onSaved={() => { setLogging(false); load(); }}
        />
      )}
    </Card>
  );
}
