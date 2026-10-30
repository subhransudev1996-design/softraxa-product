"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Handshake, IndianRupee, MousePointerClick, TrendingUp } from "lucide-react";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Notice } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr, inr } from "@/lib/format";
import { Editing, PartnerForm, PayDialog, editingFrom, linkOf } from "./shared";

/* eslint-disable @typescript-eslint/no-explicit-any */

const pct = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "—");

/** Active, older than 30 days, and no clicks in the last 30. */
export function isQuiet(p: any) {
  return p.active && Number(p.clicks_30) === 0 && Date.now() - new Date(p.created_at).getTime() > 30 * 86400000;
}

/**
 * Influencer partners (migrations 0104, 0109): each has a code and a link. A
 * shop that joins with it gets a discount; its first payment earns the
 * partner a commission, payable after the hold. "You made" is that payment
 * before GST and after refunds, less commission and fixed fees.
 */
export function Partners() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [shops, setShops] = useState<any[]>([]);
  const [defaults, setDefaults] = useState({ buyer_off_pct: "10", commission_pct: "20", hold_days: "15", min_payout: "500" });
  const [editing, setEditing] = useState<Editing | null>(null);
  const [paying, setPaying] = useState<any>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [linkShop, setLinkShop] = useState("");
  const [linkCode, setLinkCode] = useState("");
  const [sort, setSort] = useState("newest");
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
    db.from("platform_settings").select("partner_buyer_off_pct, partner_commission_pct, partner_hold_days, partner_min_payout").eq("id", 1).maybeSingle()
      .then(({ data }) => data && setDefaults({
        buyer_off_pct: String(Number(data.partner_buyer_off_pct)),
        commission_pct: String(Number(data.partner_commission_pct)),
        hold_days: String(data.partner_hold_days),
        min_payout: String(Number(data.partner_min_payout ?? 500)),
      }));
  }, [refresh]);

  if (!rows) return <Spinner />;
  const owed = rows.reduce((s, p) => s + Math.max(0, Number(p.payable)), 0);
  const sorted = sort === "newest" ? rows : [...rows].sort((a, b) => Number(b[sort]) - Number(a[sort]));

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
      p: { buyer_off_pct: Number(defaults.buyer_off_pct), commission_pct: Number(defaults.commission_pct), hold_days: Number(defaults.hold_days), min_payout: Number(defaults.min_payout) },
    });
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: "Saved. New partners start with these; change any partner's deal on Edit." });
  }

  async function link() {
    const { data, error } = await createClient().rpc("admin_set_partner", { p_business: linkShop, p_code: linkCode });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: data ? `Linked to ${data}. If the shop has already paid, the commission is added.` : "Partner removed from the shop." });
    setLinkCode("");
    setRefresh((n) => n + 1);
  }

  const newPartner = () => setEditing({
    name: "", handle: "", phone: "", upi_id: "", code: "", buyer_off_pct: defaults.buyer_off_pct,
    commission_kind: "percent", commission_value: defaults.commission_pct, hold_days: defaults.hold_days, active: true, note: "",
    platform: "instagram", followers: "", niche: "", language: "", city: "",
  });

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Partners" value={rows.filter((p) => p.active).length} hint={`${rows.length} in all`} icon={<Handshake size={17} />} />
        <StatCard label="Link clicks, 30 days" value={rows.reduce((s, p) => s + Number(p.clicks_30), 0)} icon={<MousePointerClick size={17} />} />
        <StatCard label="You made, all partners" value={inr(rows.reduce((s, p) => s + Number(p.net), 0))} hint="First payments less commission and fees" icon={<TrendingUp size={17} />} />
        <StatCard label="Commission to pay now" value={inr(owed)} hint={`${inr(rows.reduce((s, p) => s + Number(p.held), 0))} still in the hold`} icon={<IndianRupee size={17} />} />
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Label>Sort</Label>
          <Select value={sort} onChange={(e) => setSort(e.target.value)} aria-label="Sort partners" className="w-44">
            <option value="newest">Newest</option>
            <option value="net">Most you made</option>
            <option value="paid_shops">Most paid shops</option>
            <option value="clicks_30">Most clicks, 30 days</option>
          </Select>
        </div>
        {canMarket && <Button onClick={newPartner}>New partner</Button>}
      </div>

      <Card>
        <Table headers={["Partner", "Deal", "Clicks", "Joined", "Paid", "You made", "Owed now", "Paid out", ""]}>
          {sorted.map((p) => {
            const payable = Number(p.payable);
            const net = Number(p.net);
            return (
              <tr key={p.id} className={p.active ? "" : "opacity-60"}>
                <td className="px-4 py-3">
                  <Link href={`/influencers/${p.id}`} className="text-left font-semibold text-ink hover:underline">{p.name}</Link>
                  <span className="block text-xs text-zinc-500">
                    <span className="font-mono font-bold">{p.code}</span>{p.handle ? ` · ${p.handle}` : ""}{!p.active && " · off"}
                  </span>
                  {isQuiet(p) && <span className="mt-1 block"><Badge color="orange">No clicks in 30 days</Badge></span>}
                </td>
                <td className="whitespace-nowrap px-4 py-3 text-xs">
                  {p.commission_kind === "amount" ? inr(p.commission_value) : `${Number(p.commission_value)}%`} to them
                  <span className="block text-zinc-500">{Number(p.buyer_off_pct)}% off for shops · {p.hold_days}-day hold</span>
                </td>
                <td className="px-4 py-3 tabular-nums">{p.clicks}<span className="block text-xs text-zinc-500">{p.clicks_30} in 30 days</span></td>
                <td className="px-4 py-3 tabular-nums">{p.signups}<span className="block text-xs text-zinc-500">{pct(Number(p.signups), Number(p.clicks))} of clicks</span></td>
                <td className="px-4 py-3 tabular-nums">{p.paid_shops}<span className="block text-xs text-zinc-500">{pct(Number(p.paid_shops), Number(p.signups))} of joined</span></td>
                <td className="px-4 py-3 tabular-nums">
                  <b className={net < 0 ? "text-red-600" : "text-ink"}>{inr(net)}</b>
                  {Number(p.fees) > 0 && <span className="block text-xs text-zinc-500">after {inr(p.fees)} fees</span>}
                </td>
                <td className="px-4 py-3 tabular-nums">
                  <b className={payable < 0 ? "text-red-600" : "text-ink"}>{inr(payable)}</b>
                  {Number(p.held) > 0 && <span className="block text-xs text-zinc-500">+ {inr(p.held)} held</span>}
                  {p.payout_request && <span className="mt-1 block"><Badge color="orange">Payout requested</Badge></span>}
                </td>
                <td className="px-4 py-3 tabular-nums">
                  {inr(p.paid)}
                  {p.last_paid_on && <span className="block text-xs text-zinc-500">{dateStr(p.last_paid_on)}</span>}
                </td>
                <td className="px-4 py-3">
                  <div className="flex flex-wrap justify-end gap-2">
                    {canPay && payable > 0 && <Button onClick={() => setPaying(p)}>Pay {inr(payable)}</Button>}
                    <Button variant="outline" onClick={() => copy(linkOf(p), "Link")}>Copy link</Button>
                    {canMarket && <Button variant="ghost" onClick={() => setEditing(editingFrom(p))}>Edit</Button>}
                  </div>
                </td>
              </tr>
            );
          })}
          {rows.length === 0 && (
            <tr><td colSpan={9} className="px-4 py-10 text-center text-zinc-500">No partners yet. Add an influencer here, or use Make partner on the Pipeline tab.</td></tr>
          )}
        </Table>
      </Card>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {canMarket && (
          <Card>
            <CardBody className="space-y-3">
              <h2 className="text-sm font-semibold text-zinc-700">Deal for new partners</h2>
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
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
                <div>
                  <Label>Minimum payout ₹</Label>
                  <Input type="number" min={0} value={defaults.min_payout} onChange={(e) => setDefaults({ ...defaults, min_payout: e.target.value })} />
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
        <PartnerForm editing={editing} setEditing={setEditing} onClose={() => setEditing(null)}
          onDone={(text) => { setEditing(null); setNotice({ ok: true, text }); setRefresh((n) => n + 1); }} />
      )}

      {paying && <PayDialog partner={paying} onClose={() => setPaying(null)}
        onDone={(text) => { setPaying(null); setNotice({ ok: true, text }); setRefresh((n) => n + 1); }} />}
    </div>
  );
}
