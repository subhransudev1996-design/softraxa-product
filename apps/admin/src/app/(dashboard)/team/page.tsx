"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Input, Label, PageHeader, Select, Spinner } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { useMe } from "@/components/me";
import { AREAS, Area, ROLES, TeamMember, TeamRole, roleLabel } from "@/lib/team";
import { dateTimeStr } from "@/lib/format";

type Editing = { member: TeamMember | null; email: string; name: string; role: TeamRole; areas: Area[] };

/**
 * The owner's Team page (migration 0098): who can use the admin panel and
 * which areas each person may use. The database enforces the areas.
 */
export default function TeamPage() {
  const me = useMe();
  const [team, setTeam] = useState<TeamMember[] | null>(null);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [link, setLink] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    createClient()
      .rpc("admin_team_list")
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setTeam((data as TeamMember[]) ?? []);
      });
  }, [refresh]);

  const active = (team ?? []).filter((m) => m.active);
  const removed = (team ?? []).filter((m) => !m.active);

  function openNew() {
    setLink(null);
    setEditing({ member: null, email: "", name: "", role: "sales", areas: ROLES.find((r) => r.key === "sales")!.areas });
  }

  function openEdit(m: TeamMember) {
    setLink(null);
    setEditing({ member: m, email: m.email, name: m.name, role: m.team_role, areas: m.team_role === "owner" ? [] : m.areas });
  }

  async function save() {
    if (!editing) return;
    setBusy(true);
    setNotice(null);
    if (editing.member) {
      const { error } = await createClient().rpc("admin_team_save", {
        p_user: editing.member.id,
        p_name: editing.name,
        p_role: editing.role,
        p_areas: editing.areas,
        p_active: true,
      });
      setBusy(false);
      if (error) return setNotice({ ok: false, text: error.message });
      setNotice({ ok: true, text: `${editing.name || editing.email} saved.` });
    } else {
      const res = await fetch("/api/team", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: editing.email, name: editing.name, role: editing.role, areas: editing.areas }),
      });
      const json = await res.json();
      setBusy(false);
      if (!json.added) return setNotice({ ok: false, text: json.error ?? "Could not add" });
      if (json.sent) {
        setNotice({ ok: true, text: `${editing.email} added. They got an email to set their password.` });
      } else {
        setNotice({ ok: false, text: `${editing.email} added, but the email didn't go: ${json.error}. Send them the link below.` });
        setLink(json.setPasswordLink ?? null);
      }
    }
    setEditing(null);
    setRefresh((n) => n + 1);
  }

  async function setActive(m: TeamMember, on: boolean) {
    if (!on && !window.confirm(`Remove ${m.name || m.email} from the team? They lose access at once; their open leads and requests go back to nobody.`)) return;
    const { error } = await createClient().rpc("admin_team_save", {
      p_user: m.id, p_name: m.name, p_role: m.team_role, p_areas: m.areas, p_active: on,
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: on ? `${m.name || m.email} is back on the team.` : `${m.name || m.email} removed.` });
    setRefresh((n) => n + 1);
  }

  async function resend(m: TeamMember) {
    setLink(null);
    const res = await fetch("/api/team", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: m.email, name: m.name, role: m.team_role, resend: true }),
    });
    const json = await res.json();
    if (json.sent) return setNotice({ ok: true, text: `Set-password email sent again to ${m.email}.` });
    setNotice({ ok: false, text: `The email didn't go: ${json.error}. Send them the link below.` });
    setLink(json.setPasswordLink ?? null);
  }

  if (!team) return <Spinner />;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Team"
        subtitle={`${active.length} ${active.length === 1 ? "person" : "people"} can use the admin panel`}
        actions={<Button onClick={openNew}>Add a team member</Button>}
      />
      <Notice notice={notice} />
      {link && (
        <Card>
          <CardBody className="space-y-2">
            <p className="text-sm font-semibold text-ink">One-time set-password link</p>
            <p className="break-all rounded-xl bg-zinc-50 p-3 font-mono text-xs text-zinc-700">{link}</p>
            <Button variant="outline" onClick={() => navigator.clipboard.writeText(link)}>Copy link</Button>
          </CardBody>
        </Card>
      )}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
        {active.map((m) => (
          <MemberCard key={m.id} m={m} isMe={m.id === me?.id}
            onEdit={() => openEdit(m)} onRemove={() => setActive(m, false)} onResend={() => resend(m)} />
        ))}
      </div>

      {removed.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-sm font-bold text-zinc-500">Removed</h2>
          <Card>
            <CardBody>
              <ul className="divide-y divide-zinc-100">
                {removed.map((m) => (
                  <li key={m.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5">
                    <div className="min-w-0">
                      <p className="font-semibold text-zinc-600">{m.name || m.email}</p>
                      <p className="text-xs text-zinc-400">{m.email} · was {roleLabel(m.team_role)}</p>
                    </div>
                    <Button variant="outline" onClick={() => setActive(m, true)}>Bring back</Button>
                  </li>
                ))}
              </ul>
            </CardBody>
          </Card>
        </div>
      )}

      <p className="text-xs text-zinc-500">
        Areas are checked by the database too: a person can&apos;t reach another area by typing its address. Everyone
        can see the client list. Every change a team member makes is in the Audit logs with their name.
      </p>

      {editing && (
        <Modal title={editing.member ? `Change ${editing.member.name || editing.member.email}` : "Add a team member"} onClose={() => setEditing(null)}>
          <form
            className="space-y-4"
            onSubmit={(e) => {
              e.preventDefault();
              save();
            }}
          >
            {!editing.member && (
              <div>
                <Label>Email (their login)</Label>
                <Input type="email" required value={editing.email}
                  onChange={(e) => setEditing({ ...editing, email: e.target.value })} placeholder="name@dukania.in" />
              </div>
            )}
            <div>
              <Label>Name</Label>
              <Input value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} placeholder="Their name" />
            </div>
            <div>
              <Label>Role</Label>
              <Select
                value={editing.role}
                disabled={editing.member?.id === me?.id}
                onChange={(e) => {
                  const role = e.target.value as TeamRole;
                  const preset = ROLES.find((r) => r.key === role)!;
                  setEditing({ ...editing, role, areas: role === "custom" ? editing.areas : preset.areas });
                }}
              >
                {ROLES.map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
              </Select>
            </div>
            {editing.role !== "owner" && (
              <div>
                <Label>What they can use</Label>
                <div className="space-y-1.5">
                  {AREAS.map((a) => (
                    <label key={a.key} className="flex cursor-pointer items-start gap-2.5 rounded-xl px-2 py-1.5 hover:bg-zinc-50">
                      <input
                        type="checkbox"
                        className="mt-0.5 h-4 w-4 accent-[var(--brand)]"
                        checked={editing.areas.includes(a.key)}
                        onChange={(e) => {
                          const areas = e.target.checked
                            ? [...editing.areas, a.key]
                            : editing.areas.filter((x) => x !== a.key);
                          const preset = ROLES.find((r) => r.key === editing.role)!;
                          const same = preset.areas.length === areas.length && preset.areas.every((x) => areas.includes(x));
                          setEditing({ ...editing, areas, role: same ? editing.role : "custom" });
                        }}
                      />
                      <span>
                        <span className="block text-sm font-semibold text-ink">{a.label}</span>
                        <span className="block text-xs text-zinc-500">{a.hint}</span>
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            )}
            {editing.role === "owner" && editing.member?.id !== me?.id && (
              <p className="rounded-xl bg-amber-50 px-3.5 py-2.5 text-sm text-amber-800">
                An owner can do everything, including changing the team and prices.
              </p>
            )}
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit" disabled={busy || (editing.role !== "owner" && editing.areas.length === 0)}>
                {busy ? "Saving…" : editing.member ? "Save" : "Add and email them"}
              </Button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}

function MemberCard({ m, isMe, onEdit, onRemove, onResend }: {
  m: TeamMember; isMe: boolean; onEdit: () => void; onRemove: () => void; onResend: () => void;
}) {
  return (
    <Card>
      <CardBody className="space-y-3">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="truncate font-bold text-ink">{m.name || m.email}{isMe && <span className="font-medium text-zinc-400"> (you)</span>}</p>
            <p className="truncate text-xs text-zinc-500">{m.email}</p>
          </div>
          <Badge color={m.team_role === "owner" ? "purple" : "blue"}>{roleLabel(m.team_role)}</Badge>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {m.team_role === "owner" ? (
            <span className="text-xs text-zinc-600">Everything, and the team</span>
          ) : (
            AREAS.filter((a) => m.areas.includes(a.key)).map((a) => (
              <span key={a.key} className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-medium text-zinc-700">{a.label}</span>
            ))
          )}
        </div>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-zinc-500">
          <span>{m.last_seen_at ? `Last seen ${dateTimeStr(m.last_seen_at)}` : "Hasn't signed in yet"}</span>
          <span className={m.two_step ? "text-emerald-700" : "text-amber-700"}>
            {m.two_step ? "Two-step login on" : "Two-step login off"}
          </span>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" onClick={onEdit}>Change</Button>
          {!isMe && !m.last_seen_at && <Button variant="ghost" onClick={onResend}>Send the email again</Button>}
          {!isMe && <Button variant="ghost" onClick={onRemove}>Remove</Button>}
        </div>
      </CardBody>
    </Card>
  );
}
