"use client";

import { Children, ReactNode, useEffect, useState } from "react";
import Link from "next/link";
import { AlertTriangle, BadgeCheck, CheckCircle2, Clock, IndianRupee, Inbox, Moon, Sparkles, Store, UserRoundPlus, Users } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, Input, Spinner, StatCard } from "@/components/ui";
import { Modal, Notice, RenewDialog, RenewTarget, waLink } from "@/components/ops";
import { useCan, useMe } from "@/components/me";
import { stageLabel } from "@/lib/leads";
import { dateStr, dateTimeStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Today = {
  today: string;
  claims: any[];
  expiring: any[];
  expired: any[];
  tickets: any[];
  open_tickets: number;
  setup: any[];
  inactive: any[];
  reconciliation: { run_id: string; finished_at: string | null; issues: number; unexplained: number } | null;
  followups: any[];
};

const daysFrom = (today: string, date: string) =>
  Math.round((new Date(`${date}T00:00:00`).getTime() - new Date(`${today}T00:00:00`).getTime()) / 86400000);

/** One group of things to do; hidden when empty. */
const TONES: Record<string, { band: string; icon: ReactNode }> = {
  red: { band: "bg-red-50 text-red-700", icon: <AlertTriangle size={15} /> },
  orange: { band: "bg-amber-50 text-amber-700", icon: <Clock size={15} /> },
  blue: { band: "bg-blue-50 text-blue-700", icon: <BadgeCheck size={15} /> },
  purple: { band: "bg-brand-tint text-brand-deep", icon: <Sparkles size={15} /> },
  zinc: { band: "bg-zinc-100 text-zinc-600", icon: <Moon size={15} /> },
};

const FIRST_ROWS = 5;

/** One group of things to do, longest lists folded; hidden when empty. */
function Group({ title, count, tone = "zinc", children }: { title: string; count: number; tone?: string; children: ReactNode }) {
  const [all, setAll] = useState(false);
  if (count === 0) return null;
  const rows = Children.toArray(children);
  const { band, icon } = TONES[tone] ?? TONES.zinc;
  return (
    <Card className="overflow-hidden">
      <div className="flex items-center gap-2.5 border-b border-zinc-100 px-5 py-3">
        <span className={`grid h-7 w-7 shrink-0 place-items-center rounded-lg ${band}`}>{icon}</span>
        <h2 className="text-sm font-bold text-ink">{title}</h2>
        <span className="ml-auto text-sm font-semibold tabular-nums text-zinc-500">{count}</span>
      </div>
      <ul className="divide-y divide-zinc-100 px-5">{all ? rows : rows.slice(0, FIRST_ROWS)}</ul>
      {rows.length > FIRST_ROWS && (
        <button onClick={() => setAll(!all)} className="w-full cursor-pointer border-t border-zinc-100 py-2.5 text-sm font-semibold text-brand transition-colors hover:bg-zinc-50">
          {all ? "Show fewer" : `Show all ${rows.length}`}
        </button>
      )}
    </Card>
  );
}

function Row({ main, sub, actions }: { main: ReactNode; sub?: ReactNode; actions: ReactNode }) {
  return (
    <li className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between">
      <div className="min-w-0">
        <div className="font-semibold text-ink">{main}</div>
        {sub && <div className="text-xs text-zinc-500">{sub}</div>}
      </div>
      <div className="flex shrink-0 flex-wrap gap-2">{actions}</div>
    </li>
  );
}

export default function TodayPage() {
  const supabase = createClient();
  const [data, setData] = useState<Today | null>(null);
  const [stats, setStats] = useState<any>(null);
  const [upi, setUpi] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [renew, setRenew] = useState<RenewTarget | null>(null);
  const [reject, setReject] = useState<any>(null);
  const [reason, setReason] = useState("");
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [staffAsks, setStaffAsks] = useState<any[]>([]);
  const [complaints, setComplaints] = useState<any[]>([]);
  const [rewards, setRewards] = useState<any[]>([]);
  const [callsDue, setCallsDue] = useState<any[]>([]);
  const [myTasks, setMyTasks] = useState<any[]>([]);
  const me = useMe();
  const [atRisk, setAtRisk] = useState<any[]>([]);
  // Renewing and money are for the people with payments (0098).
  const canPay = useCan("payments");

  useEffect(() => {
    supabase.rpc("get_admin_today").then(({ data, error }) => {
      if (error) setError(error.message);
      else setData(data as Today);
    });
    supabase.rpc("get_admin_dashboard").then(({ data }) => setStats(data));
    // Shops asking for more staff logins (migration 0097).
    supabase.from("support_tickets").select("id, business_id, requested_staff, created_at, businesses(name, phone, owner_name)")
      .not("requested_staff", "is", null).neq("status", "resolved").order("created_at")
      .then(({ data, error }) => setStaffAsks(error ? [] : data ?? []));
    // Complaints not yet resolved, first of all (migration 0099).
    supabase.from("support_tickets").select("id, subject, priority, created_at, businesses(name)")
      .eq("kind", "complaint").neq("status", "resolved").order("created_at")
      .then(({ data, error }) => setComplaints(error ? [] : data ?? []));
    // Referral rewards earned and not yet given (migration 0101).
    supabase.from("referral_rewards").select("id, months, created_at, referrer:businesses!referral_rewards_referrer_id_fkey(name)")
      .eq("status", "pending").order("created_at")
      .then(({ data, error }) => setRewards(error ? [] : data ?? []));
    // Customer success (migration 0102): calls to make, paying or trial shops at risk.
    supabase.from("client_contacts").select("id, business_id, note, follow_up_date, businesses(name, phone)")
      .eq("follow_up_done", false).lte("follow_up_date", new Date().toISOString().slice(0, 10)).order("follow_up_date")
      .then(({ data, error }) => setCallsDue(error ? [] : data ?? []));
    supabase.rpc("admin_shop_health").then(({ data, error }) =>
      setAtRisk(error ? [] : ((data as any[]) ?? []).filter((s) => s.level === "risk" && ["active", "trial"].includes(s.status))));
    // My tasks due today or overdue (migration 0103).
    if (me) {
      supabase.from("admin_tasks").select("id, title, due_date").eq("assigned_to", me.id).eq("done", false)
        .lte("due_date", new Date().toISOString().slice(0, 10)).order("due_date")
        .then(({ data, error }) => setMyTasks(error ? [] : data ?? []));
    }
    supabase.from("platform_settings").select("payment_upi_id").maybeSingle()
      .then(({ data }) => setUpi(data?.payment_upi_id ?? ""));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  async function doReject() {
    const { error } = await supabase.rpc("admin_reject_renewal_claim", { p_claim: reject.id, p_reason: reason.trim() });
    if (error) {
      setNotice({ ok: false, text: error.message });
      return;
    }
    setNotice({ ok: true, text: `Payment claim from ${reject.name} rejected — the shop sees your reason in the app.` });
    setReject(null);
    setReason("");
    setRefresh((n) => n + 1);
  }

  const reminder = (r: any, expired: boolean) => {
    const price = r.monthly_price > 0 ? ` (${inr(r.monthly_price)}/month${r.yearly_price > 0 ? ` or ${inr(r.yearly_price)}/year` : ""})` : "";
    return (
      `Namaste ${r.owner_name || ""}! Your Dukania subscription for ${r.name} ` +
      (expired ? `expired on ${dateStr(r.expiry_date)}` : `ends on ${dateStr(r.expiry_date)}`) +
      `. To continue${price}, pay by UPI${upi ? ` to ${upi}` : ""} and send the payment screenshot here, ` +
      `or tap "I've paid" in the app. — Dukania`
    );
  };

  if (error) return <p className="text-red-600">{error}</p>;
  if (!data) return <Spinner />;

  const total =
    data.claims.length + data.expiring.length + data.expired.length + data.tickets.length +
    data.setup.length + data.inactive.length + data.followups.length + complaints.length + callsDue.length + myTasks.length +
    (canPay ? rewards.length : 0) +
    (data.reconciliation?.unexplained ? 1 : 0);

  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening";
  const firstName = (me?.name ?? "").trim().split(/\s+/)[0];

  return (
    <div className="space-y-6">
      <section className="dot-grid overflow-hidden rounded-xl bg-sidebar px-6 py-6 sm:px-8">
        <p className="text-sm font-medium text-sidebar-muted">{dateStr(data.today)}</p>
        <h1 className="mt-1 text-2xl font-bold tracking-tight text-white sm:text-[28px]">
          {greeting}{firstName ? `, ${firstName}` : ""}
        </h1>
        <p className="mt-1 flex items-center gap-2 text-sm text-sidebar-muted">
          {total === 0
            ? <><CheckCircle2 size={16} className="text-emerald-400" /> Nothing needs you right now.</>
            : <><span className="rounded-full bg-marigold px-2 py-0.5 text-xs font-bold tabular-nums text-sidebar">{total}</span> thing{total === 1 ? "" : "s"} need{total === 1 ? "s" : ""} you today</>}
        </p>
      </section>
      {stats && (
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <StatCard label="Paying shops" value={stats.active_clients} icon={<Store size={17} />} />
          <StatCard label="On trial" value={stats.trial_clients} icon={<UserRoundPlus size={17} />} />
          <StatCard label="Expired" value={stats.expired_clients} hint={`${stats.suspended_clients} suspended`} icon={<Inbox size={17} />} />
          {canPay ? (
            <StatCard label="Collected this month" value={inr(stats.monthly_revenue)} hint={`${stats.new_clients_this_month} new shops`} icon={<IndianRupee size={17} />} />
          ) : (
            <StatCard label="New shops this month" value={stats.new_clients_this_month} icon={<Users size={17} />} />
          )}
        </div>
      )}
      <Notice notice={notice} />
      {!upi && canPay && (
        <p className="rounded-lg bg-orange-50 px-4 py-3 text-sm text-orange-800">
          Your UPI ID isn&apos;t set, so expired shops can&apos;t see how to pay you.{" "}
          <Link href="/settings" className="font-semibold underline">Set it in Settings</Link>.
        </p>
      )}

      <div className="grid gap-4">
        <Group title="Your tasks" count={myTasks.length} tone="blue">
          {myTasks.map((t) => (
            <Row
              key={t.id}
              main={t.title}
              sub={<>Due {dateStr(t.due_date)}</>}
              actions={<Link href="/tasks"><Button variant="outline">Open tasks</Button></Link>}
            />
          ))}
        </Group>

        <Group title="Complaints not yet resolved" count={complaints.length} tone="red">
          {complaints.map((c) => (
            <Row
              key={c.id}
              main={<>{c.businesses?.name}: {c.subject}</>}
              sub={<>Since {dateTimeStr(c.created_at)} · {c.priority} priority</>}
              actions={<Link href="/support"><Button>Open Support</Button></Link>}
            />
          ))}
        </Group>

        <Group title="Payments to verify" count={data.claims.length} tone="blue">
          {data.claims.map((c) => (
            <Row
              key={c.id}
              main={<>{c.name} · {inr(c.amount)}</>}
              sub={<>UTR <span className="font-mono">{c.reference}</span> · {dateTimeStr(c.created_at)}{c.note ? ` · ${c.note}` : ""}</>}
              actions={<>
                <Button variant="soft" onClick={() => setRenew({ businessId: c.business_id, name: c.name, phone: c.phone, planId: c.plan_id, expiry: c.expiry_date, claim: { id: c.id, amount: Number(c.amount), reference: c.reference } })}>
                  Verified — renew
                </Button>
                <Button variant="outline" onClick={() => setReject(c)}>Not received</Button>
              </>}
            />
          ))}
        </Group>

        <Group title="Expired — not renewed" count={data.expired.length} tone="red">
          {data.expired.map((r) => (
            <Row
              key={r.business_id}
              main={<Link href={`/clients/${r.business_id}`} className="hover:underline">{r.name}</Link>}
              sub={<>Expired {dateStr(r.expiry_date)} ({-daysFrom(data.today, r.expiry_date)} days ago) · {r.plan_name ?? "no plan"} · {r.phone || "no phone"}</>}
              actions={<>
                {canPay && <Button variant="soft" onClick={() => setRenew({ businessId: r.business_id, name: r.name, phone: r.phone, planId: r.plan_id, expiry: r.expiry_date })}>Renew</Button>}
                <a href={waLink(r.phone, reminder(r, true))} target="_blank" rel="noreferrer"><Button variant="outline">WhatsApp</Button></a>
              </>}
            />
          ))}
        </Group>

        <Group title="Expiring in the next 7 days" count={data.expiring.length} tone="orange">
          {data.expiring.map((r) => (
            <Row
              key={r.business_id}
              main={<Link href={`/clients/${r.business_id}`} className="hover:underline">{r.name}</Link>}
              sub={<>{r.status === "trial" ? "Trial" : r.plan_name ?? "Plan"} ends {dateStr(r.expiry_date)} ({daysFrom(data.today, r.expiry_date) === 0 ? "today" : `in ${daysFrom(data.today, r.expiry_date)} days`})</>}
              actions={<>
                {canPay && <Button variant="soft" onClick={() => setRenew({ businessId: r.business_id, name: r.name, phone: r.phone, planId: r.plan_id, expiry: r.expiry_date })}>Renew</Button>}
                <a href={waLink(r.phone, reminder(r, false))} target="_blank" rel="noreferrer"><Button variant="outline">Remind</Button></a>
              </>}
            />
          ))}
        </Group>

        {canPay && (
          <Group title="Referral rewards to give" count={rewards.length} tone="purple">
            {rewards.map((r) => (
              <Row
                key={r.id}
                main={<>{r.referrer?.name}: {r.months} month{r.months === 1 ? "" : "s"} free</>}
                sub={<>A shop it referred paid on {dateStr(r.created_at)}</>}
                actions={<Link href="/marketing"><Button variant="outline">Give or skip</Button></Link>}
              />
            ))}
          </Group>
        )}

        <Group title="Asking for more staff logins" count={staffAsks.length} tone="purple">
          {staffAsks.map((r) => (
            <Row
              key={r.id}
              main={<Link href={`/clients/${r.business_id}`} className="hover:underline">{r.businesses?.name}</Link>}
              sub={<>Wants {r.requested_staff} more login{r.requested_staff > 1 ? "s" : ""} · asked {dateStr(r.created_at)}</>}
              actions={<>
                {canPay && (
                  <Link href={`/clients/${r.business_id}?addon=${r.requested_staff}`}>
                    <Button>Add {r.requested_staff} login{r.requested_staff > 1 ? "s" : ""}</Button>
                  </Link>
                )}
                {r.businesses?.phone && (
                  <a href={waLink(r.businesses.phone, `Namaste ${r.businesses.owner_name || ""}! We got your request for ${r.requested_staff} more staff login${r.requested_staff > 1 ? "s" : ""} for ${r.businesses.name}. `)} target="_blank" rel="noreferrer">
                    <Button variant="outline">WhatsApp</Button>
                  </a>
                )}
              </>}
            />
          ))}
        </Group>

        <Group title="Support tickets waiting for your reply" count={data.tickets.length} tone="purple">
          {data.tickets.map((t) => (
            <Row
              key={t.id}
              main={<>{t.name}: {t.subject}</>}
              sub={<>Waiting since {dateTimeStr(t.waiting_since ?? t.created_at)}</>}
              actions={<Link href="/support"><Button variant="outline">Reply</Button></Link>}
            />
          ))}
        </Group>

        {data.reconciliation && data.reconciliation.unexplained > 0 && (
          <Group title="Stock or balance mismatches" count={data.reconciliation.unexplained} tone="red">
            <Row
              main={<>{data.reconciliation.unexplained} unexplained in the last nightly check</>}
              sub={<>Checked {dateTimeStr(data.reconciliation.finished_at)} · must be 0 before the pilot ends</>}
              actions={<Link href="/reconciliation"><Button variant="outline">Review</Button></Link>}
            />
          </Group>
        )}

        <Group title="Calls to make" count={callsDue.length} tone="orange">
          {callsDue.map((c) => (
            <Row
              key={c.id}
              main={<Link href={`/clients/${c.business_id}`} className="hover:underline">{c.businesses?.name}</Link>}
              sub={<>Follow up {dateStr(c.follow_up_date)}{c.note ? ` · ${c.note}` : ""}</>}
              actions={c.businesses?.phone ? <a href={`tel:${c.businesses.phone}`}><Button variant="outline">Call</Button></a> : null}
            />
          ))}
        </Group>

        {atRisk.length > 0 && (
          <Group title="Paying or trial shops at risk" count={atRisk.length} tone="red">
            {atRisk.slice(0, 5).map((s) => (
              <Row
                key={s.id}
                main={<Link href={`/clients/${s.id}`} className="hover:underline">{s.name} · health {s.score}</Link>}
                sub={<>{s.reasons.join(" · ")}</>}
                actions={<Link href="/success"><Button variant="outline">Customer success</Button></Link>}
              />
            ))}
          </Group>
        )}

        <Group title="Signed up but never finished setup" count={data.setup.length}>
          {data.setup.map((r) => (
            <Row
              key={r.business_id}
              main={<Link href={`/clients/${r.business_id}`} className="hover:underline">{r.name}</Link>}
              sub={<>Joined {dateStr(r.created_at)} · {r.phone || "no phone"}</>}
              actions={<a href={waLink(r.phone, `Namaste ${r.owner_name || ""}! This is Dukania. Can I help you finish setting up Dukania for ${r.name}? It takes 5 minutes.`)} target="_blank" rel="noreferrer"><Button variant="outline">Offer help</Button></a>}
            />
          ))}
        </Group>

        <Group title="No bills for 7 days" count={data.inactive.length}>
          {data.inactive.map((r) => (
            <Row
              key={r.business_id}
              main={<Link href={`/clients/${r.business_id}`} className="hover:underline">{r.name}</Link>}
              sub={<>Last bill {r.last_bill ? dateStr(r.last_bill) : "never"}</>}
              actions={<a href={waLink(r.phone, `Namaste ${r.owner_name || ""}! This is Dukania. We noticed no bills in Dukania for ${r.name} this week — is everything working? Happy to help.`)} target="_blank" rel="noreferrer"><Button variant="outline">Check in</Button></a>}
            />
          ))}
        </Group>

        <Group title="Lead follow-ups due" count={data.followups.length}>
          {data.followups.map((l) => (
            <Row
              key={l.id}
              main={<Link href={`/leads/${l.id}`} className="hover:underline">{l.shop_name}</Link>}
              sub={<>{l.contact_name || "—"} · due {dateStr(l.follow_up_date)} · {stageLabel(l.status)}</>}
              actions={<Link href={`/leads/${l.id}`}><Button variant="outline">Open lead</Button></Link>}
            />
          ))}
        </Group>
      </div>

      {renew && (
        <RenewDialog
          target={renew}
          onClose={() => setRenew(null)}
          onDone={() => setRefresh((n) => n + 1)}
        />
      )}
      {reject && (
        <Modal title={`Payment not received — ${reject.name}`} onClose={() => setReject(null)}>
          <div className="space-y-4">
            <p className="text-sm text-zinc-600">
              The shop reported {inr(reject.amount)} with UTR <span className="font-mono">{reject.reference}</span>.
              Tell them why you couldn&apos;t confirm it — they see this in the app.
            </p>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. No payment with this UTR — please send a screenshot" />
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setReject(null)}>Cancel</Button>
              <Button variant="danger" onClick={doReject} disabled={!reason.trim()}>Reject claim</Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
