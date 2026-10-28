"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Select, Spinner, StatCard } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { memberName, useMe, useTeam } from "@/components/me";
import type { TeamMember } from "@/lib/team";
import { dateTimeStr } from "@/lib/format";
import {
  KINDS, PRIORITIES, duration, fillReply, kindOf, needsReply, overdue, priorityOf, waitingHours,
} from "@/lib/support";
import { SuggestionsBoard } from "./suggestions";
import { SavedReplies } from "./saved-replies";

/* eslint-disable @typescript-eslint/no-explicit-any */

const FILTERS = [
  ["needs", "Needs reply"],
  ["waiting", "Waiting on shop"],
  ["resolved", "Resolved"],
  ["all", "All"],
] as const;

const TABS = [
  ["requests", "Requests"],
  ["suggestions", "Suggestions board"],
  ["replies", "Saved replies"],
] as const;

const statusColor = (t: any) => (t.status === "resolved" ? "green" : needsReply(t) ? "red" : "orange");
const statusText = (t: any) => (t.status === "resolved" ? "resolved" : needsReply(t) ? "needs reply" : "waiting on shop");

// Most urgent first: complaints and high priority, then the longest wait.
const rank = (t: any) =>
  (t.kind === "complaint" ? 0 : 10) + PRIORITIES.findIndex((p) => p.key === t.priority);

export default function SupportPage() {
  const [tab, setTab] = useState<string>("requests");
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap gap-2">
        {TABS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            aria-pressed={tab === key}
            className={`rounded-xl px-4 py-2 text-sm font-semibold transition ${tab === key ? "bg-brand text-white" : "bg-white text-zinc-600 ring-1 ring-inset ring-zinc-200 hover:bg-zinc-50"}`}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === "requests" && <Requests />}
      {tab === "suggestions" && <SuggestionsBoard />}
      {tab === "replies" && <SavedReplies />}
    </div>
  );
}

function Requests() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [filter, setFilter] = useState<string>("needs");
  const [kind, setKind] = useState<string>("all");
  const [open, setOpen] = useState<any>(null);
  const [refresh, setRefresh] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  // Whose requests: everyone's, mine, nobody's, or one person's (0098).
  const me = useMe();
  const team = useTeam();
  const [who, setWho] = useState<string>("all");

  useEffect(() => {
    supabase
      .from("support_tickets")
      .select("*, businesses(id, name, phone, owner_name), suggestions(id, title)")
      .order("created_at", { ascending: false })
      .limit(500)
      .then(({ data }) => {
        setRows(data ?? []);
        setNow(Date.now());
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  // The reply clock moves while the page is open.
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 60000);
    return () => clearInterval(id);
  }, []);

  const all = rows ?? [];
  const mineOk = (t: any) =>
    who === "all" ? true
      : who === "mine" ? t.assigned_to === me?.id
      : who === "nobody" ? !t.assigned_to
      : t.assigned_to === who;
  const shown = all
    .filter(mineOk)
    .filter((t) => kind === "all" || t.kind === kind)
    .filter((t) =>
      filter === "all" ? true
        : filter === "needs" ? needsReply(t)
        : filter === "resolved" ? t.status === "resolved"
        : t.status !== "resolved" && !needsReply(t))
    .sort((a, b) =>
      filter === "needs" ? rank(a) - rank(b) || waitingHours(b, now) - waitingHours(a, now) : 0);
  const needsCount = all.filter(needsReply).length;

  // Last 30 days: how fast the first answer came, and the shops' ratings.
  const since = now - 30 * 86400000;
  const recent = all.filter((t) => new Date(t.created_at).getTime() >= since);
  const answered = recent.filter((t) => t.first_reply_at);
  const avgFirst = answered.length
    ? answered.reduce((s, t) => s + (new Date(t.first_reply_at).getTime() - new Date(t.created_at).getTime()), 0) /
      answered.length / 3600000
    : null;
  const rated = all.filter((t) => t.rating && t.rated_at && new Date(t.rated_at).getTime() >= since);
  const avgRating = rated.length ? rated.reduce((s, t) => s + t.rating, 0) / rated.length : null;
  const complaints = all.filter((t) => t.kind === "complaint" && t.status !== "resolved").length;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-zinc-900">Support</h1>
        <p className="text-sm text-zinc-500">
          {needsCount === 0 ? "No one is waiting for you." : `${needsCount} shop${needsCount === 1 ? " is" : "s are"} waiting for your reply.`}
        </p>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Waiting for a reply" value={needsCount} hint={`${all.filter((t) => overdue(t, now)).length} past their time`} />
        <StatCard label="Open complaints" value={complaints} />
        <StatCard label="First reply (30 days)" value={avgFirst === null ? "—" : duration(avgFirst)} hint={`${answered.length} answered`} />
        <StatCard label="Rating (30 days)" value={avgRating === null ? "—" : `${avgRating.toFixed(1)} ★`} hint={`${rated.length} rated`} />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {FILTERS.map(([key, label]) => (
          <button
            key={key}
            onClick={() => setFilter(key)}
            aria-pressed={filter === key}
            className={`rounded-full px-3 py-1 text-xs font-semibold ring-1 ring-inset ${filter === key ? "bg-ink text-white ring-ink" : "bg-white text-zinc-600 ring-zinc-200"}`}
          >
            {label}{key === "needs" && needsCount > 0 ? ` (${needsCount})` : ""}
          </button>
        ))}
        <Select value={kind} onChange={(e) => setKind(e.target.value)} className="max-w-[11rem] py-1 text-xs" aria-label="What about">
          <option value="all">Every kind</option>
          {KINDS.map((k) => <option key={k.key} value={k.key}>{k.label}</option>)}
        </Select>
        <Select value={who} onChange={(e) => setWho(e.target.value)} className="max-w-[12rem] py-1 text-xs" aria-label="Whose requests">
          <option value="all">Everyone&apos;s</option>
          <option value="mine">Mine</option>
          <option value="nobody">Not assigned</option>
          {team.filter((m) => m.active && m.id !== me?.id).map((m) => (
            <option key={m.id} value={m.id}>{m.name || m.email}</option>
          ))}
        </Select>
      </div>

      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <ul className="divide-y divide-zinc-100">
            {shown.map((t) => {
              const k = kindOf(t.kind);
              const p = priorityOf(t.priority);
              const late = overdue(t, now);
              return (
                <li key={t.id}>
                  <button onClick={() => setOpen(t)} className="flex w-full flex-col gap-1.5 px-5 py-4 text-left hover:bg-zinc-50 sm:flex-row sm:items-center sm:justify-between">
                    <span className="min-w-0">
                      <span className="flex flex-wrap items-center gap-2">
                        <Badge color={k.color}>{k.label}</Badge>
                        {(p.key === "urgent" || p.key === "high") && <Badge color="red">{p.label}</Badge>}
                        <span className="font-semibold text-ink">{t.subject}</span>
                      </span>
                      <span className="mt-0.5 block truncate text-xs text-zinc-500">
                        {t.businesses?.name ?? "—"} · {t.message || "no details"}
                        {t.suggestions?.title ? ` · under "${t.suggestions.title}"` : ""}
                      </span>
                    </span>
                    <span className="flex shrink-0 flex-wrap items-center gap-3">
                      {memberName(team, t.assigned_to) && (
                        <span className="text-xs font-medium text-zinc-600">{memberName(team, t.assigned_to)}</span>
                      )}
                      {t.rating && <span className="text-xs font-semibold text-amber-600">{"★".repeat(t.rating)}</span>}
                      {needsReply(t) ? (
                        <span className={`text-xs font-semibold ${late ? "text-red-600" : "text-zinc-500"}`}>
                          waiting {duration(waitingHours(t, now))}
                        </span>
                      ) : (
                        <span className="text-xs text-zinc-500">{dateTimeStr(t.last_shop_message_at ?? t.created_at)}</span>
                      )}
                      <Badge color={statusColor(t)}>{statusText(t)}</Badge>
                    </span>
                  </button>
                </li>
              );
            })}
            {shown.length === 0 && <li className="px-5 py-10 text-center text-sm text-zinc-500">Nothing here.</li>}
          </ul>
        </Card>
      )}

      {open && (
        <TicketDialog
          ticket={open}
          team={team}
          onClose={() => setOpen(null)}
          onChanged={() => setRefresh((n) => n + 1)}
        />
      )}
    </div>
  );
}

/** One request: the conversation, a reply box, kind, priority, suggestion and private notes. */
function TicketDialog({ ticket, team, onClose, onChanged }: {
  ticket: any; team: TeamMember[]; onClose: () => void; onChanged: () => void;
}) {
  const supabase = createClient();
  const [messages, setMessages] = useState<any[] | null>(null);
  const [notes, setNotes] = useState<any[]>([]);
  const [status, setStatus] = useState<string>(ticket.status);
  const [assignee, setAssignee] = useState<string>(ticket.assigned_to ?? "");
  const [kind, setKind] = useState<string>(ticket.kind ?? "question");
  const [priority, setPriority] = useState<string>(ticket.priority ?? "normal");
  const [suggestionId, setSuggestionId] = useState<string>(ticket.suggestion_id ?? "");
  const [suggestions, setSuggestions] = useState<any[]>([]);
  const [newIdea, setNewIdea] = useState("");
  const [savedReplies, setSavedReplies] = useState<any[]>([]);
  const [reply, setReply] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const b = ticket.businesses ?? {};
  const thread = useRef<HTMLDivElement>(null);

  // Keep the newest message in view.
  useEffect(() => {
    thread.current?.scrollTo({ top: thread.current.scrollHeight });
  }, [messages]);

  useEffect(() => {
    supabase.from("support_messages").select("*").eq("ticket_id", ticket.id).order("created_at")
      .then(({ data }) => setMessages(data ?? []));
    supabase.from("admin_notes").select("*").eq("ticket_id", ticket.id).order("created_at")
      .then(({ data }) => setNotes(data ?? []));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  useEffect(() => {
    supabase.from("suggestions").select("id, title, status").order("created_at", { ascending: false })
      .then(({ data }) => setSuggestions(data ?? []));
    supabase.from("saved_replies").select("id, title, body").order("title")
      .then(({ data }) => setSavedReplies(data ?? []));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function send(resolve: boolean) {
    if (!reply.trim()) return;
    setBusy(true);
    const newStatus = resolve ? "resolved" : "in_progress";
    const { error } = await supabase.rpc("admin_reply_ticket", { p_ticket: ticket.id, p_body: reply.trim(), p_status: newStatus });
    setBusy(false);
    if (error) return setNotice({ ok: false, text: error.message });
    // Tell the shop's phones; the reply is in the app either way.
    supabase.functions.invoke("support-push", { body: { ticket_id: ticket.id } }).catch(() => {});
    setReply("");
    setStatus(newStatus);
    setNotice({ ok: true, text: resolve ? "Reply sent and resolved — the shop can now rate it in the app." : "Reply sent — the shop sees it in the app under Support." });
    setRefresh((n) => n + 1);
    onChanged();
  }

  async function changeStatus(next: string) {
    const { error } = await supabase.rpc("admin_set_ticket_status", { p_ticket: ticket.id, p_status: next });
    if (error) return setNotice({ ok: false, text: error.message });
    setStatus(next);
    onChanged();
  }

  async function changeMeta(nextKind: string, nextPriority: string) {
    const { error } = await supabase.rpc("admin_set_ticket_meta", { p_ticket: ticket.id, p_kind: nextKind, p_priority: nextPriority });
    if (error) return setNotice({ ok: false, text: error.message });
    setKind(nextKind);
    setPriority(nextPriority);
    onChanged();
  }

  /** Put the request under a suggestion (existing or new), or take it out. */
  async function linkSuggestion(id: string, title = "") {
    const { data, error } = await supabase.rpc("admin_link_suggestion", {
      p_ticket: ticket.id, p_suggestion: id || null, p_title: title || null,
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setSuggestionId((data as string) ?? "");
    if (title) {
      setSuggestions((s) => [{ id: data, title, status: "new" }, ...s]);
      setNewIdea("");
    }
    setNotice({ ok: true, text: data ? "Added to the suggestions board — when you mark it done, this shop is told." : "Taken off the suggestions board." });
    onChanged();
  }

  /** Give the request to a team member who has Support (0098), or to nobody. */
  async function assign(userId: string) {
    const { error } = await supabase.rpc("admin_assign", { p_kind: "ticket", p_id: ticket.id, p_user: userId || null });
    if (error) return setNotice({ ok: false, text: error.message });
    setAssignee(userId);
    onChanged();
  }

  async function addNote() {
    if (!note.trim()) return;
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from("admin_notes").insert({
      business_id: ticket.business_id, ticket_id: ticket.id, note: note.trim(), created_by: user?.id ?? null,
    });
    if (error) return setNotice({ ok: false, text: error.message });
    setNote("");
    setRefresh((n) => n + 1);
  }

  const openIdeas = suggestions.filter((s) => s.id === suggestionId || !["done", "declined"].includes(s.status));

  return (
    <Modal title={ticket.subject} onClose={onClose} wide>
      <div className="space-y-4 text-sm">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-zinc-600">
            <Link href={`/clients/${b.id}`} className="font-semibold text-brand hover:underline">{b.name}</Link>
            {b.owner_name ? ` · ${b.owner_name}` : ""} · opened {dateTimeStr(ticket.created_at)}
          </p>
          <div className="flex flex-wrap items-center gap-2">
            {b.phone && (
              <a href={waLink(b.phone, `Namaste! This is Dukania, about your support request "${ticket.subject}".`)} target="_blank" rel="noreferrer">
                <Button variant="outline">WhatsApp</Button>
              </a>
            )}
            {status === "resolved"
              ? <Button variant="outline" onClick={() => changeStatus("open")}>Reopen</Button>
              : <Button variant="outline" onClick={() => changeStatus("resolved")}>Mark resolved</Button>}
          </div>
        </div>

        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <Select value={kind} onChange={(e) => changeMeta(e.target.value, priority)} aria-label="What about">
            {KINDS.map((k) => <option key={k.key} value={k.key}>{k.label}</option>)}
          </Select>
          <Select value={priority} onChange={(e) => changeMeta(kind, e.target.value)} aria-label="Priority">
            {PRIORITIES.map((p) => <option key={p.key} value={p.key}>{p.label} — answer within {duration(p.hours)}</option>)}
          </Select>
          <Select value={assignee} onChange={(e) => assign(e.target.value)} aria-label="With">
            <option value="">With nobody</option>
            {team
              .filter((m) => (m.active && m.areas.includes("support")) || m.id === assignee)
              .map((m) => (
                <option key={m.id} value={m.id}>With {m.name || m.email}</option>
              ))}
          </Select>
        </div>

        <Notice notice={notice} />
        {ticket.requested_plan_id && status !== "resolved" && (
          <p className="rounded-xl bg-blue-50 px-4 py-3 text-blue-800">
            This shop is asking for a plan change. Agree the price with them, then open{" "}
            <Link href={`/clients/${b.id}`} className="font-semibold underline">the client</Link> and press Renew with
            the new plan — this request then answers and closes itself.
          </p>
        )}
        {ticket.rating && (
          <p className="rounded-xl bg-amber-50 px-4 py-3 text-amber-900">
            The shop rated this <b>{"★".repeat(ticket.rating)}{"☆".repeat(5 - ticket.rating)}</b>
            {ticket.rating_note ? ` — "${ticket.rating_note}"` : ""}
          </p>
        )}

        {kind === "suggestion" && (
          <div className="space-y-2 rounded-xl bg-violet-50 p-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-violet-700">On the suggestions board</p>
            <div className="flex flex-col gap-2 sm:flex-row">
              <Select value={suggestionId} onChange={(e) => linkSuggestion(e.target.value)} aria-label="Suggestion">
                <option value="">Not on the board yet</option>
                {openIdeas.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}
              </Select>
            </div>
            {!suggestionId && (
              <div className="flex gap-2">
                <input
                  value={newIdea}
                  onChange={(e) => setNewIdea(e.target.value)}
                  placeholder="Or a new suggestion, e.g. Dark mode"
                  className="w-full rounded-xl border border-zinc-200 bg-white px-3 py-1.5 text-sm outline-none focus:border-brand"
                />
                <Button variant="outline" onClick={() => linkSuggestion("", newIdea.trim())} disabled={!newIdea.trim()}>Add</Button>
              </div>
            )}
          </div>
        )}

        <div ref={thread} className="max-h-[36dvh] min-h-24 space-y-2 overflow-y-auto rounded-xl bg-zinc-50 p-3">
          <Bubble mine={false} body={ticket.message || ticket.subject} at={ticket.created_at} />
          {messages === null ? <Spinner /> : messages.map((m) => (
            <Bubble key={m.id} mine={m.from_softraxa} body={m.body} at={m.created_at} />
          ))}
        </div>

        <div>
          {savedReplies.length > 0 && (
            <Select
              value=""
              onChange={(e) => {
                const r = savedReplies.find((x) => x.id === e.target.value);
                if (r) setReply((cur) => (cur.trim() ? `${cur.trimEnd()}\n\n` : "") + fillReply(r.body, b.name, b.owner_name));
              }}
              className="mb-2 max-w-xs py-1 text-xs"
              aria-label="Saved reply"
            >
              <option value="">Use a saved reply…</option>
              {savedReplies.map((r) => <option key={r.id} value={r.id}>{r.title}</option>)}
            </Select>
          )}
          <textarea
            value={reply}
            onChange={(e) => setReply(e.target.value)}
            rows={3}
            placeholder="Write your reply — the shop reads it in the app"
            className="w-full rounded-xl border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10"
          />
          <div className="mt-2 flex flex-wrap justify-end gap-2">
            <Button variant="outline" onClick={() => send(true)} disabled={busy || !reply.trim()}>Reply &amp; resolve</Button>
            <Button onClick={() => send(false)} disabled={busy || !reply.trim()}>{busy ? "Sending…" : "Reply"}</Button>
          </div>
        </div>

        <div className="space-y-2 rounded-xl border border-dashed border-zinc-300 p-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Private notes — only the team sees these</p>
            {notes.map((n) => (
              <p key={n.id} className="text-sm">
                <span className="text-xs text-zinc-400">{dateTimeStr(n.created_at)}{memberName(team, n.created_by) ? ` · ${memberName(team, n.created_by)}` : ""}</span> · {n.note}
              </p>
            ))}
            <div className="flex gap-2">
              <input
                value={note}
                onChange={(e) => setNote(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && addNote()}
                placeholder="Add a note…"
                className="w-full rounded-xl border border-zinc-200 px-3 py-1.5 text-sm outline-none focus:border-brand"
              />
              <Button variant="outline" onClick={addNote} disabled={!note.trim()}>Add</Button>
            </div>
        </div>
      </div>
    </Modal>
  );
}

function Bubble({ mine, body, at }: { mine: boolean; body: string; at: string }) {
  return (
    <div className={`flex ${mine ? "justify-end" : "justify-start"}`}>
      <div className={`max-w-[85%] rounded-2xl px-3.5 py-2 ${mine ? "bg-brand text-white" : "bg-white text-ink ring-1 ring-zinc-200"}`}>
        <p className="whitespace-pre-wrap break-words">{body}</p>
        <p className={`mt-1 text-[10px] ${mine ? "text-white/70" : "text-zinc-400"}`}>{mine ? "Dukania" : "Shop"} · {dateTimeStr(at)}</p>
      </div>
    </div>
  );
}
