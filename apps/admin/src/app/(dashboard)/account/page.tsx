"use client";

import { ReactNode, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, PageHeader } from "@/components/ui";
import { Notice } from "@/components/ops";
import { useMe } from "@/components/me";
import { AREAS, roleLabel } from "@/lib/team";
import { dateStr } from "@/lib/format";

type Factor = { id: string; status: string; created_at: string };
type Enrolling = { factorId: string; qr: string; secret: string };

/** Each team member's own login: password, two-step login, other devices. */
export default function AccountPage() {
  const me = useMe();
  return (
    <div className="space-y-6">
      <PageHeader title="My login" subtitle={me ? `${me.name || me.email} · ${roleLabel(me.team_role)}` : undefined} />
      {me && (
        <Section title="What you can use" hint="The owner sets this on the Team page.">
          <div className="flex flex-wrap gap-2">
            {me.is_owner ? (
              <Badge color="purple">Everything, and the team</Badge>
            ) : (
              AREAS.filter((a) => me.areas.includes(a.key)).map((a) => (
                <Badge key={a.key} color="purple">{a.label}</Badge>
              ))
            )}
          </div>
        </Section>
      )}
      <TwoStepCard />
      <PasswordCard email={me?.email ?? ""} />
      <DevicesCard />
    </div>
  );
}

function Section({ title, hint, children }: { title: string; hint: string; children: ReactNode }) {
  return (
    <Card>
      <CardBody className="space-y-4">
        <div>
          <h2 className="text-base font-bold text-ink">{title}</h2>
          <p className="text-xs text-zinc-500">{hint}</p>
        </div>
        {children}
      </CardBody>
    </Card>
  );
}

/** A code from an authenticator app (Google Authenticator, Microsoft Authenticator…) after the password. */
function TwoStepCard() {
  const router = useRouter();
  const [factors, setFactors] = useState<Factor[] | null>(null);
  const [enrolling, setEnrolling] = useState<Enrolling | null>(null);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    createClient().auth.mfa.listFactors().then(({ data }) => setFactors((data?.totp as Factor[]) ?? []));
  }, [refresh]);

  async function start() {
    setBusy(true);
    setNotice(null);
    const supabase = createClient();
    // A setup that was started and never finished blocks a new one.
    const { data: all } = await supabase.auth.mfa.listFactors();
    for (const f of all?.all ?? []) {
      if (f.status !== "verified") await supabase.auth.mfa.unenroll({ factorId: f.id });
    }
    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `Dukania admin ${Date.now()}` });
    setBusy(false);
    if (error || !data) return setNotice({ ok: false, text: error?.message ?? "Could not start" });
    setEnrolling({ factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
  }

  async function verifyCode(e: React.FormEvent) {
    e.preventDefault();
    if (!enrolling) return;
    setBusy(true);
    const { error } = await createClient().auth.mfa.challengeAndVerify({ factorId: enrolling.factorId, code: code.trim() });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: "That code didn't work. Try the newest code in the app." });
    setEnrolling(null);
    setCode("");
    setNotice({ ok: true, text: "Two-step login is on. From now on you'll type a code from the app after your password." });
    setRefresh((n) => n + 1);
    router.refresh(); // the panel stops asking for two-step login
  }

  async function turnOff(f: Factor) {
    if (!window.confirm("Turn off two-step login? Anyone with your password could then sign in.")) return;
    setBusy(true);
    const { error } = await createClient().auth.mfa.unenroll({ factorId: f.id });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: "Two-step login is off." });
    setRefresh((n) => n + 1);
  }

  const on = (factors ?? []).filter((f) => f.status === "verified");

  return (
    <Section
      title="Two-step login"
      hint="After your password, a 6-digit code from an authenticator app on your phone. A stolen password alone can't get in."
    >
      <Notice notice={notice} />
      {factors === null ? null : on.length > 0 ? (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-zinc-700">
            <Badge color="green">On</Badge> <span className="ml-2">since {dateStr(on[0].created_at)}</span>
          </p>
          <Button variant="outline" disabled={busy} onClick={() => turnOff(on[0])}>Turn off</Button>
        </div>
      ) : enrolling ? (
        <form onSubmit={verifyCode} className="space-y-4">
          <ol className="list-decimal space-y-1 pl-5 text-sm text-zinc-700">
            <li>Install Google Authenticator or Microsoft Authenticator on your phone.</li>
            <li>In the app, add an account and scan this code.</li>
            <li>Type the 6-digit code the app shows.</li>
          </ol>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={enrolling.qr} alt="QR code for the authenticator app" className="h-44 w-44 rounded-lg border border-zinc-200 bg-white p-2" />
          <p className="text-xs text-zinc-500">
            Can&apos;t scan? Type this key in the app: <code className="break-all font-mono text-zinc-700">{enrolling.secret}</code>
          </p>
          <div className="max-w-xs">
            <Label>6-digit code</Label>
            <Input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} placeholder="123456" />
          </div>
          <div className="flex gap-2">
            <Button type="submit" disabled={busy || code.length !== 6}>{busy ? "Checking…" : "Turn on"}</Button>
            <Button variant="ghost" onClick={() => setEnrolling(null)}>Cancel</Button>
          </div>
        </form>
      ) : (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-zinc-700"><Badge color="orange">Off</Badge></p>
          <Button disabled={busy} onClick={start}>Turn on two-step login</Button>
        </div>
      )}
    </Section>
  );
}

/** Change the password of the login you are signed in with. */
function PasswordCard({ email }: { email: string }) {
  const [password, setPassword] = useState("");
  const [again, setAgain] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);

  async function change(e: React.FormEvent) {
    e.preventDefault();
    setNotice(null);
    if (password.length < 10) return setNotice({ ok: false, text: "Use at least 10 characters" });
    if (password !== again) return setNotice({ ok: false, text: "The two passwords don't match" });
    setBusy(true);
    const { error } = await createClient().auth.updateUser({ password });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: error.message });
    setPassword("");
    setAgain("");
    setNotice({ ok: true, text: "Password changed. Use the new one the next time you sign in." });
  }

  return (
    <Section title="Password" hint="Use a long password that you use nowhere else.">
      <p className="text-sm text-zinc-700">Signed in as <b>{email || "—"}</b></p>
      <Notice notice={notice} />
      <form onSubmit={change} className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label>New password</Label>
          <Input type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} />
        </div>
        <div>
          <Label>New password again</Label>
          <Input type="password" autoComplete="new-password" value={again} onChange={(e) => setAgain(e.target.value)} />
        </div>
        <div className="sm:col-span-2">
          <Button type="submit" variant="outline" disabled={busy || !password}>{busy ? "Changing…" : "Change password"}</Button>
        </div>
      </form>
    </Section>
  );
}

/** Lost a phone or used a shared computer: sign out everywhere else. */
function DevicesCard() {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);

  async function signOutOthers() {
    setBusy(true);
    const { error } = await createClient().auth.signOut({ scope: "others" });
    setBusy(false);
    setNotice(error ? { ok: false, text: error.message } : { ok: true, text: "Signed out on every other computer and phone." });
  }

  return (
    <Section title="Other devices" hint="Lost a phone, or signed in on someone else's computer? This keeps you signed in here only.">
      <Notice notice={notice} />
      <Button variant="outline" disabled={busy} onClick={signOutOthers}>
        {busy ? "Signing out…" : "Sign out on all other devices"}
      </Button>
    </Section>
  );
}
