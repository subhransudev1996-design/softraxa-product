/**
 * Support requests (migrations 0054, 0099): what a request is about, its
 * priority and the reply clock.
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

export const KINDS = [
  { key: "question", label: "Question", color: "blue" },
  { key: "complaint", label: "Complaint", color: "red" },
  { key: "bug", label: "Problem in the app", color: "orange" },
  { key: "suggestion", label: "Suggestion", color: "purple" },
  { key: "billing", label: "Billing / plan", color: "green" },
  { key: "other", label: "Other", color: "zinc" },
] as const;

export const PRIORITIES = [
  { key: "urgent", label: "Urgent", hours: 1 },
  { key: "high", label: "High", hours: 4 },
  { key: "normal", label: "Normal", hours: 24 },
  { key: "low", label: "Low", hours: 72 },
] as const;

export const SUGGESTION_STATUSES = [
  { key: "new", label: "New", color: "zinc" },
  { key: "planned", label: "Planned", color: "blue" },
  { key: "in_progress", label: "Being built", color: "orange" },
  { key: "done", label: "Done", color: "green" },
  { key: "declined", label: "Not doing", color: "red" },
] as const;

export const kindOf = (k: string | null | undefined) => KINDS.find((x) => x.key === k) ?? KINDS[0];
export const priorityOf = (p: string | null | undefined) => PRIORITIES.find((x) => x.key === p) ?? PRIORITIES[2];
export const suggestionStatusOf = (s: string) => SUGGESTION_STATUSES.find((x) => x.key === s) ?? SUGGESTION_STATUSES[0];

// Same rule as ticket_needs_reply() (migration 0054): the shop wrote last.
export const needsReply = (t: any) =>
  t.status !== "resolved" &&
  (!t.last_reply_at || new Date(t.last_shop_message_at ?? t.created_at) > new Date(t.last_reply_at));

/** Hours the shop has been waiting for an answer (0 when it isn't waiting). */
export const waitingHours = (t: any, now = Date.now()) =>
  needsReply(t) ? (now - new Date(t.last_shop_message_at ?? t.created_at).getTime()) / 3600000 : 0;

/** Waiting longer than the priority allows (urgent 1h, high 4h, normal 24h, low 72h). */
export const overdue = (t: any, now = Date.now()) => waitingHours(t, now) > priorityOf(t.priority).hours;

/** "45m", "3h 20m", "2d 4h". */
export function duration(hours: number): string {
  const m = Math.max(0, Math.round(hours * 60));
  if (m < 60) return `${m}m`;
  if (m < 24 * 60) return `${Math.floor(m / 60)}h${m % 60 ? ` ${m % 60}m` : ""}`;
  const h = Math.floor(m / 60);
  return `${Math.floor(h / 24)}d${h % 24 ? ` ${h % 24}h` : ""}`;
}

/** A saved reply with the shop's name and the owner's name filled in. */
export const fillReply = (body: string, shop: string, owner: string) =>
  body.replaceAll("{shop}", shop || "your shop").replaceAll("{owner}", owner || "");
