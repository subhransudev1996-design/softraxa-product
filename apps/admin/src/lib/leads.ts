export const leadStatusBadge = (status?: string) =>
  ({ new: "blue", contacted: "orange", demo: "purple", converted: "green", lost: "red" }[
    status ?? ""
  ] ?? "zinc");

export const LEAD_SOURCES: [string, string][] = [
  ["walk_in", "Walk-in"],
  ["referral", "Referral"],
  ["field_visit", "Field visit"],
  ["phone_call", "Phone call"],
  ["whatsapp", "WhatsApp"],
  ["social", "Social media"],
  ["website", "Website"],
  ["other", "Other"],
];

export const LEAD_STATUSES = ["new", "contacted", "demo", "converted", "lost"] as const;

export const ACTIVITY_TYPES: [string, string][] = [
  ["call", "Phone call"],
  ["whatsapp", "WhatsApp"],
  ["visit", "Shop visit"],
  ["demo", "Demo"],
  ["note", "Note"],
];
