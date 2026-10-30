"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { dateStr, inr } from "@/lib/format";
import { PayDialog } from "./shared";

/* eslint-disable @typescript-eslint/no-explicit-any */

const istToday = () => new Date(Date.now() + 5.5 * 3600000).toISOString().slice(0, 10);

/** The April of a financial year: "2026" is 1 Apr 2026 to 31 Mar 2027. */
function currentFy() {
  const d = istToday();
  return Number(d.slice(0, 4)) - (Number(d.slice(5, 7)) < 4 ? 1 : 0);
}

function downloadCsv(name: string, rows: (string | number)[][]) {
  const cell = (v: string | number) => {
    const s = String(v ?? "");
    // A leading =, +, - or @ would run as a formula in Excel.
    const safe = /^[=+\-@]/.test(s) ? `'${s}` : s;
    return `"${safe.replace(/"/g, '""')}"`;
  };
  const blob = new Blob(["﻿" + rows.map((r) => r.map(cell).join(",")).join("\r\n")], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * Paying influencers (migration 0110): requests and others ready to pay,
 * declines with a reason, PAN, and the payouts of a financial year with TDS
 * held and deposited. Payments area only: it shows the PAN.
 */
export function Payouts() {
  const [fy, setFy] = useState(currentFy());
  const [data, setData] = useState<any>(null);
  const [paying, setPaying] = useState<any>(null);
  const [declining, setDeclining] = useState<any>(null);
  const [panFor, setPanFor] = useState<any>(null);
  const [deposit, setDeposit] = useState<any>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    createClient().rpc("admin_partner_payouts", { p_from: `${fy}-04-01`, p_to: `${fy + 1}-03-31` }).then(({ data: d, error }) => {
      if (error) setNotice({ ok: false, text: error.message.includes("admin_partner_payouts") ? "Migration 0110 isn't applied to this database yet." : error.message });
      setData(d ?? { partners: [], declined: [], payouts: [] });
    });
  }, [fy, refresh]);

  if (!data) return <Spinner />;
  const reload = () => setRefresh((n) => n + 1);
  const payouts: any[] = data.payouts;
  const requests = data.partners.filter((p: any) => p.request_id);
  const ready = data.partners.filter((p: any) => !p.request_id);
  const held = payouts.reduce((s, o) => s + Number(o.tds), 0);
  const toDeposit = payouts.filter((o) => Number(o.tds) > 0 && !o.tds_deposited_on).reduce((s, o) => s + Number(o.tds), 0);

  async function copy(text: string) {
    try {
      await navigator.clipboard.writeText(text);
      setNotice({ ok: true, text: `${text} copied.` });
    } catch {
      setNotice({ ok: false, text });
    }
  }

  function exportCsv() {
    downloadCsv(`influencer-payouts-${fy}-${String(fy + 1).slice(2)}.csv`, [
      ["Date", "Partner", "Code", "PAN", "Commission", "TDS", "Paid to them", "Paid by", "Reference", "TDS deposited on", "Challan"],
      ...payouts.map((o) => [o.paid_on, o.name, o.code, o.pan ?? "", Number(o.amount), Number(o.tds), Number(o.net), o.mode, o.reference, o.tds_deposited_on ?? "", o.tds_challan]),
    ]);
  }

  const row = (p: any) => {
    const payable = Number(p.payable);
    const changed = p.request_id && Number(p.requested) !== payable;
    return (
      <tr key={p.id}>
        <td className="px-4 py-3">
          <Link href={`/influencers/${p.id}`} className="font-semibold text-ink hover:underline">{p.name}</Link>
          <span className="block font-mono text-xs text-zinc-500">{p.code}</span>
          {p.requested_at && <span className="block text-xs text-zinc-500">Asked {dateStr(p.requested_at)}</span>}
        </td>
        <td className="px-4 py-3 tabular-nums">
          <b className="text-ink">{inr(payable)}</b>
          {changed && <span className="block text-xs text-amber-700">They asked for {inr(p.requested)}; it changed after a sale or refund</span>}
        </td>
        <td className="px-4 py-3">
          {p.upi_id ? <button onClick={() => copy(p.upi_id)} className="font-mono text-xs font-semibold text-brand hover:underline">{p.upi_id}</button> : <span className="text-xs text-red-600">No UPI ID</span>}
        </td>
        <td className="px-4 py-3">
          <button onClick={() => setPanFor(p)} className="font-mono text-xs font-semibold text-brand hover:underline">{p.pan || "Add PAN"}</button>
        </td>
        <td className="px-4 py-3">
          <div className="flex flex-wrap justify-end gap-2">
            {payable > 0 && <Button onClick={() => setPaying(p)}>Pay</Button>}
            {p.request_id && <Button variant="outline" onClick={() => setDeclining(p)}>Decline</Button>}
          </div>
        </td>
      </tr>
    );
  };

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Requests" value={requests.length} hint={inr(requests.reduce((s: number, p: any) => s + Number(p.payable), 0))} />
        <StatCard label="Also ready to pay" value={ready.length} hint={inr(ready.reduce((s: number, p: any) => s + Number(p.payable), 0))} />
        <StatCard label="TDS held this year" value={inr(held)} />
        <StatCard label="TDS to deposit" value={inr(toDeposit)} hint="Held and not marked deposited" />
      </div>

      <Card>
        <CardBody className="space-y-3">
          <h2 className="text-sm font-semibold text-zinc-700">Payout requests</h2>
          {requests.length === 0 ? <p className="text-sm text-zinc-500">No one is waiting. Requests show here, and in the alerts bell.</p> : (
            <Table headers={["Partner", "Pay now", "UPI ID", "PAN", ""]}>{requests.map(row)}</Table>
          )}
        </CardBody>
      </Card>

      {ready.length > 0 && (
        <Card>
          <CardBody className="space-y-3">
            <h2 className="text-sm font-semibold text-zinc-700">Ready to pay, not asked yet</h2>
            <Table headers={["Partner", "Pay now", "UPI ID", "PAN", ""]}>{ready.map(row)}</Table>
          </CardBody>
        </Card>
      )}

      <Card>
        <CardBody className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-semibold text-zinc-700">Payouts and TDS</h2>
            <div className="flex items-center gap-2">
              <Select value={fy} onChange={(e) => setFy(Number(e.target.value))} aria-label="Financial year" className="!w-32">
                {[0, 1, 2].map((n) => <option key={n} value={currentFy() - n}>FY {currentFy() - n}-{String(currentFy() - n + 1).slice(2)}</option>)}
              </Select>
              <Button variant="outline" disabled={payouts.length === 0} onClick={exportCsv}>Download CSV</Button>
            </div>
          </div>
          {payouts.length === 0 ? <p className="text-sm text-zinc-500">No payouts in this year.</p> : (
            <Table headers={["Date", "Partner", "Commission", "TDS", "Paid to them", "Reference", "TDS deposit"]}>
              {payouts.map((o) => (
                <tr key={o.id}>
                  <td className="whitespace-nowrap px-4 py-3">{dateStr(o.paid_on)}</td>
                  <td className="px-4 py-3">
                    <Link href={`/influencers/${o.partner_id}`} className="font-semibold text-ink hover:underline">{o.name}</Link>
                    <span className="block font-mono text-xs text-zinc-500">{o.pan || "No PAN"}</span>
                  </td>
                  <td className="px-4 py-3 tabular-nums">{inr(o.amount)}</td>
                  <td className="px-4 py-3 tabular-nums">{Number(o.tds) > 0 ? inr(o.tds) : "—"}</td>
                  <td className="px-4 py-3 font-semibold tabular-nums">{inr(o.net)}</td>
                  <td className="px-4 py-3 font-mono text-xs">{o.reference || o.mode}</td>
                  <td className="px-4 py-3">
                    {Number(o.tds) <= 0 ? "—" : (
                      <button onClick={() => setDeposit(o)} className="text-left">
                        {o.tds_deposited_on ? <Badge color="green">{dateStr(o.tds_deposited_on)}</Badge> : <Badge color="orange">Mark deposited</Badge>}
                        {o.tds_challan && <span className="mt-1 block font-mono text-xs text-zinc-500">{o.tds_challan}</span>}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </Table>
          )}
        </CardBody>
      </Card>

      {data.declined.length > 0 && (
        <Card>
          <CardBody className="space-y-2">
            <h2 className="text-sm font-semibold text-zinc-700">Recently declined</h2>
            <ul className="divide-y divide-zinc-100 text-sm">
              {data.declined.map((d: any) => (
                <li key={d.id} className="py-2">
                  <b className="text-ink">{d.name}</b> · {inr(d.amount)} · {dateStr(d.closed_at)}
                  <span className="block text-xs text-zinc-500">{d.decline_reason}</span>
                </li>
              ))}
            </ul>
          </CardBody>
        </Card>
      )}

      {paying && <PayDialog partner={paying} onClose={() => setPaying(null)}
        onDone={(text) => { setPaying(null); setNotice({ ok: true, text }); reload(); }} />}
      {declining && <DeclineDialog partner={declining} onClose={() => setDeclining(null)}
        onDone={(text) => { setNotice({ ok: true, text }); reload(); }} />}
      {panFor && <PanDialog partner={panFor} onClose={() => setPanFor(null)}
        onDone={() => { setPanFor(null); reload(); }} />}
      {deposit && <DepositDialog payout={deposit} onClose={() => setDeposit(null)}
        onDone={() => { setDeposit(null); reload(); }} />}
    </div>
  );
}

function DeclineDialog({ partner, onClose, onDone }: { partner: any; onClose: () => void; onDone: (text: string) => void }) {
  const [reason, setReason] = useState("");
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function decline() {
    const { error: e } = await createClient().rpc("admin_decline_payout_request", { p_id: partner.request_id, p_reason: reason });
    if (e) return setError(e.message);
    setDone(true);
    onDone(`${partner.name}'s request is declined. They see the reason on their page and can ask again.`);
  }

  const message = `Namaste ${partner.name}! We couldn't pay your Dukania payout request yet: ${reason.trim()}. You can ask again from your partner page once this is sorted. Dukania`;

  return (
    <Modal title={`Decline ${partner.name}'s request?`} onClose={onClose}>
      {done ? (
        <div className="flex justify-end gap-2">
          {partner.phone && <a href={waLink(partner.phone, message)} target="_blank" rel="noreferrer"><Button>Tell them on WhatsApp</Button></a>}
          <Button variant="ghost" onClick={onClose}>Close</Button>
        </div>
      ) : (
        <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); decline(); }}>
          {error && <p className="font-medium text-red-600">{error}</p>}
          <div>
            <Label>Reason (they will see this)</Label>
            <Input required autoFocus value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Your UPI ID didn't work — please check it" />
          </div>
          <p className="text-xs text-zinc-500">Their commission stays ready to pay. Nothing is taken away.</p>
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>Cancel</Button>
            <Button type="submit" variant="danger" disabled={!reason.trim()}>Decline</Button>
          </div>
        </form>
      )}
    </Modal>
  );
}

function PanDialog({ partner, onClose, onDone }: { partner: any; onClose: () => void; onDone: () => void }) {
  const [pan, setPan] = useState<string>(partner.pan ?? "");
  const [error, setError] = useState<string | null>(null);

  async function save() {
    const { error: e } = await createClient().rpc("admin_set_partner_pan", { p_partner: partner.id, p_pan: pan });
    if (e) return setError(e.message);
    onDone();
  }

  return (
    <Modal title={`${partner.name}'s PAN`} onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
        {error && <p className="font-medium text-red-600">{error}</p>}
        <div>
          <Label>PAN (empty removes it)</Label>
          <Input autoFocus value={pan} maxLength={10} className="font-mono" placeholder="ABCDE1234F" onChange={(e) => setPan(e.target.value.toUpperCase())} />
        </div>
        <p className="text-xs text-zinc-500">Only team members with Payments can see it. Partners can also add it on their own page.</p>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit">Save</Button>
        </div>
      </form>
    </Modal>
  );
}

function DepositDialog({ payout, onClose, onDone }: { payout: any; onClose: () => void; onDone: () => void }) {
  const [on, setOn] = useState<string>(payout.tds_deposited_on ?? istToday());
  const [challan, setChallan] = useState<string>(payout.tds_challan ?? "");
  const [error, setError] = useState<string | null>(null);

  async function save(depositedOn: string) {
    const { error: e } = await createClient().rpc("admin_set_tds_deposit", {
      p_payout: payout.id, p: { deposited_on: depositedOn, challan },
    });
    if (e) return setError(e.message);
    onDone();
  }

  return (
    <Modal title={`TDS of ${inr(payout.tds)} — ${payout.name}`} onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(on); }}>
        {error && <p className="font-medium text-red-600">{error}</p>}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <Label>Deposited on</Label>
            <Input type="date" required value={on} onChange={(e) => setOn(e.target.value)} />
          </div>
          <div>
            <Label>Challan number</Label>
            <Input value={challan} onChange={(e) => setChallan(e.target.value)} className="font-mono" />
          </div>
        </div>
        <p className="text-xs text-zinc-500">This only notes the deposit. Dukania doesn&apos;t pay or file TDS for you.</p>
        <div className="flex justify-end gap-2">
          {payout.tds_deposited_on && <Button variant="ghost" onClick={() => save("")}>Not deposited</Button>}
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit">Save</Button>
        </div>
      </form>
    </Modal>
  );
}
