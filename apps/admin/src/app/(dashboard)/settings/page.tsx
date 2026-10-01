"use client";

import { ReactNode, useEffect, useState } from "react";
import Link from "next/link";
import QRCode from "qrcode";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Spinner } from "@/components/ui";
import { Notice } from "@/components/ops";
import { dateTimeStr } from "@/lib/format";

const UPI_PATTERN = /^[A-Za-z0-9._-]{2,255}@[A-Za-z][A-Za-z0-9]{1,63}$/;
const GSTIN_PATTERN = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/;

const FIELDS = [
  "payment_upi_id", "payment_payee_name", "support_whatsapp", "business_name",
  "business_address", "business_phone", "business_email", "business_gstin", "receipt_footer",
  "android_download_url", "windows_download_url",
] as const;
type Field = (typeof FIELDS)[number];
type Form = Record<Field, string>;

const EMPTY: Form = {
  payment_upi_id: "", payment_payee_name: "SOFTRAXA", support_whatsapp: "", business_name: "SOFTRAXA",
  business_address: "", business_phone: "", business_email: "", business_gstin: "", receipt_footer: "",
  android_download_url: "", windows_download_url: "",
};

const isHttps = (v: string) => /^https:\/\/\S+$/.test(v.trim());

// Same rule as admin_save_settings: digits only, 10 digits get India's 91.
const waDigits = (v: string) => {
  const d = v.replace(/\D/g, "");
  return d.length === 10 ? `91${d}` : d;
};

// The link the app puts in a shop's renewal QR (no amount: you tell the shop).
const upiLink = (upi: string, payee: string) =>
  `upi://pay?pa=${encodeURIComponent(upi)}&pn=${encodeURIComponent(payee || "SOFTRAXA")}&cu=INR&tn=${encodeURIComponent("Dukania renewal")}`;

/**
 * How shops pay and reach SOFTRAXA, and what payment receipts say
 * (migrations 0053 and 0056). Saved through admin_save_settings: checked
 * and logged.
 */
export default function SettingsPage() {
  const supabase = createClient();
  const [form, setForm] = useState<Form | null>(null);
  const [saved, setSaved] = useState<Form>(EMPTY);
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);
  const [needsMigration, setNeedsMigration] = useState(false);
  // Download links arrived with migration 0059.
  const [needsWebsiteMigration, setNeedsWebsiteMigration] = useState(false);
  const [trial, setTrial] = useState<{ plan: string | null; days: number | null }>({ plan: null, days: null });
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [qr, setQr] = useState<{ link: string; url: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase.from("platform_settings").select("*").maybeSingle().then(({ data }) => {
      const next = { ...EMPTY };
      for (const f of FIELDS) if (typeof data?.[f] === "string") next[f] = data[f];
      setForm(next);
      setSaved(next);
      setUpdatedAt(data?.updated_at ?? null);
      setNeedsMigration(Boolean(data) && !("business_name" in data));
      setNeedsWebsiteMigration(Boolean(data) && !("android_download_url" in data));
    });
    supabase.from("plans").select("name").eq("is_trial", true).limit(1)
      .then(({ data }) => setTrial((t) => ({ ...t, plan: data?.[0]?.name ?? null })));
    supabase.from("software_products").select("trial_days").eq("slug", "dukania").maybeSingle()
      .then(({ data }) => setTrial((t) => ({ ...t, days: data?.trial_days ?? null })));
    supabase.auth.getUser().then(({ data }) => setEmail(data.user?.email ?? ""));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  const upi = form?.payment_upi_id.trim() ?? "";
  const upiValid = UPI_PATTERN.test(upi);
  const link = upiValid ? upiLink(upi, form?.payment_payee_name.trim() ?? "") : "";

  useEffect(() => {
    if (!link) return;
    let active = true;
    QRCode.toDataURL(link, { margin: 1, width: 220 }).then((url) => {
      if (active) setQr({ link, url });
    });
    return () => { active = false; };
  }, [link]);

  if (!form) return <Spinner />;

  const set = (key: Field, value: string) => setForm({ ...form, [key]: value });
  const dirty = FIELDS.some((f) => form[f] !== saved[f]);
  const wa = waDigits(form.support_whatsapp);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    setNotice(null);
    if (upi && !upiValid) return setNotice({ ok: false, text: "That doesn't look like a UPI ID — it should be like softraxa@okaxis" });
    if (wa && (wa.length < 11 || wa.length > 15)) {
      return setNotice({ ok: false, text: "The WhatsApp number should be 10 digits, or the country code and the number" });
    }
    const gstin = form.business_gstin.trim().toUpperCase();
    if (gstin && !GSTIN_PATTERN.test(gstin)) {
      return setNotice({ ok: false, text: "That doesn't look like a GSTIN (15 characters, like 27ABCDE1234F1Z5)" });
    }
    for (const key of ["android_download_url", "windows_download_url"] as const) {
      if (form[key].trim() && !isHttps(form[key])) {
        return setNotice({ ok: false, text: "Download links must start with https://" });
      }
    }
    // Money goes wherever this ID points: make the change deliberate.
    if (saved.payment_upi_id && upi !== saved.payment_upi_id) {
      const ok = window.confirm(
        upi
          ? `Shops will now pay ${upi} instead of ${saved.payment_upi_id}. Have you scanned the QR on this page and seen your own name?`
          : `Remove your UPI ID? Expired shops will no longer see a QR code to pay you.`,
      );
      if (!ok) return;
    }
    setBusy(true);
    const { error } = await supabase.rpc("admin_save_settings", { p: form });
    setBusy(false);
    if (error) {
      return setNotice({
        ok: false,
        text: error.message.includes("admin_save_settings") ? "Migration 0056 isn't applied to this database yet." : error.message,
      });
    }
    setNotice({ ok: true, text: "Saved — shops see the new details the next time they open the app, and the website within the hour." });
    setRefresh((n) => n + 1);
  }

  return (
    <div className="max-w-3xl space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-zinc-900">Settings</h1>
        <p className="text-sm text-zinc-500">
          How shops pay you and reach you, and what your receipts say.
          {updatedAt ? ` Last changed ${dateTimeStr(updatedAt)}.` : ""}
        </p>
      </div>
      <Notice notice={notice} />
      {needsMigration && (
        <Notice notice={{ ok: false, text: "Migration 0056 isn't applied to this database yet — these settings can't be saved until it is." }} />
      )}

      <form onSubmit={save} className="space-y-6">
        <Section title="How shops pay you" hint="An expired shop sees this as a QR code in the app. The QR has no amount: you tell each shop what to pay.">
          <div className="grid gap-5 sm:grid-cols-[1fr_auto]">
            <div className="space-y-4">
              <div>
                <Label>Your UPI ID</Label>
                <Input value={form.payment_upi_id} onChange={(e) => set("payment_upi_id", e.target.value)} placeholder="softraxa@okaxis" className="font-mono" />
                {upi && !upiValid && <p className="mt-1 text-xs font-medium text-red-600">This isn&apos;t a UPI ID yet — it should look like name@bank.</p>}
                {!upi && <p className="mt-1 text-xs font-medium text-orange-700">Without a UPI ID, expired shops can only contact you on WhatsApp.</p>}
              </div>
              <div>
                <Label>Payee name</Label>
                <Input value={form.payment_payee_name} onChange={(e) => set("payment_payee_name", e.target.value)} placeholder="SOFTRAXA" />
                <p className="mt-1 text-xs text-zinc-500">Shown under the QR in the app. The UPI app itself shows the name on your bank account.</p>
              </div>
            </div>
            <div className="flex flex-col items-center gap-2 rounded-xl bg-zinc-50 p-4 text-center">
              {upiValid && qr?.link === link ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={qr.url} alt="UPI QR code for your UPI ID" width={176} height={176} className="rounded-lg bg-white p-1" />
              ) : (
                <div className="grid h-44 w-44 place-items-center rounded-lg border border-dashed border-zinc-300 px-3 text-xs text-zinc-500">
                  Enter your UPI ID to see the QR
                </div>
              )}
              <p className="max-w-44 text-xs text-zinc-600">
                <b>Check it:</b> scan this with your own phone. The UPI app must show your name before you save.
              </p>
            </div>
          </div>
        </Section>

        <Section title="How shops reach you" hint="Every WhatsApp button in the app opens a chat with this number.">
          <div>
            <Label>Support WhatsApp number</Label>
            <div className="flex flex-wrap items-center gap-2">
              <Input value={form.support_whatsapp} onChange={(e) => set("support_whatsapp", e.target.value)} placeholder="98765 43210" className="max-w-xs" inputMode="tel" />
              {wa.length >= 11 && (
                <a href={`https://wa.me/${wa}`} target="_blank" rel="noreferrer">
                  <Button variant="outline">Test on WhatsApp</Button>
                </a>
              )}
            </div>
            <p className="mt-1 text-xs text-zinc-500">
              {wa ? `Saved as +${wa}. ` : "Empty: the app uses the number built into it. "}
              A 10-digit number gets India&apos;s 91 in front.
            </p>
          </div>
        </Section>

        <Section title="On your receipts" hint="Printed at the top of every payment receipt you give a shop.">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <Label>Business name</Label>
              <Input value={form.business_name} onChange={(e) => set("business_name", e.target.value)} placeholder="SOFTRAXA" />
            </div>
            <div>
              <Label>Phone</Label>
              <Input value={form.business_phone} onChange={(e) => set("business_phone", e.target.value)} inputMode="tel" />
            </div>
            <div className="sm:col-span-2">
              <Label>Address</Label>
              <Input value={form.business_address} onChange={(e) => set("business_address", e.target.value)} />
            </div>
            <div>
              <Label>Email</Label>
              <Input type="email" value={form.business_email} onChange={(e) => set("business_email", e.target.value)} />
            </div>
            <div>
              <Label>GSTIN (only if you are registered)</Label>
              <Input value={form.business_gstin} onChange={(e) => set("business_gstin", e.target.value.toUpperCase())} maxLength={15} className="font-mono" />
            </div>
            <div className="sm:col-span-2">
              <Label>Line at the bottom of the receipt</Label>
              <Input value={form.receipt_footer} onChange={(e) => set("receipt_footer", e.target.value)} maxLength={200} placeholder="e.g. Thank you for choosing Dukania" />
            </div>
          </div>
        </Section>

        <Section title="On the website" hint="softraxa.in shows your WhatsApp number, phone and email from above, Dukania's starting price from your cheapest plan, and these download links.">
          {needsWebsiteMigration && (
            <Notice notice={{ ok: false, text: "Migration 0059 isn't applied yet — the download links can't be saved until it is." }} />
          )}
          <div className="grid gap-4">
            <div>
              <Label>Android app download link</Label>
              <Input value={form.android_download_url} onChange={(e) => set("android_download_url", e.target.value)} placeholder="https://github.com/…/releases/download/v1.0.0/Dukania.apk" className="font-mono" />
              {form.android_download_url.trim() && !isHttps(form.android_download_url) && (
                <p className="mt-1 text-xs font-medium text-red-600">The link must start with https://</p>
              )}
            </div>
            <div>
              <Label>Windows installer download link</Label>
              <Input value={form.windows_download_url} onChange={(e) => set("windows_download_url", e.target.value)} placeholder="https://github.com/…/releases/download/v1.0.0/Dukania-Setup-1.0.0.exe" className="font-mono" />
              {form.windows_download_url.trim() && !isHttps(form.windows_download_url) && (
                <p className="mt-1 text-xs font-medium text-red-600">The link must start with https://</p>
              )}
            </div>
            <p className="text-xs text-zinc-500">
              Empty: the website&apos;s Download page says &ldquo;message us on WhatsApp for the app&rdquo; instead of a download button.
              Paste a new link here whenever you publish a new version.
            </p>
          </div>
        </Section>

        <div className="sticky bottom-3 z-10 flex items-center justify-between gap-3 rounded-2xl border border-zinc-200 bg-white/95 px-4 py-3 shadow-lg backdrop-blur">
          <p className="text-sm text-zinc-600">{dirty ? "You have changes that aren't saved." : "Everything is saved."}</p>
          <div className="flex gap-2">
            {dirty && <Button variant="ghost" onClick={() => setForm(saved)}>Undo</Button>}
            <Button type="submit" disabled={busy || !dirty || needsMigration}>{busy ? "Saving…" : "Save settings"}</Button>
          </div>
        </div>
      </form>

      <Section title="New shops" hint="Set in other places; shown here so you know what a new signup gets.">
        <p className="text-sm text-zinc-700">
          A new shop starts on{" "}
          <b>{trial.plan ?? "no plan (owner only)"}</b>
          {trial.days ? <> for <b>{trial.days} days</b></> : null}.
        </p>
        <p className="text-sm text-zinc-500">
          Change the trial plan on <Link href="/plans" className="font-semibold text-brand hover:underline">Plans</Link>,
          the number of days on <Link href="/products" className="font-semibold text-brand hover:underline">Software</Link>.
          Setup problems are listed on <Link href="/health" className="font-semibold text-brand hover:underline">System health</Link>.
        </p>
      </Section>

      <PasswordCard email={email} />
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

/** Change the password of the admin account you are signed in with. */
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
    <Section title="Your login" hint="This account controls every shop's subscription. Use a long password that you use nowhere else.">
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
