"use client";

import { ReactNode, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Spinner } from "@/components/ui";
import { Notice } from "@/components/ops";
import { dateStr, dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Check = { key: string; ok: boolean | null; detail: string };

// Settings that live in dashboards the panel can't read. Tick them once done.
const MANUAL: { key: string; title: string; how: ReactNode }[] = [
  {
    key: "auth_urls",
    title: "Supabase: Site URL and Redirect URLs",
    how: <>Authentication → URL Configuration: Site URL = your website; add <code>https://your-website/auth/callback</code> to Redirect URLs.</>,
  },
  {
    key: "auth_templates",
    title: "Supabase: email templates use the website link",
    how: <>Authentication → Email Templates. <b>Confirm signup</b> link: <code>{"{{ .SiteURL }}/auth/callback?token_hash={{ .TokenHash }}&type=email"}</code>. <b>Reset password</b> link: <code>{"{{ .SiteURL }}/auth/callback?token_hash={{ .TokenHash }}&type=recovery"}</code>. Without this, new shops can&apos;t confirm their email or reset passwords.</>,
  },
  {
    key: "auth_smtp",
    title: "Supabase: your own email sender (SMTP)",
    how: <>Authentication → SMTP Settings: turn on custom SMTP (Resend: host smtp.resend.com, port 465, user &quot;resend&quot;, password = your Resend API key). The built-in sender only allows a few emails an hour.</>,
  },
  {
    key: "hosting_env",
    title: "Hosting has the same settings as your computer",
    how: <>Wherever the admin panel and website are hosted, set the same values as <code>.env.local</code> / <code>.env</code> (Supabase URL and keys, WEBSITE_URL, RESEND_API_KEY, EMAIL_FROM).</>,
  },
  {
    key: "firebase_secret",
    title: "Push notifications: Firebase secret on the server",
    how: <>Supabase → Edge Functions → Secrets: <code>FIREBASE_SERVICE_ACCOUNT</code> (the service account JSON) and <code>PUSH_ALERTS_SECRET</code>. Then deploy push-alerts, approval-push and support-push.</>,
  },
  {
    key: "backup_restore",
    title: "Backup restore tested (monthly)",
    how: <>Restore a production backup into staging and check it opens. Tick again every month — it&apos;s a release rule.</>,
  },
];

function Dot({ ok }: { ok: boolean | null }) {
  const color = ok === null ? "bg-zinc-300" : ok ? "bg-emerald-500" : "bg-red-500";
  return <span className={`mt-1.5 inline-block h-2.5 w-2.5 shrink-0 rounded-full ${color}`} aria-label={ok === null ? "unknown" : ok ? "ok" : "problem"} />;
}

function Line({ ok, title, detail }: { ok: boolean | null; title: string; detail: ReactNode }) {
  return (
    <li className="flex gap-3 py-2.5">
      <Dot ok={ok} />
      <div className="min-w-0">
        <p className="font-semibold text-ink">{title}</p>
        <p className="text-xs text-zinc-500">{detail}</p>
      </div>
    </li>
  );
}

export default function HealthPage() {
  const supabase = createClient();
  const [db, setDb] = useState<any>(null);
  const [server, setServer] = useState<Check[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [checkedAt, setCheckedAt] = useState(0);

  useEffect(() => {
    supabase.rpc("get_system_health").then(({ data, error }) => {
      if (error) return setError(error.message);
      setCheckedAt(Date.now());
      setDb(data);
    });
    fetch("/api/health").then((r) => r.json()).then((j) => setServer(j.checks ?? [])).catch(() => setServer([]));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  async function confirm(key: string, done: boolean) {
    const next = { ...(db?.confirmed_checks ?? {}) };
    if (done) next[key] = new Date().toISOString().slice(0, 10);
    else delete next[key];
    const { error } = await supabase.from("platform_settings").update({ confirmed_checks: next }).eq("id", 1);
    if (error) setNotice({ ok: false, text: error.message });
    else setDb((d: any) => ({ ...d, confirmed_checks: next }));
  }

  if (error) {
    return (
      <p className="text-red-600">
        {error.includes("get_system_health") ? "Migration 0053 isn't applied to this database yet." : error}
      </p>
    );
  }
  if (!db || !server) return <Spinner />;

  const m = db.migrations ?? {};
  const lastRecon = db.last_reconciliation;
  const reconFresh = lastRecon?.finished_at && checkedAt - new Date(lastRecon.finished_at).getTime() < 36 * 3600 * 1000;
  const s = (key: string) => server.find((c) => c.key === key);
  const fnOk = (k: string) => s(k)?.ok ?? null;

  const dbLines: [boolean | null, string, ReactNode][] = [
    [Object.values(m).every(Boolean), "Database is up to date",
      Object.entries(m).filter(([, v]) => !v).map(([k]) => k).join(", ") ? `Not applied: ${Object.entries(m).filter(([, v]) => !v).map(([k]) => k).join(", ")}` : "All migrations are applied"],
    [Boolean(db.pg_cron && db.nightly_job), "Nightly stock and balance check is scheduled",
      !db.pg_cron ? "Enable pg_cron (Integrations → Cron), then re-run the last block of migration 0050" : db.nightly_job ? "Runs at 02:00 India time" : "pg_cron is on but the job isn't scheduled — re-run the last block of 0050"],
    [lastRecon ? Boolean(reconFresh) : null, "Nightly check ran recently",
      lastRecon ? `Last run ${dateTimeStr(lastRecon.finished_at)} · ${lastRecon.unexplained} unexplained of ${lastRecon.issues}` : "Never run — press Run now on the Reconciliation page"],
    [db.imagekit_key, "ImageKit key for shop logos and product photos",
      db.imagekit_key === null ? "Couldn't read Vault" : db.imagekit_key ? "Stored in Vault" : "Missing — photo uploads fail. Create a new private key in ImageKit and store it with vault.create_secret(…, 'imagekit_private_key')"],
    [db.trial_plan_set ?? null, "Trial plan for new shops",
      db.trial_plan_set == null ? "Needs migration 0055" : db.trial_plan_set ? "Set — new shops start on it" : "Not set — new shops get no plan. Mark one on the Plans page"],
    [Boolean(db.payment_upi_set), "Your UPI ID for renewals", db.payment_upi_set ? "Set — expired shops can pay you" : "Not set — add it in Settings"],
    [db.last_bill_at ? true : null, "Shops are billing",
      db.last_bill_at ? `Last bill ${dateTimeStr(db.last_bill_at)} · ${db.bills_today} today · ${db.shops_active} active shops` : "No bills yet"],
    [db.devices > 0 ? true : null, "Phones registered for push", `${db.devices} device${db.devices === 1 ? "" : "s"}`],
  ];

  const serverLines: [boolean | null, string, ReactNode][] = [
    [s("service_key")?.ok ?? null, "Admin server key", s("service_key")?.detail],
    [s("email")?.ok ?? null, "Welcome and set-password emails", s("email")?.detail],
    [s("website")?.ok ?? null, "Website password page", s("website")?.detail],
    [fnOk("fn_push-alerts"), "Daily stock alerts function", s("fn_push-alerts")?.detail],
    [fnOk("fn_approval-push"), "Approval notification function", s("fn_approval-push")?.detail],
    [fnOk("fn_support-push"), "Support reply notification function", s("fn_support-push")?.detail],
  ];

  const problems = [...dbLines, ...serverLines].filter(([ok]) => ok === false).length +
    MANUAL.filter((c) => !db.confirmed_checks?.[c.key]).length;

  return (
    <div className="max-w-3xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">System health</h1>
          <p className="text-sm text-zinc-500">
            {problems === 0 ? "Everything is set up." : `${problems} thing${problems === 1 ? "" : "s"} to set up or confirm.`}
          </p>
        </div>
        <Button variant="outline" onClick={() => { setDb(null); setServer(null); setRefresh((n) => n + 1); }}>Check again</Button>
      </div>
      <Notice notice={notice} />

      <Card>
        <CardBody>
          <h2 className="text-sm font-semibold text-zinc-700">Database</h2>
          <ul className="divide-y divide-zinc-100 text-sm">
            {dbLines.map(([ok, title, detail]) => <Line key={title} ok={ok} title={title} detail={detail} />)}
          </ul>
        </CardBody>
      </Card>

      <Card>
        <CardBody>
          <h2 className="text-sm font-semibold text-zinc-700">Admin server and services</h2>
          <ul className="divide-y divide-zinc-100 text-sm">
            {serverLines.map(([ok, title, detail]) => <Line key={title} ok={ok} title={title} detail={detail ?? "—"} />)}
          </ul>
        </CardBody>
      </Card>

      <Card>
        <CardBody>
          <h2 className="text-sm font-semibold text-zinc-700">Confirm by hand</h2>
          <p className="mb-2 text-xs text-zinc-500">These live in other dashboards the panel can&apos;t read. Tick each once it&apos;s done.</p>
          <ul className="divide-y divide-zinc-100 text-sm">
            {MANUAL.map((c) => {
              const done = db.confirmed_checks?.[c.key];
              return (
                <li key={c.key} className="flex gap-3 py-3">
                  <input
                    id={`chk-${c.key}`}
                    type="checkbox"
                    checked={Boolean(done)}
                    onChange={(e) => confirm(c.key, e.target.checked)}
                    className="mt-1 h-4 w-4 accent-[var(--brand)]"
                  />
                  <label htmlFor={`chk-${c.key}`} className="min-w-0">
                    <span className="font-semibold text-ink">{c.title}</span>
                    {done && <span className="ml-2 text-xs text-emerald-700">done {dateStr(done)}</span>}
                    <span className="mt-0.5 block text-xs text-zinc-500 [&_code]:rounded [&_code]:bg-zinc-100 [&_code]:px-1 [&_code]:font-mono [&_code]:text-[11px] [&_code]:text-ink">{c.how}</span>
                  </label>
                </li>
              );
            })}
          </ul>
        </CardBody>
      </Card>
    </div>
  );
}
