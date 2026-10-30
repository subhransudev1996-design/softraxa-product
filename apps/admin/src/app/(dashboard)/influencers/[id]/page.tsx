"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, PageHeader, Spinner, StatCard, Table } from "@/components/ui";
import { Notice, waLink } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr, inr } from "@/lib/format";
import { isQuiet } from "../partners";
import { PostsAndFees } from "../posts-fees";
import { Editing, PartnerForm, PartnerLogin, PayDialog, STATUS, editingFrom, linkOf, statsOf } from "../shared";

/* eslint-disable @typescript-eslint/no-explicit-any */

const pct = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "—");

/** One influencer (migration 0109): the funnel, what they really made, posts, fees, sales, payouts and login. */
export default function InfluencerPage() {
  const { id } = useParams<{ id: string }>();
  const [partner, setPartner] = useState<any>(undefined);
  const [funnel, setFunnel] = useState<any>(null);
  const [sales, setSales] = useState<any[] | null>(null);
  const [payouts, setPayouts] = useState<any[]>([]);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [paying, setPaying] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const canMarket = useCan("marketing");
  const canPay = useCan("payments");
  const today = new Date().toISOString().slice(0, 10);

  useEffect(() => {
    const db = createClient();
    db.rpc("admin_partners").then(({ data, error }) => {
      if (error) setNotice({ ok: false, text: error.message });
      setPartner(((data as any[]) ?? []).find((p) => p.id === id) ?? null);
    });
    db.rpc("admin_partner_funnel", { p_partner: id }).then(({ data }) => setFunnel(data));
    db.from("partner_commissions").select("*, businesses(name)").eq("partner_id", id).order("created_at", { ascending: false })
      .then(({ data }) => setSales(data ?? []));
    db.from("partner_payouts").select("*").eq("partner_id", id).order("paid_on", { ascending: false })
      .then(({ data }) => setPayouts(data ?? []));
  }, [id, refresh]);

  if (partner === undefined) return <Spinner />;
  if (!partner) return <p className="text-sm text-zinc-500">Partner not found. <Link href="/influencers?tab=partners" className="font-semibold text-brand hover:underline">Back to partners</Link></p>;

  const reload = () => setRefresh((n) => n + 1);
  const payable = Number(partner.payable);
  const net = Number(partner.net);
  const clicks = Number(partner.clicks);
  const signups = Number(partner.signups);
  const paidShops = Number(partner.paid_shops);
  const about = [partner.followers != null ? `${Number(partner.followers).toLocaleString("en-IN")} followers` : "", partner.niche, partner.language, partner.city].filter(Boolean).join(" · ");

  async function copy(text: string, what: string) {
    try {
      await navigator.clipboard.writeText(text);
      setNotice({ ok: true, text: `${what} copied.` });
    } catch {
      setNotice({ ok: false, text });
    }
  }

  async function newLink() {
    if (!window.confirm(`Make a new stats link for ${partner.name}? The old one stops working.`)) return;
    const { data, error } = await createClient().rpc("admin_new_partner_link", { p_partner: partner.id });
    if (error) return setNotice({ ok: false, text: error.message });
    copy(`https://www.dukania.in/partner/${data}`, "New stats link");
    reload();
  }

  const invite = `Namaste ${partner.name}! Your Dukania partner link: ${linkOf(partner)} — your code ${partner.code} gives shops ` +
    `${Number(partner.buyer_off_pct)}% off. Your numbers and earnings: ${statsOf(partner)} (keep this link private). Dukania`;

  return (
    <div className="space-y-6">
      <Link href="/influencers?tab=partners" className="inline-flex items-center gap-1.5 text-sm font-semibold text-zinc-600 hover:text-ink">
        <ArrowLeft size={15} /> Partners
      </Link>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <PageHeader title={partner.name} subtitle={[partner.handle, about].filter(Boolean).join(" · ") || partner.code} />
        <div className="flex flex-wrap gap-2">
          {canPay && payable > 0 && <Button onClick={() => setPaying(true)}>Pay {inr(payable)}</Button>}
          {canMarket && <Button variant="outline" onClick={() => setEditing(editingFrom(partner))}>Edit</Button>}
        </div>
      </div>
      <Notice notice={notice} />
      <div className="flex flex-wrap gap-2">
        {!partner.active && <Badge>Off</Badge>}
        {isQuiet(partner) && <Badge color="orange">No clicks in 30 days</Badge>}
        {partner.payout_request && <Badge color="orange">Payout requested: {inr(partner.payout_request.amount)}</Badge>}
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="You made" value={inr(net)} hint="First payments less commission and fees" />
        <StatCard label="First payments" value={inr(partner.revenue)} hint="Before GST, after refunds" />
        <StatCard label="Commission" value={inr(partner.earned)} hint={`${inr(partner.paid)} paid out`} />
        <StatCard label="Fixed fees" value={inr(partner.fees)} />
      </div>

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">From click to sale</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
            {[
              ["Clicks", clicks, ""],
              ["Joined", signups, `${pct(signups, clicks)} of clicks`],
              ["On trial", funnel?.on_trial ?? "—", ""],
              ["Trial ended", funnel?.trial_ended ?? "—", "Didn't buy yet"],
              ["Paid", paidShops, `${pct(paidShops, signups)} of joined`],
            ].map(([label, value, hint]) => (
              <div key={label as string} className="rounded-lg bg-zinc-50 p-3">
                <p className="text-xs text-zinc-500">{label}</p>
                <p className="text-xl font-semibold tabular-nums text-ink">{value}</p>
                {hint && <p className="text-xs text-zinc-500">{hint}</p>}
              </div>
            ))}
          </div>
          {funnel?.months && (
            <div className="mt-4">
              <Table headers={["Month", "Clicks", "Joined", "Paid", "Commission"]}>
                {funnel.months.map((m: any) => (
                  <tr key={m.month}>
                    <td className="px-4 py-2">{new Date(m.month).toLocaleDateString("en-IN", { month: "short", year: "numeric" })}</td>
                    <td className="px-4 py-2 tabular-nums">{m.clicks}</td>
                    <td className="px-4 py-2 tabular-nums">{m.signups}</td>
                    <td className="px-4 py-2 tabular-nums">{m.paid_shops}</td>
                    <td className="px-4 py-2 tabular-nums">{inr(m.earned)}</td>
                  </tr>
                ))}
              </Table>
            </div>
          )}
        </CardBody>
      </Card>

      <PostsAndFees partner={partner} onChange={reload} />

      <Card>
        <CardBody className="space-y-3 text-sm">
          <h2 className="font-semibold text-zinc-700">Shops that paid</h2>
          {!sales ? <Spinner /> : sales.length === 0 ? (
            <p className="text-zinc-500">No paid shops yet. {signups} joined with the code.</p>
          ) : (
            <Table headers={["Shop", "Paid", "Commission", "Payable", ""]}>
              {sales.map((c) => {
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
          {payouts.length > 0 && (
            <div className="pt-2">
              <h2 className="mb-2 font-semibold text-zinc-700">Payouts</h2>
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
        </CardBody>
      </Card>

      <Card>
        <CardBody className="space-y-3 text-sm">
          <h2 className="font-semibold text-zinc-700">Their link, stats page and login</h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div className="rounded-lg bg-zinc-50 p-3">
              <p className="text-xs text-zinc-500">Their link (for posts and bio)</p>
              <p className="break-all font-mono font-semibold">{linkOf(partner)}</p>
              <Button variant="outline" className="mt-2" onClick={() => copy(linkOf(partner), "Link")}>Copy</Button>
            </div>
            <div className="rounded-lg bg-zinc-50 p-3">
              <p className="text-xs text-zinc-500">Their private stats page</p>
              <p className="break-all font-mono text-xs">{statsOf(partner)}</p>
              <div className="mt-2 flex gap-2">
                <Button variant="outline" onClick={() => copy(statsOf(partner), "Stats link")}>Copy</Button>
                {canMarket && <Button variant="ghost" onClick={newLink}>New link</Button>}
              </div>
            </div>
          </div>
          <PartnerLogin key={partner.id} partner={partner} canEdit={canMarket} />
          {partner.phone && (
            <a href={waLink(partner.phone, invite)} target="_blank" rel="noreferrer"><Button>Send link and code on WhatsApp</Button></a>
          )}
        </CardBody>
      </Card>

      {editing && (
        <PartnerForm editing={editing} setEditing={setEditing} onClose={() => setEditing(null)}
          onDone={(text) => { setEditing(null); setNotice({ ok: true, text }); reload(); }} />
      )}
      {paying && <PayDialog partner={partner} onClose={() => setPaying(false)}
        onDone={(text) => { setPaying(false); setNotice({ ok: true, text }); reload(); }} />}
    </div>
  );
}
