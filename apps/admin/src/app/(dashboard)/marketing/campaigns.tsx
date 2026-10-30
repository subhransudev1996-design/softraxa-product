"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Notice } from "@/components/ops";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const CHANNELS = ["facebook", "instagram", "google", "youtube", "whatsapp", "newspaper", "pamphlet", "event", "other"];
const SITE = "https://www.dukania.in";

/**
 * Campaigns (migration 0101): what each one cost, and the leads, sales and
 * money it brought. A lead belongs to a campaign by its Campaign field —
 * typed by the team, or filled in by the website when the visitor came
 * through a campaign link (below).
 */
export function Campaigns() {
  const [report, setReport] = useState<any[] | null>(null);
  const [costs, setCosts] = useState<any[]>([]);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [form, setForm] = useState({ campaign: "", channel: "facebook", amount: "", spent_on: "", note: "" });
  const [link, setLink] = useState({ campaign: "", channel: "facebook" });
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const db = createClient();
    db.rpc("admin_campaign_report").then(({ data, error }) => {
      if (error) setNotice({ ok: false, text: error.message });
      setReport((data as any[]) ?? []);
    });
    db.from("campaign_costs").select("*").order("spent_on", { ascending: false }).limit(200)
      .then(({ data }) => setCosts(data ?? []));
  }, [refresh]);

  async function addCost(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await createClient().from("campaign_costs").insert({
      campaign: form.campaign.trim(), channel: form.channel, amount: Number(form.amount),
      spent_on: form.spent_on || new Date().toISOString().slice(0, 10), note: form.note.trim(),
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setForm({ ...form, amount: "", note: "" });
    setRefresh((n) => n + 1);
  }

  async function removeCost(c: any) {
    if (!window.confirm(`Delete ${inr(c.amount)} for "${c.campaign}"?`)) return;
    const { error } = await createClient().from("campaign_costs").delete().eq("id", c.id);
    if (error) return setNotice({ ok: false, text: error.message });
    setRefresh((n) => n + 1);
  }

  if (!report) return <Spinner />;
  const spend = report.reduce((s, r) => s + Number(r.spend), 0);
  const money = report.reduce((s, r) => s + Number(r.money), 0);
  const won = report.reduce((s, r) => s + Number(r.won), 0);
  const leads = report.reduce((s, r) => s + Number(r.leads), 0);
  const url = link.campaign.trim()
    ? `${SITE}/?utm_source=${encodeURIComponent(link.channel)}&utm_campaign=${encodeURIComponent(link.campaign.trim())}`
    : "";

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Spent on campaigns" value={inr(spend)} />
        <StatCard label="Leads from campaigns" value={leads} hint={leads && spend ? `${inr(spend / leads)} a lead` : undefined} />
        <StatCard label="Sales" value={won} hint={won && spend ? `${inr(spend / won)} a sale` : undefined} />
        <StatCard label="Money from those shops" value={inr(money)} hint={spend ? `${(money / spend).toFixed(1)}× what was spent` : undefined} />
      </div>

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">By campaign</h2>
          {report.length === 0 ? (
            <p className="text-sm text-zinc-500">No campaigns yet. Add a cost below, or give leads a Campaign.</p>
          ) : (
            <Table headers={["Campaign", "Spent", "Leads", "Won", "Money", "Per lead", "Per sale", "Return"]}>
              {report.map((r) => {
                const s = Number(r.spend);
                return (
                  <tr key={r.campaign}>
                    <td className="px-4 py-2.5 font-medium">
                      {r.campaign}
                      {r.first_spend && <span className="block text-xs text-zinc-500">since {dateStr(r.first_spend)}</span>}
                    </td>
                    <td className="px-4 py-2.5 tabular-nums">{s ? inr(s) : "—"}</td>
                    <td className="px-4 py-2.5 tabular-nums">{r.leads}</td>
                    <td className="px-4 py-2.5 tabular-nums text-emerald-700">{r.won}</td>
                    <td className="px-4 py-2.5 tabular-nums">{inr(r.money)}</td>
                    <td className="px-4 py-2.5 tabular-nums">{s && r.leads ? inr(s / r.leads) : "—"}</td>
                    <td className="px-4 py-2.5 tabular-nums">{s && r.won ? inr(s / r.won) : "—"}</td>
                    <td className={`px-4 py-2.5 font-semibold tabular-nums ${s && Number(r.money) >= s ? "text-emerald-700" : "text-zinc-700"}`}>
                      {s ? `${(Number(r.money) / s).toFixed(1)}×` : "—"}
                    </td>
                  </tr>
                );
              })}
            </Table>
          )}
          <p className="mt-2 text-xs text-zinc-500">Money = everything the won shops have paid so far. Return = money ÷ spent.</p>
        </CardBody>
      </Card>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Add a cost</h2>
            <form onSubmit={addCost} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="sm:col-span-2">
                <Label>Campaign</Label>
                <Input required list="campaign-names" value={form.campaign} onChange={(e) => setForm({ ...form, campaign: e.target.value })} placeholder="e.g. Diwali Facebook ad" />
                <datalist id="campaign-names">
                  {report.map((r) => <option key={r.campaign} value={r.campaign} />)}
                </datalist>
              </div>
              <div>
                <Label>Where</Label>
                <Select value={form.channel} onChange={(e) => setForm({ ...form, channel: e.target.value })}>
                  {CHANNELS.map((c) => <option key={c} value={c}>{c}</option>)}
                </Select>
              </div>
              <div>
                <Label>Amount ₹</Label>
                <Input required type="number" min={0} value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} />
              </div>
              <div>
                <Label>Spent on</Label>
                <Input type="date" value={form.spent_on} onChange={(e) => setForm({ ...form, spent_on: e.target.value })} />
              </div>
              <div>
                <Label>Note</Label>
                <Input value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
              </div>
              <div className="sm:col-span-2">
                <Button type="submit" disabled={!form.campaign.trim() || !form.amount}>Add cost</Button>
              </div>
            </form>
          </CardBody>
        </Card>

        <Card>
          <CardBody className="space-y-3">
            <h2 className="text-sm font-semibold text-zinc-700">Campaign link for the website</h2>
            <p className="text-xs text-zinc-500">
              Use this link in the ad or post. Anyone who comes through it and sends the website&apos;s contact form becomes
              a lead with this campaign.
            </p>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Input value={link.campaign} onChange={(e) => setLink({ ...link, campaign: e.target.value })} placeholder="Campaign name" list="campaign-names" />
              <Select value={link.channel} onChange={(e) => setLink({ ...link, channel: e.target.value })}>
                {CHANNELS.map((c) => <option key={c} value={c}>{c}</option>)}
              </Select>
            </div>
            {url && (
              <>
                <p className="break-all rounded-md bg-zinc-50 p-3 font-mono text-xs text-zinc-700">{url}</p>
                <Button variant="outline" onClick={async () => {
                  try { await navigator.clipboard.writeText(url); setCopied(true); setTimeout(() => setCopied(false), 1500); }
                  catch { window.prompt("Copy this link:", url); }
                }}>{copied ? "Copied" : "Copy link"}</Button>
              </>
            )}
          </CardBody>
        </Card>
      </div>

      {costs.length > 0 && (
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Costs</h2>
            <Table headers={["Date", "Campaign", "Where", "Amount", "Note", ""]}>
              {costs.map((c) => (
                <tr key={c.id}>
                  <td className="px-4 py-2.5">{dateStr(c.spent_on)}</td>
                  <td className="px-4 py-2.5">{c.campaign}</td>
                  <td className="px-4 py-2.5 capitalize">{c.channel}</td>
                  <td className="px-4 py-2.5 tabular-nums">{inr(c.amount)}</td>
                  <td className="px-4 py-2.5 text-zinc-500">{c.note}</td>
                  <td className="px-4 py-2.5 text-right"><Button variant="ghost" onClick={() => removeCost(c)}>Delete</Button></td>
                </tr>
              ))}
            </Table>
          </CardBody>
        </Card>
      )}
    </div>
  );
}
