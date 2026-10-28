/**
 * The admin team (migration 0098): who is signed in and which areas of
 * the panel they may use. The database enforces the same areas; hiding
 * pages here only keeps the menu tidy.
 */

export type Area =
  | "clients" | "payments" | "support" | "leads" | "marketing" | "catalog"
  | "plans" | "settings" | "website" | "system";

export type TeamRole = "owner" | "sales" | "support" | "accounts" | "custom";

export type Me = {
  id: string;
  name: string;
  email: string;
  team_role: TeamRole;
  is_owner: boolean;
  areas: Area[];
};

export type TeamMember = {
  id: string;
  name: string;
  email: string;
  team_role: TeamRole;
  areas: Area[];
  active: boolean;
  last_seen_at: string | null;
  created_at: string;
  two_step: boolean;
};

export const AREAS: { key: Area; label: string; hint: string }[] = [
  { key: "clients", label: "Clients", hint: "Add clients, block or unblock, switch features (everyone can see clients)" },
  { key: "payments", label: "Payments & sales", hint: "Verify payments, renew, record sales and add-ons, Sales page" },
  { key: "support", label: "Support", hint: "Answer the shops' support requests" },
  { key: "leads", label: "Leads", hint: "Leads and follow-ups" },
  { key: "marketing", label: "Marketing", hint: "Announcements, promo codes, referrals, campaigns and their costs" },
  { key: "catalog", label: "Master products", hint: "Master products and software" },
  { key: "plans", label: "Plans & prices", hint: "Plans, prices and the lowest price" },
  { key: "settings", label: "Settings", hint: "Payment details, contact numbers, receipts" },
  { key: "website", label: "Website", hint: "The website CMS" },
  { key: "system", label: "System", hint: "Reconciliation, system health, audit logs" },
];

export const ROLES: { key: TeamRole; label: string; areas: Area[] }[] = [
  { key: "owner", label: "Owner — everything, and manages the team", areas: [] },
  { key: "sales", label: "Sales", areas: ["clients", "leads"] },
  { key: "support", label: "Support", areas: ["support", "catalog"] },
  { key: "accounts", label: "Accounts", areas: ["payments"] },
  { key: "custom", label: "Custom — pick the areas", areas: [] },
];

export const roleLabel = (r: TeamRole) =>
  ({ owner: "Owner", sales: "Sales", support: "Support", accounts: "Accounts", custom: "Custom" })[r] ?? r;

/** The area a page belongs to; null = every team member. "owner" = the owner only. */
export function areaFor(pathname: string): Area | "owner" | null {
  const first = "/" + (pathname.split("/")[1] ?? "");
  if (pathname.startsWith("/clients/new")) return "clients";
  return (
    {
      "/payments": "payments",
      "/sales": "payments",
      "/support": "support",
      "/leads": "leads",
      "/marketing": "marketing",
      "/catalog": "catalog",
      "/products": "catalog",
      "/plans": "plans",
      "/settings": "settings",
      "/reconciliation": "system",
      "/health": "system",
      "/audit": "system",
      "/team": "owner",
    } as Record<string, Area | "owner">
  )[first] ?? null;
}

export function canUse(me: Me | null, area: Area | "owner" | null): boolean {
  if (!area) return true;
  if (!me) return false;
  if (me.is_owner) return true;
  return area !== "owner" && me.areas.includes(area);
}
