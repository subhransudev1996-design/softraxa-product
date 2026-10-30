"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner, subscriptionBadge } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { BUSINESS_TYPES, businessTypeLabel } from "@/lib/business-types";
import { dateStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Filters = {
  q: string; status: string; plan: string; type: string; expiry: string; usage: string; ai: string; joined: string;
};
const NO_FILTERS: Filters = { q: "", status: "all", plan: "all", type: "all", expiry: "all", usage: "all", ai: "all", joined: "all" };

const day = 86400000;

function matches(s: any, f: Filters, now: number): boolean {
  if (f.q) {
    const q = f.q.toLowerCase();
    if (![s.name, s.owner_name, s.phone, s.address].some((v: string) => (v ?? "").toLowerCase().includes(q))) return false;
  }
  if (f.status !== "all" && s.status !== f.status) return false;
  if (f.plan === "none" ? s.plan_id : f.plan !== "all" && s.plan_id !== f.plan) return false;
  if (f.type !== "all" && s.business_type !== f.type) return false;
  const exp = s.expiry_date ? new Date(`${s.expiry_date}T00:00:00`).getTime() : null;
  if (f.expiry === "7" && !(exp !== null && exp >= now - day && exp <= now + 7 * day)) return false;
  if (f.expiry === "30" && !(exp !== null && exp >= now - day && exp <= now + 30 * day)) return false;
  if (f.expiry === "lapsed" && !(exp !== null && exp < now - day && exp >= now - 60 * day)) return false;
  const bills = Number(s.bills_30d ?? 0);
  if (f.usage === "none" && bills > 0) return false;
  if (f.usage === "low" && !(bills >= 1 && bills <= 20)) return false;
  if (f.usage === "high" && bills <= 20) return false;
  if (f.ai === "yes" && !s.has_ai) return false;
  if (f.ai === "no" && s.has_ai) return false;
  const joined = new Date(s.created_at).getTime();
  if (f.joined === "7" && joined < now - 7 * day) return false;
  if (f.joined === "30" && joined < now - 30 * day) return false;
  return true;
}

/** Describes the group in words, for the announcement's record. */
function describe(f: Filters, plans: any[]): string {
  const parts = [
    f.status !== "all" && f.status,
    f.plan === "none" ? "no plan" : f.plan !== "all" && plans.find((p) => p.id === f.plan)?.name,
    f.type !== "all" && businessTypeLabel(f.type),
    { "7": "ending in 7 days", "30": "ending in 30 days", lapsed: "lapsed in the last 60 days" }[f.expiry],
    { none: "no bills in 30 days", low: "1–20 bills in 30 days", high: "20+ bills in 30 days" }[f.usage],
    { yes: "with AI", no: "without AI" }[f.ai],
    { "7": "joined this week", "30": "joined this month" }[f.joined],
    f.q && `matching "${f.q}"`,
  ].filter(Boolean);
  return parts.length ? parts.join(", ") : "every shop";
}

/**
 * Pick a group of shops by plan, type, expiry and how much they use
 * Dukania, then announce to them (banner and/or notification) or work
 * through them on WhatsApp.
 */
export function ShopGroups() {
  const [shops, setShops] = useState<any[] | null>(null);
  const [plans, setPlans] = useState<any[]>([]);
  const [f, setF] = useState<Filters>(NO_FILTERS);
  const [error, setError] = useState<string | null>(null);
  const [announcing, setAnnouncing] = useState(false);
  const [whatsapp, setWhatsapp] = useState(false);
  const [now] = useState(() => Date.now());

  useEffect(() => {
    const db = createClient();
    db.rpc("admin_marketing_shops").then(({ data, error }) => {
      if (error) setError(error.message.includes("admin_marketing_shops") ? "Migration 0101 isn't applied to this database yet." : error.message);
      setShops((data as any[]) ?? []);
    });
    db.from("plans").select("id, name").order("sort_order").then(({ data }) => setPlans(data ?? []));
  }, []);

  if (!shops) return <Spinner />;
  const group = shops.filter((s) => matches(s, f, now));
  const set = (k: keyof Filters, v: string) => setF((x) => ({ ...x, [k]: v }));

  return (
    <div className="space-y-4">
      {error && <Notice notice={{ ok: false, text: error }} />}
      <Card>
        <CardBody className="space-y-3">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Input placeholder="Name, owner, phone, address…" value={f.q} onChange={(e) => set("q", e.target.value)} />
            <Select value={f.status} onChange={(e) => set("status", e.target.value)} aria-label="Status">
              <option value="all">Trial, paid or expired</option>
              <option value="trial">On trial</option>
              <option value="active">Paid (active)</option>
              <option value="expired">Expired</option>
              <option value="suspended">Suspended</option>
            </Select>
            <Select value={f.plan} onChange={(e) => set("plan", e.target.value)} aria-label="Plan">
              <option value="all">Any plan</option>
              {plans.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              <option value="none">No plan</option>
            </Select>
            <Select value={f.type} onChange={(e) => set("type", e.target.value)} aria-label="Type of shop">
              <option value="all">Any type of shop</option>
              {BUSINESS_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </Select>
            <Select value={f.expiry} onChange={(e) => set("expiry", e.target.value)} aria-label="Plan ends">
              <option value="all">Any end date</option>
              <option value="7">Ending in 7 days</option>
              <option value="30">Ending in 30 days</option>
              <option value="lapsed">Lapsed in the last 60 days</option>
            </Select>
            <Select value={f.usage} onChange={(e) => set("usage", e.target.value)} aria-label="Bills in 30 days">
              <option value="all">Any use</option>
              <option value="none">No bills in 30 days</option>
              <option value="low">1–20 bills in 30 days</option>
              <option value="high">More than 20 bills in 30 days</option>
            </Select>
            <Select value={f.ai} onChange={(e) => set("ai", e.target.value)} aria-label="AI assistant">
              <option value="all">With or without AI</option>
              <option value="yes">With AI</option>
              <option value="no">Without AI</option>
            </Select>
            <Select value={f.joined} onChange={(e) => set("joined", e.target.value)} aria-label="Joined">
              <option value="all">Joined any time</option>
              <option value="7">Joined this week</option>
              <option value="30">Joined this month</option>
            </Select>
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-zinc-700">
              <b>{group.length}</b> of {shops.length} shops — {describe(f, plans)}
              {f !== NO_FILTERS && (
                <button onClick={() => setF(NO_FILTERS)} className="ml-2 text-xs font-semibold text-brand hover:underline">Clear</button>
              )}
            </p>
            <div className="flex flex-wrap gap-2">
              <Button variant="outline" onClick={() => setWhatsapp(true)} disabled={group.length === 0}>WhatsApp list</Button>
              <Button onClick={() => setAnnouncing(true)} disabled={group.length === 0}>Announce to {group.length}</Button>
            </div>
          </div>
        </CardBody>
      </Card>

      <Card>
        <ul className="divide-y divide-zinc-100">
          {group.slice(0, 200).map((s) => (
            <li key={s.id} className="flex flex-col gap-1 px-5 py-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="min-w-0">
                <Link href={`/clients/${s.id}`} className="font-semibold text-ink hover:underline">{s.name}</Link>
                <p className="truncate text-xs text-zinc-500">
                  {s.owner_name || "—"} · {s.phone || "no phone"} · {businessTypeLabel(s.business_type)}
                </p>
              </div>
              <div className="flex shrink-0 flex-wrap items-center gap-2 text-xs text-zinc-500">
                <span>{s.bills_30d} bills / 30 days</span>
                {s.expiry_date && <span>ends {dateStr(s.expiry_date)}</span>}
                <Badge color={subscriptionBadge(s.status)}>{s.plan_name ?? s.status ?? "no plan"}</Badge>
              </div>
            </li>
          ))}
          {group.length > 200 && <li className="px-5 py-3 text-center text-xs text-zinc-500">…and {group.length - 200} more</li>}
          {group.length === 0 && <li className="px-5 py-10 text-center text-sm text-zinc-500">No shop matches.</li>}
        </ul>
      </Card>

      {announcing && (
        <AnnounceDialog shops={group} audience={describe(f, plans)} onClose={() => setAnnouncing(false)} />
      )}
      {whatsapp && <WhatsAppList shops={group} onClose={() => setWhatsapp(false)} />}
    </div>
  );
}

/** A banner in the shops' app and/or a notification on their phones. */
function AnnounceDialog({ shops, audience, onClose }: { shops: any[]; audience: string; onClose: () => void }) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [buttonLabel, setButtonLabel] = useState("");
  const [buttonUrl, setButtonUrl] = useState("");
  const [banner, setBanner] = useState(true);
  const [push, setPush] = useState(false);
  const [endsOn, setEndsOn] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [done, setDone] = useState(false);

  async function send() {
    setBusy(true);
    setNotice(null);
    const db = createClient();
    const { data: id, error } = await db.rpc("admin_create_announcement", {
      p: {
        title, body, button_label: buttonLabel, button_url: buttonUrl, banner, push, audience,
        business_ids: shops.map((s) => s.id),
        ends_at: endsOn ? new Date(`${endsOn}T23:59:59+05:30`).toISOString() : null,
      },
    });
    if (error) {
      setBusy(false);
      return setNotice({ ok: false, text: error.message });
    }
    let text = banner ? `The banner is in the app for ${shops.length} shop${shops.length === 1 ? "" : "s"}.` : "Saved.";
    if (push) {
      const { data, error: pushError } = await db.functions.invoke("announce-push", { body: { announcement_id: id } });
      text += pushError
        ? ` The notification didn't go: ${pushError.message}. Is the announce-push function deployed?`
        : ` Notification sent to ${(data as any)?.sent ?? 0} phone${(data as any)?.sent === 1 ? "" : "s"}${(data as any)?.skipped ? ` (${(data as any).skipped})` : ""}.`;
    }
    setBusy(false);
    setDone(true);
    setNotice({ ok: true, text });
  }

  return (
    <Modal title={`Announce to ${shops.length} shop${shops.length === 1 ? "" : "s"}`} onClose={onClose} wide>
      <div className="space-y-4">
        <p className="text-xs text-zinc-500">Group: {audience}. The app shows no prices — write offers as &quot;call us&quot; or a link.</p>
        <div>
          <Label>Title</Label>
          <Input value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. New: print bills on A5" />
        </div>
        <div>
          <Label>Message</Label>
          <textarea rows={3} maxLength={1000} value={body} onChange={(e) => setBody(e.target.value)}
            className="w-full rounded-md border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10" />
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <Label>Button (optional)</Label>
            <Input value={buttonLabel} onChange={(e) => setButtonLabel(e.target.value)} placeholder="e.g. Watch the video" />
          </div>
          <div>
            <Label>Button link</Label>
            <Input value={buttonUrl} onChange={(e) => setButtonUrl(e.target.value)} placeholder="https://…" />
          </div>
        </div>
        <div className="flex flex-wrap gap-4 text-sm">
          <label className="flex items-center gap-2"><input type="checkbox" checked={banner} onChange={(e) => setBanner(e.target.checked)} /> Banner on the app&apos;s home screen</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={push} onChange={(e) => setPush(e.target.checked)} /> Notification on their phones</label>
        </div>
        {banner && (
          <div className="max-w-xs">
            <Label>Banner ends on (optional)</Label>
            <Input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
          </div>
        )}
        <Notice notice={notice} />
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>{done ? "Close" : "Cancel"}</Button>
          {!done && (
            <Button onClick={send} disabled={busy || !title.trim() || (!banner && !push)}>{busy ? "Sending…" : "Send"}</Button>
          )}
        </div>
      </div>
    </Modal>
  );
}

/** One WhatsApp button per shop with the message filled in; ticks show who's done. */
function WhatsAppList({ shops, onClose }: { shops: any[]; onClose: () => void }) {
  const [text, setText] = useState("Namaste {owner}! This is Dukania. ");
  const [sent, setSent] = useState<Set<string>>(new Set());
  const withPhone = shops.filter((s) => s.phone);
  const fill = (s: any) => text.replaceAll("{owner}", s.owner_name || "").replaceAll("{shop}", s.name);

  return (
    <Modal title={`WhatsApp ${withPhone.length} shop${withPhone.length === 1 ? "" : "s"}`} onClose={onClose} wide>
      <div className="space-y-4">
        <div>
          <Label>Message — {"{owner}"} and {"{shop}"} are filled in for each shop</Label>
          <textarea rows={3} value={text} onChange={(e) => setText(e.target.value)}
            className="w-full rounded-md border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10" />
        </div>
        <p className="text-xs text-zinc-500">{sent.size} of {withPhone.length} opened. {shops.length - withPhone.length > 0 ? `${shops.length - withPhone.length} without a phone number are left out.` : ""}</p>
        <ul className="max-h-[50dvh] divide-y divide-zinc-100 overflow-y-auto rounded-md border border-zinc-200">
          {withPhone.map((s) => (
            <li key={s.id} className="flex items-center justify-between gap-3 px-4 py-2.5">
              <div className="min-w-0">
                <p className={`truncate text-sm font-semibold ${sent.has(s.id) ? "text-zinc-400 line-through" : "text-ink"}`}>{s.name}</p>
                <p className="truncate text-xs text-zinc-500">{s.owner_name || "—"} · {s.phone}</p>
              </div>
              <a href={waLink(s.phone, fill(s))} target="_blank" rel="noreferrer"
                onClick={() => setSent((x) => new Set(x).add(s.id))}>
                <Button variant={sent.has(s.id) ? "ghost" : "outline"}>{sent.has(s.id) ? "Again" : "WhatsApp"}</Button>
              </a>
            </li>
          ))}
        </ul>
      </div>
    </Modal>
  );
}
