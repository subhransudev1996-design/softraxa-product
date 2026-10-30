"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner, StatCard } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr } from "@/lib/format";
import { PLATFORMS } from "./shared";

/* eslint-disable @typescript-eslint/no-explicit-any */

const STAGES = [
  ["found", "Found"],
  ["contacted", "Contacted"],
  ["talking", "Talking"],
  ["joined", "Joined"],
] as const;

type Draft = {
  id?: string; name: string; handle: string; platform: string; followers: string; niche: string; language: string;
  city: string; phone: string; deal_note: string; next_follow_up: string; note: string;
};

const blank: Draft = { name: "", handle: "", platform: "instagram", followers: "", niche: "", language: "", city: "", phone: "", deal_note: "", next_follow_up: "", note: "" };

const draftOf = (x: any): Draft => ({
  id: x.id, name: x.name, handle: x.handle, platform: x.platform, followers: x.followers == null ? "" : String(x.followers),
  niche: x.niche, language: x.language, city: x.city, phone: x.phone, deal_note: x.deal_note,
  next_follow_up: x.next_follow_up ?? "", note: x.note,
});

const today = () => new Date(Date.now() + 5.5 * 3600000).toISOString().slice(0, 10);
const shortCount = (n: number) => (n >= 100000 ? `${+(n / 100000).toFixed(1)}L` : n >= 1000 ? `${+(n / 1000).toFixed(1)}k` : String(n));

/** The influencers you are reaching out to (migration 0109), from first find to partner. */
export function Pipeline() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [joining, setJoining] = useState<any>(null);
  const [dropping, setDropping] = useState<any>(null);
  const [showDropped, setShowDropped] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const canEdit = useCan("marketing");

  useEffect(() => {
    createClient().from("partner_prospects").select("*").order("created_at", { ascending: false }).then(({ data, error }) => {
      if (error) setNotice({ ok: false, text: error.message.includes("partner_prospects") ? "Migration 0109 isn't applied to this database yet." : error.message });
      setRows(data ?? []);
    });
  }, [refresh]);

  if (!rows) return <Spinner />;
  const now = today();
  const open = rows.filter((x) => x.stage !== "joined" && x.stage !== "dropped");
  const due = open.filter((x) => x.next_follow_up && x.next_follow_up <= now);
  const dropped = rows.filter((x) => x.stage === "dropped");
  const reload = () => setRefresh((n) => n + 1);

  async function save(x: any, change: Record<string, unknown>) {
    const { error } = await createClient().rpc("admin_save_prospect", { p: { ...draftOf(x), ...change } });
    if (error) return setNotice({ ok: false, text: error.message });
    reload();
  }

  async function remove(x: any) {
    if (!window.confirm(`Delete ${x.name} from the pipeline?`)) return;
    const { error } = await createClient().rpc("admin_delete_prospect", { p_id: x.id });
    if (error) return setNotice({ ok: false, text: error.message });
    reload();
  }

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="In talks" value={open.length} />
        <StatCard label="Follow up today" value={due.length} hint={due.length ? due.map((x) => x.name).slice(0, 2).join(", ") : "Nothing due"} />
        <StatCard label="Joined" value={rows.filter((x) => x.stage === "joined").length} />
        <StatCard label="Dropped" value={dropped.length} />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-zinc-600">Note everyone you find or message. Make partner gives them a code and link.</p>
        {canEdit && <Button onClick={() => setDraft(blank)}>Add influencer</Button>}
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-4">
        {STAGES.map(([stage, label]) => {
          const cards = rows.filter((x) => x.stage === stage);
          return (
            <section key={stage} className="rounded-lg bg-zinc-100/70 p-3">
              <h2 className="mb-3 flex items-center justify-between px-1 text-sm font-semibold text-zinc-700">
                {label} <span className="tabular-nums text-zinc-500">{cards.length}</span>
              </h2>
              <div className="space-y-3">
                {cards.map((x) => (
                  <ProspectCard key={x.id} x={x} now={now} canEdit={canEdit}
                    onEdit={() => setDraft(draftOf(x))}
                    onStage={(s) => (s === "dropped" ? setDropping(x) : save(x, { stage: s }))}
                    onJoin={() => setJoining(x)}
                    onDelete={() => remove(x)} />
                ))}
                {cards.length === 0 && <p className="px-1 pb-2 text-xs text-zinc-500">Nobody here.</p>}
              </div>
            </section>
          );
        })}
      </div>

      {dropped.length > 0 && (
        <div>
          <Button variant="ghost" onClick={() => setShowDropped(!showDropped)}>{showDropped ? "Hide" : "Show"} dropped ({dropped.length})</Button>
          {showDropped && (
            <Card className="mt-2">
              <ul className="divide-y divide-zinc-100 text-sm">
                {dropped.map((x) => (
                  <li key={x.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
                    <span>
                      <b className="text-ink">{x.name}</b>{x.handle ? ` · ${x.handle}` : ""}
                      {x.drop_reason && <span className="block text-xs text-zinc-500">{x.drop_reason}</span>}
                    </span>
                    {canEdit && (
                      <span className="flex gap-2">
                        <Button variant="outline" onClick={() => save(x, { stage: "talking" })}>Back to Talking</Button>
                        <Button variant="ghost" onClick={() => remove(x)}>Delete</Button>
                      </span>
                    )}
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>
      )}

      {draft && <ProspectForm draft={draft} setDraft={setDraft} onClose={() => setDraft(null)} onDone={() => { setDraft(null); reload(); }} />}
      {joining && <JoinDialog prospect={joining} onClose={() => setJoining(null)} />}
      {dropping && (
        <DropDialog prospect={dropping} onClose={() => setDropping(null)}
          onDrop={(reason) => { save(dropping, { stage: "dropped", drop_reason: reason }); setDropping(null); }} />
      )}
    </div>
  );
}

function ProspectCard({ x, now, canEdit, onEdit, onStage, onJoin, onDelete }: {
  x: any; now: string; canEdit: boolean; onEdit: () => void; onStage: (s: string) => void; onJoin: () => void; onDelete: () => void;
}) {
  const overdue = x.next_follow_up && x.next_follow_up <= now;
  const about = [x.followers != null ? `${shortCount(Number(x.followers))} followers` : "", x.niche, x.language, x.city].filter(Boolean).join(" · ");
  const hello = `Namaste ${x.name}! I'm from Dukania, a billing and stock app for Indian shops. I'd love to work with you — shops get a discount with your code and you earn on each sale. Can we talk?`;

  return (
    <Card>
      <CardBody className="space-y-2 p-4 text-sm">
        {x.stage === "joined" && x.partner_id ? (
          <Link href={`/influencers/${x.partner_id}`} className="font-semibold text-ink hover:underline">{x.name}</Link>
        ) : (
          <button onClick={onEdit} disabled={!canEdit} className="text-left font-semibold text-ink hover:underline disabled:no-underline">{x.name}</button>
        )}
        {x.handle && <p className="break-all text-xs text-zinc-500">{x.handle}</p>}
        {about && <p className="text-xs text-zinc-600">{about}</p>}
        {x.deal_note && <p className="rounded-lg bg-zinc-50 px-2.5 py-1.5 text-xs text-zinc-700">{x.deal_note}</p>}
        {x.next_follow_up && (
          <p><Badge color={overdue ? "orange" : "zinc"}>Follow up {dateStr(x.next_follow_up)}</Badge></p>
        )}
        {canEdit && x.stage !== "joined" && (
          <div className="flex flex-wrap items-center gap-2 pt-1">
            <Select value={x.stage} onChange={(e) => onStage(e.target.value)} aria-label={`Stage of ${x.name}`} className="!w-auto !py-1 text-xs">
              <option value="found">Found</option>
              <option value="contacted">Contacted</option>
              <option value="talking">Talking</option>
              <option value="dropped">Dropped…</option>
            </Select>
            <Button className="!px-3 !py-1 text-xs" onClick={onJoin}>Make partner</Button>
            {x.phone && (
              <a href={waLink(x.phone, hello)} target="_blank" rel="noreferrer" className="text-xs font-semibold text-brand hover:underline">WhatsApp</a>
            )}
            <button onClick={onDelete} className="text-xs font-semibold text-zinc-500 hover:text-red-600">Delete</button>
          </div>
        )}
      </CardBody>
    </Card>
  );
}

function ProspectForm({ draft, setDraft, onClose, onDone }: {
  draft: Draft; setDraft: (d: Draft) => void; onClose: () => void; onDone: () => void;
}) {
  const [error, setError] = useState<string | null>(null);

  async function save() {
    const { error: e } = await createClient().rpc("admin_save_prospect", { p: draft });
    if (e) return setError(e.message);
    onDone();
  }

  const field = (key: keyof Draft, label: string, placeholder = "") => (
    <div>
      <Label>{label}</Label>
      <Input value={draft[key] ?? ""} placeholder={placeholder} onChange={(e) => setDraft({ ...draft, [key]: e.target.value })} />
    </div>
  );

  return (
    <Modal title={draft.id ? `Edit ${draft.name}` : "Add influencer"} onClose={onClose} wide>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
        {error && <p className="font-medium text-red-600">{error}</p>}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {field("name", "Name", "Rahul Sharma")}
          {field("handle", "Instagram / YouTube", "@rahul.business")}
          <div>
            <Label>Platform</Label>
            <Select value={draft.platform} onChange={(e) => setDraft({ ...draft, platform: e.target.value })}>
              {PLATFORMS.map(([k, label]) => <option key={k} value={k}>{label}</option>)}
            </Select>
          </div>
          <div>
            <Label>Followers</Label>
            <Input type="number" min={0} value={draft.followers} onChange={(e) => setDraft({ ...draft, followers: e.target.value })} />
          </div>
          {field("niche", "Niche", "Kirana tips")}
          {field("language", "Language", "Hindi")}
          {field("city", "City")}
          {field("phone", "WhatsApp number", "98765 43210")}
          <div>
            <Label>Next follow-up</Label>
            <Input type="date" value={draft.next_follow_up} onChange={(e) => setDraft({ ...draft, next_follow_up: e.target.value })} />
          </div>
          {field("deal_note", "Deal talk", "Asked ₹5,000 a reel, offered 20%")}
        </div>
        {field("note", "Note")}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={!draft.name.trim()}>Save</Button>
        </div>
      </form>
    </Modal>
  );
}

function DropDialog({ prospect, onClose, onDrop }: { prospect: any; onClose: () => void; onDrop: (reason: string) => void }) {
  const [reason, setReason] = useState("");
  return (
    <Modal title={`Drop ${prospect.name}?`} onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); onDrop(reason); }}>
        <div>
          <Label>Why (optional)</Label>
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Asked too much, no reply…" />
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit">Drop</Button>
        </div>
      </form>
    </Modal>
  );
}

function JoinDialog({ prospect, onClose }: { prospect: any; onClose: () => void }) {
  const router = useRouter();
  const [code, setCode] = useState("");
  const [off, setOff] = useState("10");
  const [kind, setKind] = useState("percent");
  const [value, setValue] = useState("20");
  const [hold, setHold] = useState("15");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    createClient().from("platform_settings").select("partner_buyer_off_pct, partner_commission_pct, partner_hold_days").eq("id", 1).maybeSingle()
      .then(({ data }) => {
        if (!data) return;
        setOff(String(Number(data.partner_buyer_off_pct)));
        setValue(String(Number(data.partner_commission_pct)));
        setHold(String(data.partner_hold_days));
      });
  }, []);

  async function make() {
    setBusy(true);
    setError(null);
    const { data, error: e } = await createClient().rpc("admin_prospect_to_partner", {
      p_prospect: prospect.id,
      p: { code, buyer_off_pct: Number(off), commission_kind: kind, commission_value: Number(value), hold_days: Number(hold) },
    });
    setBusy(false);
    if (e) return setError(e.message);
    router.push(`/influencers/${(data as any).id}`);
  }

  return (
    <Modal title={`Make ${prospect.name} a partner`} onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); make(); }}>
        {error && <p className="font-medium text-red-600">{error}</p>}
        <div>
          <Label>Code (3–20 letters, numbers, - or _)</Label>
          <Input required autoFocus value={code} pattern="[A-Za-z0-9_\-]{3,20}" className="font-mono" placeholder="RAHUL10"
            onChange={(e) => setCode(e.target.value.toUpperCase())} />
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <Label>Shop gets % off</Label>
            <Input type="number" min={0} max={50} value={off} onChange={(e) => setOff(e.target.value)} />
          </div>
          <div>
            <Label>Hold before paying (days)</Label>
            <Input type="number" min={0} max={90} value={hold} onChange={(e) => setHold(e.target.value)} />
          </div>
          <div>
            <Label>Partner earns</Label>
            <Select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="percent">% of first payment</option>
              <option value="amount">₹ per shop</option>
            </Select>
          </div>
          <div>
            <Label>{kind === "percent" ? "Percent" : "Amount ₹"}</Label>
            <Input type="number" min={0} max={kind === "percent" ? 100 : undefined} value={value} onChange={(e) => setValue(e.target.value)} />
          </div>
        </div>
        <p className="text-xs text-zinc-500">You&apos;ll go to their page next, to create their login and send it on WhatsApp.</p>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={busy || !code.trim()}>{busy ? "Creating…" : "Create partner"}</Button>
        </div>
      </form>
    </Modal>
  );
}
