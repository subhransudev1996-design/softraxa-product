"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, Spinner } from "@/components/ui";
import { Modal, Notice, waLink } from "@/components/ops";
import { dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const FILTERS = [
  ["needs", "Needs reply"],
  ["waiting", "Waiting on shop"],
  ["resolved", "Resolved"],
  ["all", "All"],
] as const;

// Same rule as ticket_needs_reply() (migration 0054): the shop wrote last.
const needsReply = (t: any) =>
  t.status !== "resolved" &&
  (!t.last_reply_at || new Date(t.last_shop_message_at ?? t.created_at) > new Date(t.last_reply_at));

const statusColor = (t: any) => (t.status === "resolved" ? "green" : needsReply(t) ? "red" : "orange");
const statusText = (t: any) => (t.status === "resolved" ? "resolved" : needsReply(t) ? "needs reply" : "waiting on shop");

export default function SupportPage() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [filter, setFilter] = useState<string>("needs");
  const [open, setOpen] = useState<any>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase
      .from("support_tickets")
      .select("*, businesses(id, name, phone, owner_name)")
      .order("created_at", { ascending: false })
      .limit(300)
      .then(({ data }) => setRows(data ?? []));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  const shown = (rows ?? []).filter((t) =>
    filter === "all" ? true
      : filter === "needs" ? needsReply(t)
      : filter === "resolved" ? t.status === "resolved"
      : t.status !== "resolved" && !needsReply(t));
  const needsCount = (rows ?? []).filter(needsReply).length;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-zinc-900">Support</h1>
        <p className="text-sm text-zinc-500">
          {needsCount === 0 ? "No one is waiting for you." : `${needsCount} shop${needsCount === 1 ? " is" : "s are"} waiting for your reply.`}
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
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
      </div>

      {!rows ? (
        <Spinner />
      ) : (
        <Card>
          <ul className="divide-y divide-zinc-100">
            {shown.map((t) => (
              <li key={t.id}>
                <button onClick={() => setOpen(t)} className="flex w-full flex-col gap-1 px-5 py-4 text-left hover:bg-zinc-50 sm:flex-row sm:items-center sm:justify-between">
                  <span className="min-w-0">
                    <span className="block font-semibold text-ink">{t.subject}</span>
                    <span className="block truncate text-xs text-zinc-500">
                      {t.businesses?.name ?? "—"} · {t.message || "no details"}
                    </span>
                  </span>
                  <span className="flex shrink-0 items-center gap-3">
                    <span className="text-xs text-zinc-500">{dateTimeStr(t.last_shop_message_at ?? t.created_at)}</span>
                    <Badge color={statusColor(t)}>{statusText(t)}</Badge>
                  </span>
                </button>
              </li>
            ))}
            {shown.length === 0 && <li className="px-5 py-10 text-center text-sm text-zinc-500">Nothing here.</li>}
          </ul>
        </Card>
      )}

      {open && (
        <TicketDialog
          ticket={open}
          onClose={() => setOpen(null)}
          onChanged={() => setRefresh((n) => n + 1)}
        />
      )}
    </div>
  );
}

/** One ticket: the conversation, a reply box, status and private notes. */
function TicketDialog({ ticket, onClose, onChanged }: { ticket: any; onClose: () => void; onChanged: () => void }) {
  const supabase = createClient();
  const [messages, setMessages] = useState<any[] | null>(null);
  const [notes, setNotes] = useState<any[]>([]);
  const [status, setStatus] = useState<string>(ticket.status);
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
    setNotice({ ok: true, text: "Reply sent — the shop sees it in the app under Support." });
    setRefresh((n) => n + 1);
    onChanged();
  }

  async function changeStatus(next: string) {
    const { error } = await supabase.rpc("admin_set_ticket_status", { p_ticket: ticket.id, p_status: next });
    if (error) return setNotice({ ok: false, text: error.message });
    setStatus(next);
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

  return (
    <Modal title={ticket.subject} onClose={onClose} wide>
      <div className="space-y-4 text-sm">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-zinc-600">
            <Link href={`/clients/${b.id}`} className="font-semibold text-brand hover:underline">{b.name}</Link>
            {b.owner_name ? ` · ${b.owner_name}` : ""} · opened {dateTimeStr(ticket.created_at)}
          </p>
          <div className="flex items-center gap-2">
            {b.phone && (
              <a href={waLink(b.phone, `Namaste! This is SOFTRAXA, about your support request "${ticket.subject}".`)} target="_blank" rel="noreferrer">
                <Button variant="outline">WhatsApp</Button>
              </a>
            )}
            {status === "resolved"
              ? <Button variant="outline" onClick={() => changeStatus("open")}>Reopen</Button>
              : <Button variant="outline" onClick={() => changeStatus("resolved")}>Mark resolved</Button>}
          </div>
        </div>
        <Notice notice={notice} />
        {ticket.requested_plan_id && status !== "resolved" && (
          <p className="rounded-xl bg-blue-50 px-4 py-3 text-blue-800">
            This shop is asking for a plan change. Agree the price with them, then open{" "}
            <Link href={`/clients/${b.id}`} className="font-semibold underline">the client</Link> and press Renew with
            the new plan — this request then answers and closes itself.
          </p>
        )}

        <div ref={thread} className="max-h-[36dvh] min-h-24 space-y-2 overflow-y-auto rounded-xl bg-zinc-50 p-3">
          <Bubble mine={false} body={ticket.message || ticket.subject} at={ticket.created_at} />
          {messages === null ? <Spinner /> : messages.map((m) => (
            <Bubble key={m.id} mine={m.from_softraxa} body={m.body} at={m.created_at} />
          ))}
        </div>

        <div>
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
            <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">Private notes — only you see these</p>
            {notes.map((n) => (
              <p key={n.id} className="text-sm"><span className="text-xs text-zinc-400">{dateTimeStr(n.created_at)}</span> · {n.note}</p>
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
        <p className={`mt-1 text-[10px] ${mine ? "text-white/70" : "text-zinc-400"}`}>{mine ? "You" : "Shop"} · {dateTimeStr(at)}</p>
      </div>
    </div>
  );
}
