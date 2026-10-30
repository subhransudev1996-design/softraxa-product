"use client";

import { useState } from "react";
import { Button, Input, Label, Select, Toggle } from "@/components/ui";
import { Modal, waLink } from "@/components/ops";
import { createClient } from "@/lib/supabase/client";
import { inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

export const SITE = "https://www.dukania.in";
// Commission paid to one person in a financial year above this needs TDS
// (section 194H) — a reminder only; the CA decides.
const TDS_LIMIT = 20000;

export const PLATFORMS = [
  ["instagram", "Instagram"],
  ["youtube", "YouTube"],
  ["facebook", "Facebook"],
  ["other", "Other"],
] as const;

export type Editing = {
  id?: string; name: string; handle: string; phone: string; upi_id: string; code: string;
  buyer_off_pct: string; commission_kind: string; commission_value: string; hold_days: string; active: boolean; note: string;
  platform: string; followers: string; niche: string; language: string; city: string;
};

export const linkOf = (p: any) => `${SITE}/r/${p.code}`;
export const statsOf = (p: any) => `${SITE}/partner/${p.stats_token}`;

export const editingFrom = (p: any): Editing => ({
  id: p.id, name: p.name, handle: p.handle, phone: p.phone, upi_id: p.upi_id, code: p.code,
  buyer_off_pct: String(Number(p.buyer_off_pct)), commission_kind: p.commission_kind,
  commission_value: String(Number(p.commission_value)), hold_days: String(p.hold_days), active: p.active, note: p.note,
  platform: p.platform ?? "instagram", followers: p.followers == null ? "" : String(p.followers),
  niche: p.niche ?? "", language: p.language ?? "", city: p.city ?? "",
});

/** Add or edit a partner. */
export function PartnerForm({ editing, setEditing, onClose, onDone }: {
  editing: Editing; setEditing: (e: Editing) => void; onClose: () => void; onDone: (text: string) => void;
}) {
  const [error, setError] = useState<string | null>(null);

  async function save() {
    const { data, error: e } = await createClient().rpc("admin_save_partner", {
      p: {
        id: editing.id ?? "", name: editing.name, handle: editing.handle, phone: editing.phone, upi_id: editing.upi_id,
        code: editing.code, buyer_off_pct: Number(editing.buyer_off_pct), commission_kind: editing.commission_kind,
        commission_value: Number(editing.commission_value), hold_days: Number(editing.hold_days),
        active: editing.active, note: editing.note, platform: editing.platform, followers: editing.followers,
        niche: editing.niche, language: editing.language, city: editing.city,
      },
    });
    if (e) return setError(e.message);
    onDone(editing.id ? "Saved." : `${(data as any).name} is ready. Their link: ${linkOf(data)}`);
  }

  return (
        <Modal title={editing.id ? `Edit ${editing.name}` : "New partner"} onClose={() => onClose()} wide>
          <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
            {error && <p className="font-medium text-red-600">{error}</p>}
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
                <Input required disabled={Boolean(editing.id)} value={editing.code} pattern="[A-Za-z0-9_\-]{3,20}" className="font-mono"
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
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
              <div>
                <Label>Platform</Label>
                <Select value={editing.platform} onChange={(e) => setEditing({ ...editing, platform: e.target.value })}>
                  {PLATFORMS.map(([k, label]) => <option key={k} value={k}>{label}</option>)}
                </Select>
              </div>
              <div>
                <Label>Followers</Label>
                <Input type="number" min={0} value={editing.followers} onChange={(e) => setEditing({ ...editing, followers: e.target.value })} />
              </div>
              <div>
                <Label>Niche</Label>
                <Input value={editing.niche} onChange={(e) => setEditing({ ...editing, niche: e.target.value })} placeholder="Kirana tips" />
              </div>
              <div>
                <Label>Language</Label>
                <Input value={editing.language} onChange={(e) => setEditing({ ...editing, language: e.target.value })} placeholder="Hindi" />
              </div>
              <div>
                <Label>City</Label>
                <Input value={editing.city} onChange={(e) => setEditing({ ...editing, city: e.target.value })} />
              </div>
            </div>
            <div>
              <Label>Note (only the team sees it)</Label>
              <Input value={editing.note} onChange={(e) => setEditing({ ...editing, note: e.target.value })} placeholder="e.g. 45k followers, kirana tips" />
            </div>
            {editing.id && <Toggle checked={editing.active} onChange={(v) => setEditing({ ...editing, active: v })} label={editing.active ? "On — link and code work" : "Off — link and code stop"} />}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => onClose()}>Cancel</Button>
              <Button type="submit" disabled={!editing.name.trim() || !editing.code.trim()}>{editing.id ? "Save" : "Create"}</Button>
            </div>
          </form>
        </Modal>
  );
}

export function PayDialog({ partner, onClose, onDone }: { partner: any; onClose: () => void; onDone: (text: string) => void }) {
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

export const STATUS: Record<string, [string, string]> = {
  pending: ["Waiting", "orange"],
  paid: ["Paid", "green"],
  cancelled: ["Cancelled", "zinc"],
};

/**
 * The partner's login (migration 0107): an email and a generated password,
 * shown once to send on WhatsApp. Also switches the old private link off.
 */
export function PartnerLogin({ partner, canEdit }: { partner: any; canEdit: boolean }) {
  const [email, setEmail] = useState("");
  const [login, setLogin] = useState<string>(partner.login_email || (partner.user_id ? "—" : ""));
  const [fresh, setFresh] = useState<{ email: string; password: string } | null>(null);
  const [linkOn, setLinkOn] = useState<boolean>(partner.stats_link_on !== false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function act(action: string) {
    if (action === "remove" && !window.confirm(`Remove ${partner.name}'s login? They can't sign in after this.`)) return;
    setBusy(true);
    setError(null);
    const res = await fetch("/api/partner-login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ partnerId: partner.id, action, email }),
    });
    const data = await res.json().catch(() => ({}));
    setBusy(false);
    if (!res.ok) return setError(data.error ?? "That didn't work");
    if (action === "remove") {
      setLogin("");
      setFresh(null);
    } else {
      setLogin(data.email);
      setFresh(data);
      setEmail("");
    }
  }

  async function changeLink(on: boolean) {
    const { error: e } = await createClient().rpc("admin_set_partner_link", { p_partner: partner.id, p_on: on });
    if (e) return setError(e.message);
    setLinkOn(on);
  }

  const message = fresh
    ? `Namaste ${partner.name}! Your Dukania partner login: ${SITE}/partner/login — email ${fresh.email}, password ${fresh.password} . ` +
      `You can change the password after signing in. Your link for posts: ${linkOf(partner)} , your code ${partner.code}. Dukania`
    : "";

  return (
    <div className="rounded-xl bg-zinc-50 p-3">
      <p className="text-xs text-zinc-500">Their login ({SITE.replace("https://www.", "")}/partner/login)</p>
      {error && <p className="mt-1 text-xs font-medium text-red-600">{error}</p>}
      {fresh && (
        <div className="mt-2 rounded-lg bg-violet-50 p-3 text-violet-900">
          <p className="font-semibold">Send this now — the password won&apos;t show again.</p>
          <p className="mt-1 font-mono text-xs">{fresh.email}<br />{fresh.password}</p>
          {partner.phone && (
            <a href={waLink(partner.phone, message)} target="_blank" rel="noreferrer"><Button className="mt-2">Send login on WhatsApp</Button></a>
          )}
        </div>
      )}
      {login ? (
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <span className="font-mono text-xs font-semibold">{login}</span>
          {canEdit && (
            <>
              <Button variant="outline" disabled={busy} onClick={() => act("reset")}>New password</Button>
              <Button variant="ghost" disabled={busy} onClick={() => act("remove")}>Remove login</Button>
            </>
          )}
        </div>
      ) : canEdit ? (
        <form className="mt-2 flex flex-wrap gap-2" onSubmit={(e) => { e.preventDefault(); act("create"); }}>
          <Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Their email" className="max-w-xs" />
          <Button type="submit" disabled={busy || !email.trim()}>Create login</Button>
        </form>
      ) : (
        <p className="mt-1 text-zinc-500">No login yet.</p>
      )}
      {canEdit && (
        <div className="mt-3 border-t border-zinc-200 pt-3">
          <Toggle checked={linkOn} onChange={changeLink} label={linkOn ? "Private stats link: on" : "Private stats link: off (login only)"} />
        </div>
      )}
    </div>
  );
}
