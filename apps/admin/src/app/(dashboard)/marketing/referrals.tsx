"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Notice, waLink } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

/**
 * Referrals (migration 0101): every shop has a code; a shop that joins
 * with it and pays earns the referrer free months. Rewards wait here until
 * someone with Payments gives them (the plan is extended) or skips them.
 */
export function Referrals() {
  const [shops, setShops] = useState<any[] | null>(null);
  const [rewards, setRewards] = useState<any[]>([]);
  const [months, setMonths] = useState("1");
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [linkShop, setLinkShop] = useState("");
  const [linkCode, setLinkCode] = useState("");
  const canPay = useCan("payments");

  useEffect(() => {
    const db = createClient();
    db.from("businesses").select("id, name, owner_name, phone, referral_code, referred_by, referred_at, created_at").order("name")
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setShops(data ?? []);
      });
    db.from("referral_rewards").select("*").order("created_at", { ascending: false })
      .then(({ data }) => setRewards(data ?? []));
    db.from("platform_settings").select("referral_reward_months").eq("id", 1).maybeSingle()
      .then(({ data }) => data && setMonths(String(data.referral_reward_months ?? 1)));
  }, [refresh]);

  if (!shops) return <Spinner />;
  const byId = new Map(shops.map((s) => [s.id, s]));
  const referred = shops.filter((s) => s.referred_by);
  const counts = new Map<string, number>();
  for (const s of referred) counts.set(s.referred_by, (counts.get(s.referred_by) ?? 0) + 1);
  const top = [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
  const pending = rewards.filter((r) => r.status === "pending");

  async function saveMonths() {
    const { error } = await createClient().rpc("admin_set_referral_months", { p_months: Number(months) });
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: `A shop now earns ${months} free month${months === "1" ? "" : "s"} per paying friend.` });
  }

  async function give(r: any, yes: boolean) {
    const { data, error } = await createClient().rpc("admin_give_referral_reward", { p_id: r.id, p_give: yes });
    if (error) return setNotice({ ok: false, text: error.message });
    const name = byId.get(r.referrer_id)?.name ?? "The shop";
    setNotice({ ok: true, text: yes ? `${name}'s plan now runs until ${dateStr((data as any)?.until)}.` : "Reward skipped." });
    setRefresh((n) => n + 1);
  }

  async function link() {
    const { data, error } = await createClient().rpc("admin_set_referrer", { p_business: linkShop, p_code: linkCode });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: data ? `Linked: referred by ${data}.` : "Referrer removed." });
    setLinkCode("");
    setRefresh((n) => n + 1);
  }

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Shops that joined by referral" value={referred.length} />
        <StatCard label="Rewards earned" value={rewards.length} hint={`${pending.length} waiting`} />
        <StatCard label="Free months given" value={rewards.filter((r) => r.status === "given").reduce((s, r) => s + r.months, 0)} />
        <StatCard label="Shops referring" value={counts.size} />
      </div>

      <Card>
        <CardBody className="flex flex-wrap items-end gap-3">
          <div>
            <Label>Free months for each friend who pays</Label>
            <Input type="number" min={0} max={12} value={months} onChange={(e) => setMonths(e.target.value)} className="w-28" />
          </div>
          <Button variant="outline" onClick={saveMonths}>Save</Button>
          <p className="text-xs text-zinc-500">0 turns rewards off. Shops see their code and what they&apos;ve earned on the app&apos;s Plan screen.</p>
        </CardBody>
      </Card>

      <Card>
        <CardBody>
          <h2 className="mb-3 text-sm font-semibold text-zinc-700">Rewards waiting</h2>
          {pending.length === 0 ? (
            <p className="text-sm text-zinc-500">None waiting.</p>
          ) : (
            <Table headers={["Shop to reward", "Because this shop paid", "Earned", ""]}>
              {pending.map((r) => {
                const shop = byId.get(r.referrer_id);
                return (
                  <tr key={r.id}>
                    <td className="px-4 py-3">
                      <Link href={`/clients/${r.referrer_id}`} className="font-semibold text-ink hover:underline">{shop?.name ?? "—"}</Link>
                    </td>
                    <td className="px-4 py-3">{byId.get(r.referred_id)?.name ?? "—"} · {dateStr(r.created_at)}</td>
                    <td className="px-4 py-3">{r.months} month{r.months === 1 ? "" : "s"} free</td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap justify-end gap-2">
                        {canPay ? (
                          <>
                            <Button onClick={() => give(r, true)}>Give {r.months} month{r.months === 1 ? "" : "s"}</Button>
                            <Button variant="ghost" onClick={() => give(r, false)}>Skip</Button>
                          </>
                        ) : (
                          <span className="text-xs text-zinc-500">Someone with Payments gives it</span>
                        )}
                        {shop?.phone && (
                          <a href={waLink(shop.phone, `Namaste ${shop.owner_name || ""}! ${byId.get(r.referred_id)?.name ?? "A shop"} joined Dukania with your code — thank you! You get ${r.months} month${r.months === 1 ? "" : "s"} free. — Dukania`)}
                            target="_blank" rel="noreferrer">
                            <Button variant="outline">WhatsApp</Button>
                          </a>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </Table>
          )}
        </CardBody>
      </Card>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <Card>
          <CardBody>
            <h2 className="mb-3 text-sm font-semibold text-zinc-700">Top referrers</h2>
            {top.length === 0 ? (
              <p className="text-sm text-zinc-500">No referrals yet.</p>
            ) : (
              <ul className="divide-y divide-zinc-100">
                {top.map(([id, n]) => (
                  <li key={id} className="flex items-center justify-between py-2 text-sm">
                    <Link href={`/clients/${id}`} className="font-semibold text-ink hover:underline">{byId.get(id)?.name ?? "—"}</Link>
                    <span className="flex items-center gap-2">
                      <span className="font-mono text-xs text-zinc-500">{byId.get(id)?.referral_code}</span>
                      <Badge color="purple">{n} shop{n === 1 ? "" : "s"}</Badge>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardBody>
        </Card>

        <Card>
          <CardBody className="space-y-3">
            <h2 className="text-sm font-semibold text-zinc-700">A shop told you who referred it</h2>
            <Select value={linkShop} onChange={(e) => setLinkShop(e.target.value)} aria-label="Shop">
              <option value="">Choose the shop that joined…</option>
              {shops.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}{s.referred_by ? ` (referred by ${byId.get(s.referred_by)?.name ?? "?"})` : ""}
                </option>
              ))}
            </Select>
            <div className="flex gap-2">
              <Input value={linkCode} onChange={(e) => setLinkCode(e.target.value.toUpperCase())} placeholder="The referrer's code, e.g. DKAB2CD (empty = remove)" />
              <Button variant="outline" onClick={link} disabled={!linkShop}>Save</Button>
            </div>
            <p className="text-xs text-zinc-500">Shops can also enter a code themselves on the app&apos;s Plan screen in their first 30 days.</p>
          </CardBody>
        </Card>
      </div>
    </div>
  );
}
