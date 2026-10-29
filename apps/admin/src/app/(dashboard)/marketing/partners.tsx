"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table, Toggle } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const SITE = "https://www.dukania.in";
// Commission paid to one person in a financial year above this needs TDS
// (section 194H) — a reminder only; the CA decides.
const TDS_LIMIT = 20000;

type Editing = {
  id?: string; name: string; handle: string; phone: string; upi_id: string; code: string;
  buyer_off_pct: string; commission_kind: string; commission_value: string; hold_days: string; active: boolean; note: string;
};

const linkOf = (p: any) => `${SITE}/r/${p.code}`;
const statsOf = (p: any) => `${SITE}/partner/${p.stats_token}`;

/**
 * Influencer partners (migration 0104): each has a code and a link. A shop
 * that joins with it gets a discount; its first payment earns the partner a
 * commission, payable after the hold. Each partner has a private stats page.
 */
export function Partners() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [shops, setShops] = useState<any[]>([]);
  const [defaults, setDefaults] = useState({ buyer_off_pct: "10", commission_pct: "20", hold_days: "15" });
  const [editing, setEditing] = useState<Editing | null>(null);
  const [paying, setPaying] = useState<any>(null);
  const [viewing, setViewing] = useState<any>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [linkShop, setLinkShop] = useState("");
  const [linkCode, setLinkCode] = useState("");
  const canMarket = useCan("marketing");
  const canPay = useCan("payments");

  useEffect(() => {
    const db = createClient();
    db.rpc("admin_partners").then(({ data, error }) => {
      if (error) {
        setNotice({ ok: false, text: error.message.includes("admin_partners") ? "Migration 0104 isn't applied to this database yet." : error.message });
      }
      setRows((data as any[]) ?? []);
    });
    db.from("businesses").select("id, name, partner_id, referred_by").order("name").then(({ data }) => setShops(data ?? []));
    db.from("platform_settings").select("partner_buyer_off_pct, partner_commission_pct, partner_hold_days").eq("id", 1).maybeSingle()
      .then(({ data }) => data && setDefaults({
        buyer_off_pct: String(Number(data.partner_buyer_off_pct)),
        commission_pct: String(Number(data.partner_commission_pct)),
        hold_days: String(data.partner_hold_days),
      }));
  }, [refresh]);

  if (!rows) return <Spinner />;
  const owed = rows.reduce((s, p) => s + Math.max(0, Number(p.payable)), 0);

  async function copy(text: string, what: string) {
    try {
      await navigator.clipboard.writeText(text);
      setNotice({ ok: true, text: `${what} copied.` });
    } catch {
      setNotice({ ok: false, text: text });
    }
  }

  async function saveDefaults() {
    const { error } = await createClient().rpc("admin_set_partner_defaults", {
      p: { buyer_off_pct: Number(defaults.buyer_off_pct), commission_pct: Number(defaults.commission_pct), hold_days: Number(defaults.hold_days) },
    });
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: "Saved. New partners start with these; change any partner's deal on Edit." });
  }

  async function save() {
    if (!editing) return;
    const { data, error } = await createClient().rpc("admin_save_partner", {
      p: {
        id: editing.id ?? "", name: editing.name, handle: editing.handle, phone: editing.phone, upi_id: editing.upi_id,
        code: editing.code, buyer_off_pct: Number(editing.buyer_off_pct), commission_kind: editing.commission_kind,
        commission_value: Number(editing.commission_value), hold_days: Number(editing.hold_days),
        active: editing.active, note: editing.note,
      },
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: editing.id ? "Saved." : `${(data as any).name} is ready. Their link: ${linkOf(data)}` });
    setEditing(null);
    setRefresh((n) => n + 1);
  }

  async function newLink(p: any) {
    if (!window.confirm(`Make a new stats link for ${p.name}? The old one stops working.`)) return;
    const { data, error } = await createClient().rpc("admin_new_partner_link", { p_partner: p.id });
    if (error) return setNotice({ ok: false, text: error.message });
    copy(`${SITE}/partner/${data}`, "New stats link");
    setRefresh((n) => n + 1);
  }

  async function link() {
    const { data, error } = await createClient().rpc("admin_set_partner", { p_business: linkShop, p_code: linkCode });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: data ? `Linked to ${data}. If the shop has already paid, the commission is added.` : "Partner removed from the shop." });
    setLinkCode("");
    setRefresh((n) => n + 1);
  }

  const edit = (p?: any) => setEditing(p ? {
    id: p.id, name: p.name, handle: p.handle, phone: p.phone, upi_id: p.upi_id, code: p.code,
    buyer_off_pct: String(Number(p.buyer_off_pct)), commission_kind: p.commission_kind,
    commission_value: String(Number(p.commission_value)), hold_days: String(p.hold_days), active: p.active, note: p.note,
  } : {
    name: "", handle: "", phone: "", upi_id: "", code: "", buyer_off_pct: defaults.buyer_off_pct,
    commission_kind: "percent", commission_value: defaults.commission_pct, hold_days: defaults.hold_days, active: true, note: "",
  });

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Partners" value={rows.filter((p) => p.active).length} hint={`${rows.length} in all`} />
        <StatCard label="Link clicks, 30 days" value={rows.reduce((s, p) => s + Number(p.clicks_30), 0)} />
        <StatCard label="Shops joined · paid" value={`${rows.reduce((s, p) => s + Number(p.signups), 0)} · ${rows.reduce((s, p) => s + Number(p.paid_shops), 0)}`} />
        <StatCard label="Commission to pay now" value={inr(owed)} hint={`${inr(rows.reduce((s, p) => s + Number(p.held), 0))} still in the hold`} />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-zinc-600">
          Followers open the partner&apos;s link or enter the code in the app (Plan screen). The code also gives the discount when you record the sale.
        </p>
        {canMarket && <Button onClick={() => edit()}>New partner</Button>}
      </div>

      <Card>
        <Table headers={["Partner", "Deal", "Clicks", "Joined", "Paid", "Sales", "Owed now", "Paid out", ""]}>
          {rows.map((p) => {
            const payable = Number(p.payable);
            return (
              <tr key={p.id} className={p.active ? "" : "opacity-60"}>
                <td className="px-4 py-3">
                  <button onClick={() => setViewing(p)} className="text-left font-semibold text-ink hover:underline">{p.name}</button>
                  <span className="block text-xs text-zinc-500">
                    <span className="font-mono font-bold">{p.code}</span>{p.handle ? ` · ${p.handle}` : ""}{!p.active && " · off"}
                  </span>
                </td>
                <td className="px-4 py-3 text-xs">
                  {p.commission_kind === "amount" ? inr(p.commission_value) : `${Number(p.commission_value)}%`} to them
                  <span className="block text-zinc-500">{Number(p.buyer_off_pct)}% off for shops · {p.hold_days}-day hold</span>
                </td>
                <td className="px-4 py-3 tabular-nums">{p.clicks}<span className="block text-xs text-zinc-500">{p.clicks_30} in 30 days</span></td>
                <td className="px-4 py-3 tabular-nums">{p.signups}</td>
                <td className="px-4 py-3 tabular-nums">{p.paid_shops}</td>
                <td className="px-4 py-3 tabular-nums">{inr(p.sales)}</td>
                <td className="px-4 py-3 tabular-nums">
                  <b className={payable < 0 ? "text-red-600" : "text-ink"}>{inr(payable)}</b>
                  {Number(p.held) > 0 && <span className="block text-xs text-zinc-500">+ {inr(p.held)} held</span>}
                </td>
                <td className="px-4 py-3 tabular-nums">
                  {inr(p.paid)}
                  {p.last_paid_on && <span className="block text-xs text-zinc-500">{dateStr(p.last_paid_on)}</span>}
                </td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap justify-end gap-2">
                    {canPay && payable > 0 && <Button onClick={() => setPaying(p)}>Pay {inr(payable)}</Button>}
                    <Button variant="outline" onClick={() => copy(linkOf(p), "Link")}>Copy link</Button>
                    {canMarket && <Button variant="ghost" onClick={() => edit(p)}>Edit</Button>}
                  </div>
                </td>
              </tr>
            );
          })}
          {rows.length === 0 && (
            <tr><td colSpan={9} className="px-4 py-10 text-center text-zinc-500">No partners yet. Add an influencer to give them a code and a link.</td></tr>
          )}
        </Table>
      </Card>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {canMarket && (
          <Card>
            <CardBody className="space-y-3">
              <h2 className="text-sm font-semibold text-zinc-700">Deal for new partners</h2>
              <div className="grid grid-cols-3 gap-3">
                <div>
                  <Label>Shop gets % off</Label>
                  <Input type="number" min={0} max={50} value={defaults.buyer_off_pct} onChange={(e) => setDefaults({ ...defaults, buyer_off_pct: e.target.value })} />
                </div>
                <div>
                  <Label>Partner gets %</Label>
                  <Input type="number" min={0} max={100} value={defaults.commission_pct} onChange={(e) => setDefaults({ ...defaults, commission_pct: e.target.value })} />
                </div>
                <div>
                  <Label>Hold (days)</Label>
                  <Input type="number" min={0} max={90} value={defaults.hold_days} onChange={(e) => setDefaults({ ...defaults, hold_days: e.target.value })} />
                </div>
              </div>
              <div className="flex items-center justify-between gap-3">
                <p className="text-xs text-zinc-500">Partner&apos;s % is of the shop&apos;s first payment, before GST. Renewals earn nothing.</p>
                <Button variant="outline" onClick={saveDefaults}>Save</Button>
              </div>
            </CardBody>
          </Card>
        )}

        <Card>
          <CardBody className="space-y-3">
            <h2 className="text-sm font-semibold text-zinc-700">A shop came from a partner</h2>
            <Select value={linkShop} onChange={(e) => setLinkShop(e.target.value)} aria-label="Shop">
              <option value="">Choose the shop…</option>
              {shops.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}{s.partner_id ? ` (${rows.find((p) => p.id === s.partner_id)?.name ?? "partner"})` : ""}
                </option>
              ))}
            </Select>
            <div className="flex gap-2">
              <Input value={linkCode} onChange={(e) => setLinkCode(e.target.value.toUpperCase())} placeholder="The partner's code (empty = remove)" />
              <Button variant="outline" onClick={link} disabled={!linkShop}>Save</Button>
            </div>
            <p className="text-xs text-zinc-500">For a shop that forgot the code. Using the code when you record its first sale links it too.</p>
          </CardBody>
        </Card>
      </div>

      {editing && (
        <Modal title={editing.id ? `Edit ${editing.name}` : "New partner"} onClose={() => setEditing(null)} wide>
          <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <Label>Name</Label>
                <Input required value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} placeholder="Rahul Sharma" />
              </div>
              <div>
                <Label>Instagram / YouTube</Label>
                <Input value={editing.handle} onChange={(e) => setEditing({ ...editing, handle: e.target.value })} placeholder="@rahul.business" />
              </div>
              <div>
                <Label>WhatsApp number</Label>
                <Input value={editing.phone} onChange={(e) => setEditing({ ...editing, phone: e.target.value })} placeholder="98765 43210" />
              </div>
              <div>
                <Label>UPI ID (for payouts)</Label>
                <Input value={editing.upi_id} onChange={(e) => setEditing({ ...editing, upi_id: e.target.value })} placeholder="rahul@okaxis" />
              </div>
              <div>
                <Label>Code {editing.id ? "(can't change)" : "(3–20 letters, numbers, - or _)"}</Label>
                <Input required disabled={Boolean(editing.id)} value={editing.code} pattern="[A-Za-z0-9_-]{3,20}" className="font-mono"
                  onChange={(e) => setEditing({ ...editing, code: e.target.value.toUpperCase() })} placeholder="RAHUL10" />
                {editing.code && <p className="mt-1 text-xs text-zinc-500">Link: {SITE}/r/{editing.code}</p>}
              </div>
              <div>
                <Label>Shop gets % off the website price</Label>
                <Input type="number" min={0} max={50} value={editing.buyer_off_pct} onChange={(e) => setEditing({ ...editing, buyer_off_pct: e.target.value })} />
              </div>
              <div>
                <Label>Partner earns</Label>
                <div className="flex gap-2">
                  <Select value={editing.commission_kind} onChange={(e) => setEditing({ ...editing, commission_kind: e.target.value })} className="w-52 shrink-0">
                    <option value="percent">% of first payment</option>
                    <option value="amount">₹ per shop</option>
                  </Select>
                  <Input required type="number" min={0} max={editing.commission_kind === "percent" ? 100 : undefined} value={editing.commission_value}
                    onChange={(e) => setEditing({ ...editing, commission_value: e.target.value })} />
                </div>
              </div>
              <div>
                <Label>Hold before paying (days)</Label>
                <Input type="number" min={0} max={90} value={editing.hold_days} onChange={(e) => setEditing({ ...editing, hold_days: e.target.value })} />
              </div>
            </div>
            <div>
              <Label>Note (only the team sees it)</Label>
              <Input value={editing.note} onChange={(e) => setEditing({ ...editing, note: e.target.value })} placeholder="e.g. 45k followers, kirana tips" />
            </div>
            {editing.id && <Toggle checked={editing.active} onChange={(v) => setEditing({ ...editing, active: v })} label={editing.active ? "On — link and code work" : "Off — link and code stop"} />}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit" disabled={!editing.name.trim() || !editing.code.trim()}>{editing.id ? "Save" : "Create"}</Button>
            </div>
          </form>
        </Modal>
      )}

      {paying && <PayDialog partner={paying} onClose={() => setPaying(null)}
        onDone={(text) => { setPaying(null); setNotice({ ok: true, text }); setRefresh((n) => n + 1); }} />}

      {viewing && (
        <PartnerDetail partner={viewing} onClose={() => setViewing(null)}
          onCopy={copy} onNewLink={canMarket ? () => newLink(viewing) : undefined} />
      )}
    </div>
  );
}

function PayDialog({ partner, onClose, onDone }: { partner: any; onClose: () => void; onDone: (text: string) => void }) {
  const [mode, setMode] = useState("upi");
  const [reference, setReference] = useState("");
  const [paidOn, setPaidOn] = useState(new Date().toISOString().slice(0, 10));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const amount = Number(partner.payable);
  const overTds = Number(partner.paid_this_fy) + amount > TDS_LIMIT;

  async function pay() {
    setBusy(true);
    setError(null);
    const { data, error } = await createClient().rpc("admin_pay_partner", {
      p_partner: partner.id, p: { mode, reference: reference.trim(), paid_on: paidOn },
    });
    setBusy(false);
    if (error) return setError(error.message);
    onDone(`${inr((data as any).amount)} paid to ${partner.name}, and added to Accounts as a commission expense.`);
  }

  const msg = `Namaste ${partner.name}! Your Dukania commission of ${inr(amount)} is paid${reference ? ` (ref ${reference})` : ""}. ` +
    `See your numbers any time: ${statsOf(partner)} — thank you! Dukania`;

  return (
    <Modal title={`Pay ${partner.name}`} onClose={onClose}>
      <div className="space-y-4 text-sm">
        <p>
          Payable now: <b className="text-lg">{inr(amount)}</b>
          {partner.upi_id ? <> to <span className="font-mono">{partner.upi_id}</span></> : " (no UPI ID saved)"}
        </p>
        {overTds && (
          <p className="rounded-xl bg-amber-50 px-4 py-3 text-amber-800">
            Commission to {partner.name} this financial year goes over {inr(TDS_LIMIT)}. TDS may apply (section 194H) — check with your CA before paying.
          </p>
        )}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div>
            <Label>Paid by</Label>
            <Select value={mode} onChange={(e) => setMode(e.target.value)}>
              <option value="upi">UPI</option>
              <option value="other">Bank transfer</option>
              <option value="cash">Cash</option>
            </Select>
          </div>
          <div>
            <Label>UPI / bank reference</Label>
            <Input value={reference} onChange={(e) => setReference(e.target.value)} className="font-mono" placeholder="12-digit UTR" />
          </div>
          <div>
            <Label>Date</Label>
            <Input type="date" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
          </div>
        </div>
        {error && <p className="font-medium text-red-600">{error}</p>}
        <div className="flex flex-wrap justify-end gap-2">
          {partner.phone && <a href={waLink(partner.phone, msg)} target="_blank" rel="noreferrer"><Button variant="outline">WhatsApp them</Button></a>}
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={pay} disabled={busy || (mode !== "cash" && !reference.trim())}>{busy ? "Saving…" : `Mark ${inr(amount)} paid`}</Button>
        </div>
      </div>
    </Modal>
  );
}

const STATUS: Record<string, [string, string]> = {
  pending: ["Waiting", "orange"],
  paid: ["Paid", "green"],
  cancelled: ["Cancelled", "zinc"],
};

function PartnerDetail({ partner, onClose, onCopy, onNewLink }: {
  partner: any; onClose: () => void; onCopy: (text: string, what: string) => void; onNewLink?: () => void;
}) {
  const [rows, setRows] = useState<any[] | null>(null);
  const [payouts, setPayouts] = useState<any[]>([]);
  const today = new Date().toISOString().slice(0, 10);

  useEffect(() => {
    const db = createClient();
    db.from("partner_commissions").select("*, businesses(name)").eq("partner_id", partner.id).order("created_at", { ascending: false })
      .then(({ data }) => setRows(data ?? []));
    db.from("partner_payouts").select("*").eq("partner_id", partner.id).order("paid_on", { ascending: false })
      .then(({ data }) => setPayouts(data ?? []));
  }, [partner.id]);

  const invite = `Namaste ${partner.name}! Your Dukania partner link: ${linkOf(partner)} — your code ${partner.code} gives shops ` +
    `${Number(partner.buyer_off_pct)}% off. Your numbers and earnings: ${statsOf(partner)} (keep this link private). Dukania`;

  return (
    <Modal title={partner.name} onClose={onClose} wide>
      <div className="space-y-5 text-sm">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="rounded-xl bg-zinc-50 p-3">
            <p className="text-xs text-zinc-500">Their link (for posts and bio)</p>
            <p className="break-all font-mono font-semibold">{linkOf(partner)}</p>
            <Button variant="outline" className="mt-2" onClick={() => onCopy(linkOf(partner), "Link")}>Copy</Button>
          </div>
          <div className="rounded-xl bg-zinc-50 p-3">
            <p className="text-xs text-zinc-500">Their private stats page</p>
            <p className="break-all font-mono text-xs">{statsOf(partner)}</p>
            <div className="mt-2 flex gap-2">
              <Button variant="outline" onClick={() => onCopy(statsOf(partner), "Stats link")}>Copy</Button>
              {onNewLink && <Button variant="ghost" onClick={onNewLink}>New link</Button>}
            </div>
          </div>
        </div>
        {partner.phone && (
          <div>
            <a href={waLink(partner.phone, invite)} target="_blank" rel="noreferrer"><Button>Send link and code on WhatsApp</Button></a>
          </div>
        )}

        <div>
          <h3 className="mb-2 font-semibold text-zinc-700">Shops that paid</h3>
          {!rows ? <Spinner /> : rows.length === 0 ? (
            <p className="text-zinc-500">No paid shops yet. {partner.signups} joined with the code.</p>
          ) : (
            <Table headers={["Shop", "Paid", "Commission", "Payable", ""]}>
              {rows.map((c) => {
                const [label, color] = STATUS[c.status] ?? ["", "zinc"];
                return (
                  <tr key={c.id}>
                    <td className="px-4 py-3">
                      <Link href={`/clients/${c.business_id}`} className="font-semibold text-ink hover:underline">{c.businesses?.name ?? "—"}</Link>
                      {c.kind === "refund" && <span className="block text-xs text-red-600">Refund — taken back</span>}
                    </td>
                    <td className="whitespace-nowrap px-4 py-3 tabular-nums">{inr(c.paid_amount)}</td>
                    <td className="whitespace-nowrap px-4 py-3 tabular-nums">
                      {inr(c.amount)}
                      {c.kind === "sale" && <span className="block text-xs text-zinc-500">{c.rule} of {inr(c.base)}</span>}
                    </td>
                    <td className="px-4 py-3">{c.status === "pending" && c.payable_on > today ? `From ${dateStr(c.payable_on)}` : dateStr(c.payable_on)}</td>
                    <td className="px-4 py-3"><Badge color={color}>{label}</Badge></td>
                  </tr>
                );
              })}
            </Table>
          )}
        </div>

        {payouts.length > 0 && (
          <div>
            <h3 className="mb-2 font-semibold text-zinc-700">Payouts</h3>
            <ul className="divide-y divide-zinc-100">
              {payouts.map((o) => (
                <li key={o.id} className="flex justify-between py-2">
                  <span>{dateStr(o.paid_on)} · <span className="font-mono text-xs">{o.reference || o.mode}</span></span>
                  <b className="tabular-nums">{inr(o.amount)}</b>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </Modal>
  );
}
