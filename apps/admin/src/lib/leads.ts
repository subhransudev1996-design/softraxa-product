/* eslint-disable @typescript-eslint/no-explicit-any */

/** The pipeline (migration 0100); "converted" is shown as Won. */
export const STAGES = [
  { key: "new", label: "New", color: "blue" },
  { key: "contacted", label: "Contacted", color: "orange" },
  { key: "demo", label: "Demo given", color: "purple" },
  { key: "trial", label: "On trial", color: "blue" },
  { key: "negotiation", label: "Negotiation", color: "orange" },
  { key: "converted", label: "Won", color: "green" },
  { key: "lost", label: "Lost", color: "red" },
] as const;

export const LEAD_STATUSES = STAGES.map((s) => s.key);
export const OPEN_STAGES: string[] = ["new", "contacted", "demo", "trial", "negotiation"];
export const isOpenLead = (status: string) => OPEN_STAGES.includes(status);

export const stageOf = (status?: string) => STAGES.find((s) => s.key === status) ?? STAGES[0];
export const leadStatusBadge = (status?: string) => stageOf(status).color;
export const stageLabel = (status?: string) => stageOf(status).label;

export const TEMPERATURES = [
  { key: "hot", label: "Hot", color: "red", dot: "bg-red-500" },
  { key: "warm", label: "Warm", color: "orange", dot: "bg-amber-400" },
  { key: "cold", label: "Cold", color: "blue", dot: "bg-sky-400" },
] as const;
export const temperatureOf = (t?: string) => TEMPERATURES.find((x) => x.key === t) ?? TEMPERATURES[1];

export const LOST_REASONS = [
  "Price too high",
  "Chose another software",
  "Not ready — maybe later",
  "Not interested",
  "No reply",
  "Other",
];

export const LEAD_SOURCES: [string, string][] = [
  ["walk_in", "Walk-in"],
  ["referral", "Referral"],
  ["field_visit", "Field visit"],
  ["phone_call", "Phone call"],
  ["whatsapp", "WhatsApp"],
  ["social", "Social media"],
  ["website", "Website"],
  ["app_signup", "Signed up in the app"],
  ["import", "Imported"],
  ["other", "Other"],
];
export const sourceLabel = (s?: string) =>
  LEAD_SOURCES.find(([k]) => k === s)?.[1] ?? (s ? s.replace(/_/g, " ") : "—");

export const ACTIVITY_TYPES: [string, string][] = [
  ["call", "Phone call"],
  ["whatsapp", "WhatsApp"],
  ["visit", "Shop visit"],
  ["demo", "Demo"],
  ["quote", "Quote sent"],
  ["note", "Note"],
];

/** "new → contacted" in the stage log, with the stages' names. */
export const stageNote = (note: string) =>
  note.replace(/\b(new|contacted|demo|trial|negotiation|converted|lost)\b/g, (s) => stageLabel(s));

/** Leads and clients with the same phone (admin_find_duplicates, 0100). */
export type Duplicates = { leads: { id: string; shop_name: string; status: string }[]; clients: { id: string; name: string }[] };

export async function findDuplicates(supabase: any, phone: string, exclude?: string): Promise<Duplicates | null> {
  if (phone.replace(/\D/g, "").length < 10) return null;
  const { data, error } = await supabase.rpc("admin_find_duplicates", { p_phone: phone, p_exclude: exclude ?? null });
  if (error || !data) return null;
  const d = data as Duplicates;
  return d.leads.length || d.clients.length ? d : null;
}
