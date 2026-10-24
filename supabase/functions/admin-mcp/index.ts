// admin-mcp — the Dukania admin panel as an MCP server, for ChatGPT and
// Claude ("connectors"). It reads what the admin panel shows and runs the
// same admin actions, as the signed-in SOFTRAXA admin.
//
// Login: Supabase Auth's OAuth 2.1 server. A request without a token gets
// 401 with a link to this server's OAuth metadata; the AI app then sends
// you to www.softraxa.in/oauth/consent to sign in with your admin account
// and approve it. Every call runs with YOUR login, so the database's own
// checks (platform admin only, RLS, audit log) apply exactly as in the
// admin panel. Non-admin accounts get nothing.
//
// Actions (anything that changes data) never run on the first call: they
// return what WOULD happen and need a second call with confirm: true,
// which the AI makes only after you say yes in the chat.
//
// Protocol: MCP over Streamable HTTP, stateless, JSON responses
// (POST = JSON-RPC; no server-sent events).
//
// Setup:
//   1. Dashboard > Authentication > OAuth Server: enable, Authorization
//      Path "/oauth/consent", allow dynamic client registration.
//      (Site URL must be https://www.softraxa.in.)
//   2. supabase functions deploy admin-mcp --no-verify-jwt
//      (the function checks tokens itself, so it can answer 401 with the
//      discovery link MCP clients need).
//   3. Add the connector in ChatGPT / Claude with the URL
//      https://<project-ref>.supabase.co/functions/v1/admin-mcp

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FN_URL = `${SUPABASE_URL}/functions/v1/admin-mcp`;
const METADATA_URL = `${FN_URL}/.well-known/oauth-protected-resource`;
const PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, mcp-protocol-version, mcp-session-id, x-client-info, apikey",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Expose-Headers": "WWW-Authenticate, Mcp-Session-Id",
};

const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", ...extra },
  });

// ---------------------------------------------------------------- tools

type Ctx = { db: SupabaseClient; userId: string; email: string; token: string };
type Args = Record<string, unknown>;
type Tool = {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  write?: boolean;
  /** For actions: a one-line description of what the call would do. */
  preview?: (ctx: Ctx, a: Args) => Promise<string>;
  run: (ctx: Ctx, a: Args) => Promise<unknown>;
};

const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
const num = (v: unknown) => (typeof v === "number" ? v : Number(v));
const isUuid = (v: unknown) =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const ist = (d = new Date()) => new Date(d.getTime() + 5.5 * 3600e3).toISOString().slice(0, 10);

function must<T>(r: { data: T; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message);
  return r.data;
}

function obj(props: Record<string, unknown>, required: string[] = []) {
  return { type: "object", properties: props, required, additionalProperties: false };
}
const confirmProp = {
  confirm: {
    type: "boolean",
    description:
      "Leave out (or false) first: you get a preview of the change. Only after the user has said yes in the chat, call again with confirm: true.",
  },
};

/** A shop's name for previews. */
async function clientName(ctx: Ctx, id: unknown): Promise<string> {
  if (!isUuid(id)) throw new Error("client_id must be a client's id — find it with find_clients first");
  const r = await ctx.db.from("businesses").select("name").eq("id", id).maybeSingle();
  if (!r.data) throw new Error("No client with that id");
  return r.data.name as string;
}

/** The latest subscription row of a business (from an embedded list). */
function latestSub(subs: Array<Record<string, unknown>> | null | undefined) {
  return [...(subs ?? [])].sort((a, b) =>
    String(b.created_at).localeCompare(String(a.created_at))
  )[0] ?? null;
}

const TOOLS: Tool[] = [
  // -------------------------------------------------------------- reads
  {
    name: "today_overview",
    title: "Today in the admin panel",
    description:
      "What needs attention today (renewals due, payment claims to verify, open support tickets, trials ending, shops not billing) plus headline numbers: paying shops, trials, revenue. Start here for 'what should I do today?'.",
    inputSchema: obj({}),
    run: async (ctx) => ({
      today: must(await ctx.db.rpc("get_admin_today")),
      stats: must(await ctx.db.rpc("get_admin_dashboard")),
    }),
  },
  {
    name: "find_clients",
    title: "Find clients (shops)",
    description:
      "List Dukania client shops with their plan and subscription. Filter by text (name, owner, phone, email, GST), by subscription status, or shops expiring within N days. Use it to get a client_id for other tools.",
    inputSchema: obj({
      search: { type: "string", description: "Part of the shop name, owner, phone, email or GSTIN." },
      status: { type: "string", enum: ["trial", "active", "expired", "suspended"] },
      expiring_within_days: { type: "integer", minimum: 0, maximum: 366 },
      limit: { type: "integer", minimum: 1, maximum: 200, default: 50 },
    }),
    run: async (ctx, a) => {
      let q = ctx.db
        .from("businesses")
        .select(
          "id, name, owner_name, business_type, phone, email, gst_number, is_active, onboarding_done, created_at, subscriptions(status, expiry_date, grace_days, created_at, plans(name))",
        )
        .order("created_at", { ascending: false })
        .limit(500);
      const s = str(a.search).replace(/[%,()]/g, " ");
      if (s) {
        q = q.or(
          ["name", "owner_name", "phone", "email", "gst_number"].map((c) => `${c}.ilike.%${s}%`).join(","),
        );
      }
      const rows = must(await q) as Array<Record<string, unknown>>;
      const today = ist();
      const until = a.expiring_within_days == null
        ? null
        : ist(new Date(Date.now() + num(a.expiring_within_days) * 864e5));
      const out = rows.map((b) => {
        const sub = latestSub(b.subscriptions as Array<Record<string, unknown>>);
        const { subscriptions: _s, ...rest } = b;
        return {
          ...rest,
          plan: (sub?.plans as { name?: string } | null)?.name ?? null,
          subscription_status: sub?.status ?? null,
          expiry_date: sub?.expiry_date ?? null,
        };
      }).filter((b) =>
        (!a.status || b.subscription_status === a.status) &&
        (until == null ||
          (b.expiry_date != null && String(b.expiry_date) >= today && String(b.expiry_date) <= until))
      );
      const limit = Math.min(num(a.limit) || 50, 200);
      return { total: out.length, clients: out.slice(0, limit) };
    },
  },
  {
    name: "get_client",
    title: "One client in detail",
    description:
      "Everything about one client shop: details, subscription and plan, features, staff, recent subscription payments, pending payment claims, recent support tickets, admin notes, recent admin history and usage (products, bills, last bill).",
    inputSchema: obj({ client_id: { type: "string", description: "From find_clients." } }, ["client_id"]),
    run: async (ctx, a) => {
      const id = a.client_id;
      if (!isUuid(id)) throw new Error("client_id must be an id from find_clients");
      const db = ctx.db;
      const since = new Date(Date.now() - 30 * 864e5).toISOString();
      const [biz, sub, flags, staff, pays, claims, tickets, notes, history, products, bills, bills30, last] =
        await Promise.all([
          db.from("businesses").select("*").eq("id", id).maybeSingle(),
          db.from("subscriptions").select("*, plans(name, user_limit)").eq("business_id", id)
            .order("created_at", { ascending: false }).limit(1).maybeSingle(),
          db.from("feature_flags").select("*").eq("business_id", id).maybeSingle(),
          db.from("profiles").select("id, full_name, email, role").eq("business_id", id).order("role"),
          db.from("subscription_payments").select("*").eq("business_id", id)
            .order("payment_date", { ascending: false }).limit(20),
          db.from("renewal_claims").select("*").eq("business_id", id).eq("status", "pending"),
          db.from("support_tickets").select("id, subject, status, created_at, last_reply_at, last_shop_message_at")
            .eq("business_id", id).order("created_at", { ascending: false }).limit(10),
          db.from("admin_notes").select("note, created_at").eq("business_id", id).is("ticket_id", null)
            .order("created_at", { ascending: false }).limit(20),
          db.from("audit_logs").select("action, details, created_at").eq("business_id", id)
            .or("action.like.subscription.%,action.like.business.%,action.like.feature.%,action.like.support.%")
            .order("created_at", { ascending: false }).limit(20),
          db.from("products").select("id", { count: "exact", head: true }).eq("business_id", id),
          db.from("invoices").select("id", { count: "exact", head: true }).eq("business_id", id),
          db.from("invoices").select("id", { count: "exact", head: true }).eq("business_id", id).gte("created_at", since),
          db.from("invoices").select("created_at").eq("business_id", id)
            .order("created_at", { ascending: false }).limit(1).maybeSingle(),
        ]);
      if (!biz.data) throw new Error("No client with that id");
      return {
        client: biz.data,
        subscription: sub.data,
        features: flags.data,
        staff: staff.data,
        payments: pays.data,
        pending_payment_claims: claims.data,
        support_tickets: tickets.data,
        admin_notes: notes.data,
        recent_admin_history: history.data,
        usage: {
          products: products.count,
          bills_total: bills.count,
          bills_last_30_days: bills30.count,
          last_bill_at: last.data?.created_at ?? null,
        },
      };
    },
  },
  {
    name: "list_payments",
    title: "Subscription payments received",
    description: "Subscription payments recorded in the last N days (default 30), newest first, with the shop name and total.",
    inputSchema: obj({
      days: { type: "integer", minimum: 1, maximum: 3660, default: 30 },
      client_id: { type: "string" },
    }),
    run: async (ctx, a) => {
      const from = ist(new Date(Date.now() - (num(a.days) || 30) * 864e5));
      let q = ctx.db.from("subscription_payments")
        .select("id, amount, payment_date, payment_mode, note, business_id, businesses(name)")
        .gte("payment_date", from).order("payment_date", { ascending: false }).limit(500);
      if (isUuid(a.client_id)) q = q.eq("business_id", a.client_id);
      const rows = must(await q) as Array<{ amount: number }>;
      return { from, count: rows.length, total: rows.reduce((s, r) => s + Number(r.amount), 0), payments: rows };
    },
  },
  {
    name: "list_payment_claims",
    title: "Renewal payments shops say they made",
    description:
      "Payments shops reported from the app (UPI etc.) that wait for you to verify. Verify one with renew_subscription (pass claim_id), or turn it down with reject_payment_claim.",
    inputSchema: obj({ status: { type: "string", enum: ["pending", "verified", "rejected"], default: "pending" } }),
    run: async (ctx, a) => ({
      claims: must(
        await ctx.db.from("renewal_claims").select("*, businesses(name, phone)")
          .eq("status", str(a.status) || "pending").order("created_at", { ascending: false }).limit(100),
      ),
    }),
  },
  {
    name: "list_support_tickets",
    title: "Support tickets",
    description: "Support requests from shops, newest first. Filter by status. Read one with get_support_ticket.",
    inputSchema: obj({
      status: { type: "string", enum: ["open", "in_progress", "resolved"] },
      limit: { type: "integer", minimum: 1, maximum: 200, default: 50 },
    }),
    run: async (ctx, a) => {
      let q = ctx.db.from("support_tickets")
        .select("id, subject, status, created_at, last_reply_at, last_shop_message_at, business_id, businesses(name, phone)")
        .order("created_at", { ascending: false }).limit(Math.min(num(a.limit) || 50, 200));
      if (a.status) q = q.eq("status", a.status);
      return { tickets: must(await q) };
    },
  },
  {
    name: "get_support_ticket",
    title: "One support ticket with its messages",
    description: "A support ticket, the shop, and the whole conversation in order.",
    inputSchema: obj({ ticket_id: { type: "string" } }, ["ticket_id"]),
    run: async (ctx, a) => {
      if (!isUuid(a.ticket_id)) throw new Error("ticket_id must be an id from list_support_tickets");
      const t = must(
        await ctx.db.from("support_tickets").select("*, businesses(name, phone, owner_name)")
          .eq("id", a.ticket_id).maybeSingle(),
      );
      if (!t) throw new Error("No ticket with that id");
      const msgs = must(
        await ctx.db.from("support_messages").select("from_softraxa, body, created_at")
          .eq("ticket_id", a.ticket_id).order("created_at"),
      );
      return { ticket: t, messages: msgs };
    },
  },
  {
    name: "list_leads",
    title: "Sales leads",
    description: "Shops you are trying to sign up (CRM leads) with status, follow-up date and notes. Optionally only follow-ups due by today.",
    inputSchema: obj({
      status: { type: "string" },
      follow_up_due: { type: "boolean", description: "Only leads whose follow-up date is today or earlier." },
      limit: { type: "integer", minimum: 1, maximum: 300, default: 100 },
    }),
    run: async (ctx, a) => {
      let q = ctx.db.from("leads").select("*, plans:interested_plan_id(name)")
        .order("created_at", { ascending: false }).limit(Math.min(num(a.limit) || 100, 300));
      if (str(a.status)) q = q.eq("status", str(a.status));
      if (a.follow_up_due === true) q = q.lte("follow_up_date", ist());
      return { leads: must(await q) };
    },
  },
  {
    name: "list_plans",
    title: "Plans and prices",
    description: "Dukania plans with monthly/yearly price, user and product limits, features, and whether each is offered.",
    inputSchema: obj({}),
    run: async (ctx) => ({ plans: must(await ctx.db.from("plans").select("*").order("monthly_price")) }),
  },
  {
    name: "system_health",
    title: "System health checks",
    description: "The admin panel's health page: setup checks (keys, migrations, settings), nightly checks, shops billing, items waiting for you.",
    inputSchema: obj({}),
    run: async (ctx) => must(await ctx.db.rpc("get_system_health")),
  },
  {
    name: "audit_log",
    title: "Admin and shop audit history",
    description: "Recent logged actions (renewals, suspensions, feature changes, settings, master products…), newest first; optionally for one client.",
    inputSchema: obj({
      client_id: { type: "string" },
      limit: { type: "integer", minimum: 1, maximum: 300, default: 50 },
    }),
    run: async (ctx, a) => {
      let q = ctx.db.from("audit_logs").select("action, entity, entity_id, details, created_at, businesses(name)")
        .order("created_at", { ascending: false }).limit(Math.min(num(a.limit) || 50, 300));
      if (isUuid(a.client_id)) q = q.eq("business_id", a.client_id);
      return { entries: must(await q) };
    },
  },
  {
    name: "search_master_products",
    title: "Master product list",
    description: "Search the shared product list offered to shops (no prices). Status: published (offered), pending (waiting for you), hidden.",
    inputSchema: obj({
      search: { type: "string" },
      status: { type: "string", enum: ["published", "pending", "hidden"] },
      limit: { type: "integer", minimum: 1, maximum: 200, default: 50 },
    }),
    run: async (ctx, a) =>
      must(
        await ctx.db.rpc("get_admin_master_products", {
          p_search: str(a.search), p_status: str(a.status), p_limit: Math.min(num(a.limit) || 50, 200),
        }),
      ),
  },
  {
    name: "reconciliation_status",
    title: "Nightly data checks",
    description: "The latest reconciliation run (stock, money and GST cross-checks across shops) and its issues not yet explained.",
    inputSchema: obj({}),
    run: async (ctx) => {
      const run = must(
        await ctx.db.from("reconciliation_runs").select("*").order("started_at", { ascending: false })
          .limit(1).maybeSingle(),
      ) as { id: string } | null;
      if (!run) return { run: null, issues: [] };
      const issues = must(
        await ctx.db.from("reconciliation_issues").select("*, businesses(name)").eq("run_id", run.id).limit(300),
      );
      return { run, issues };
    },
  },

  // ------------------------------------------------------------ actions
  {
    name: "renew_subscription",
    title: "Record a payment and extend a subscription",
    description:
      "Records a subscription payment and extends the shop's expiry by a month, a year, or to a chosen date (also verifies a shop's payment claim when claim_id is given). Amount 0 = free extension. Non-cash payments need the UPI/bank reference.",
    write: true,
    inputSchema: obj({
      client_id: { type: "string" },
      period: { type: "string", enum: ["month", "year", "custom"] },
      until: { type: "string", description: "YYYY-MM-DD, only for period custom." },
      amount: { type: "number", minimum: 0 },
      mode: { type: "string", enum: ["upi", "cash", "card", "other"], default: "upi" },
      reference: { type: "string", description: "UPI/bank reference number." },
      payment_date: { type: "string", description: "YYYY-MM-DD, default today." },
      plan_id: { type: "string", description: "Change plan at the same time (from list_plans)." },
      claim_id: { type: "string", description: "The shop's payment claim this verifies (list_payment_claims)." },
      note: { type: "string" },
      ...confirmProp,
    }, ["client_id", "period", "amount"]),
    preview: async (ctx, a) =>
      `Record ₹${num(a.amount)} (${str(a.mode) || "upi"}${str(a.reference) ? `, ref ${str(a.reference)}` : ""}) for ${await clientName(ctx, a.client_id)} and extend it by ${a.period === "custom" ? `to ${str(a.until)}` : `one ${a.period}`}${isUuid(a.plan_id) ? " on a new plan" : ""}${isUuid(a.claim_id) ? ", verifying the shop's payment claim" : ""}.`,
    run: async (ctx, a) =>
      must(
        await ctx.db.rpc("admin_renew_subscription", {
          p_business: a.client_id,
          p_plan: isUuid(a.plan_id) ? a.plan_id : null,
          p_period: a.period,
          p_until: a.period === "custom" ? str(a.until) || null : null,
          p_amount: num(a.amount),
          p_mode: str(a.mode) || "upi",
          p_reference: str(a.reference),
          p_payment_date: str(a.payment_date) || ist(),
          p_note: str(a.note),
          p_claim: isUuid(a.claim_id) ? a.claim_id : null,
        }),
      ),
  },
  {
    name: "reject_payment_claim",
    title: "Turn down a shop's payment claim",
    description: "Rejects a payment a shop reported (e.g. the money never arrived), with the reason the shop will see.",
    write: true,
    inputSchema: obj({ claim_id: { type: "string" }, reason: { type: "string" }, ...confirmProp }, ["claim_id", "reason"]),
    preview: async (_ctx, a) => `Reject payment claim ${str(a.claim_id)} with the reason: "${str(a.reason)}".`,
    run: async (ctx, a) => {
      must(await ctx.db.rpc("admin_reject_renewal_claim", { p_claim: a.claim_id, p_reason: str(a.reason) }));
      return { rejected: true };
    },
  },
  {
    name: "set_client_suspended",
    title: "Suspend or restore a shop",
    description: "Suspends a shop (its app stops working until restored) or restores it.",
    write: true,
    inputSchema: obj({ client_id: { type: "string" }, suspend: { type: "boolean" }, ...confirmProp }, ["client_id", "suspend"]),
    preview: async (ctx, a) => `${a.suspend ? "SUSPEND" : "Restore"} ${await clientName(ctx, a.client_id)}.`,
    run: async (ctx, a) =>
      must(await ctx.db.rpc("admin_set_business_status", { p_business: a.client_id, p_suspend: a.suspend === true })),
  },
  {
    name: "set_client_feature",
    title: "Turn a feature on or off for one shop",
    description:
      "Plan features per shop, e.g. gst_billing, barcode_scanning, excel_import, reports, pdf_invoice, thermal_print, a4_print, offline_billing, expense_module.",
    write: true,
    inputSchema: obj({
      client_id: { type: "string" }, feature: { type: "string" }, on: { type: "boolean" }, ...confirmProp,
    }, ["client_id", "feature", "on"]),
    preview: async (ctx, a) =>
      `Turn ${str(a.feature)} ${a.on ? "ON" : "OFF"} for ${await clientName(ctx, a.client_id)}.`,
    run: async (ctx, a) => {
      must(await ctx.db.rpc("admin_set_feature", { p_business: a.client_id, p_key: str(a.feature), p_on: a.on === true }));
      return { done: true };
    },
  },
  {
    name: "reply_support_ticket",
    title: "Reply to a support ticket",
    description: "Sends your reply to the shop (shown in their app, with a phone notification) and sets the ticket status.",
    write: true,
    inputSchema: obj({
      ticket_id: { type: "string" },
      message: { type: "string" },
      status: { type: "string", enum: ["open", "in_progress", "resolved"], default: "in_progress" },
      ...confirmProp,
    }, ["ticket_id", "message"]),
    preview: async (_ctx, a) =>
      `Send this reply on ticket ${str(a.ticket_id)} and mark it ${str(a.status) || "in_progress"}:\n"${str(a.message)}"`,
    run: async (ctx, a) => {
      must(await ctx.db.rpc("admin_reply_ticket", {
        p_ticket: a.ticket_id, p_body: str(a.message), p_status: str(a.status) || "in_progress",
      }));
      // Best effort, as the admin panel does: tell the shop's phones.
      try {
        await fetch(`${SUPABASE_URL}/functions/v1/support-push`, {
          method: "POST",
          headers: { Authorization: `Bearer ${ctx.token}`, apikey: ANON_KEY, "Content-Type": "application/json" },
          body: JSON.stringify({ ticket_id: a.ticket_id }),
        });
      } catch (_) { /* the reply is in the app either way */ }
      return { sent: true };
    },
  },
  {
    name: "set_ticket_status",
    title: "Change a ticket's status",
    description: "Open, in progress or resolved, without sending a reply.",
    write: true,
    inputSchema: obj({
      ticket_id: { type: "string" }, status: { type: "string", enum: ["open", "in_progress", "resolved"] }, ...confirmProp,
    }, ["ticket_id", "status"]),
    preview: async (_ctx, a) => `Mark ticket ${str(a.ticket_id)} as ${str(a.status)}.`,
    run: async (ctx, a) => {
      must(await ctx.db.rpc("admin_set_ticket_status", { p_ticket: a.ticket_id, p_status: str(a.status) }));
      return { done: true };
    },
  },
  {
    name: "add_client_note",
    title: "Add a private note to a client",
    description: "A note only admins see on the client's page (calls, promises, reminders).",
    write: true,
    inputSchema: obj({ client_id: { type: "string" }, note: { type: "string" }, ...confirmProp }, ["client_id", "note"]),
    preview: async (ctx, a) => `Add this note to ${await clientName(ctx, a.client_id)}: "${str(a.note)}"`,
    run: async (ctx, a) => {
      if (!str(a.note)) throw new Error("The note is empty");
      must(await ctx.db.from("admin_notes").insert({ business_id: a.client_id, note: str(a.note), created_by: ctx.userId }));
      return { added: true };
    },
  },
  {
    name: "set_master_product_status",
    title: "Offer, hold or hide a master product",
    description: "published = offered to shops, pending = waiting for approval, hidden = never offered.",
    write: true,
    inputSchema: obj({
      product_id: { type: "string" }, status: { type: "string", enum: ["published", "pending", "hidden"] }, ...confirmProp,
    }, ["product_id", "status"]),
    preview: async (_ctx, a) => `Set master product ${str(a.product_id)} to ${str(a.status)}.`,
    run: async (ctx, a) => {
      must(await ctx.db.rpc("admin_set_master_product_status", { p_id: a.product_id, p_status: str(a.status) }));
      return { done: true };
    },
  },
  {
    name: "run_reconciliation",
    title: "Run the data checks now",
    description: "Runs the stock/money/GST cross-checks now, for all shops or one.",
    write: true,
    inputSchema: obj({ client_id: { type: "string" }, ...confirmProp }),
    preview: async (ctx, a) =>
      `Run the data checks for ${isUuid(a.client_id) ? await clientName(ctx, a.client_id) : "all shops"} (takes a little while).`,
    run: async (ctx, a) =>
      must(await ctx.db.rpc("run_reconciliation", { p_business: isUuid(a.client_id) ? a.client_id : null })),
  },
];

// ------------------------------------------------------------- protocol

const INSTRUCTIONS =
  "Dukania admin panel (SOFTRAXA's shop-billing software for Indian retailers). Amounts are in Indian rupees, dates in IST. " +
  "Find a client_id with find_clients before using client tools. Every action tool first returns a preview: show it to the user and " +
  "call again with confirm: true only after they clearly agree. Never confirm on your own.";

function toolList() {
  return TOOLS.map((t) => ({
    name: t.name,
    title: t.title,
    description: t.write ? `${t.description} ACTION: needs the user's yes (two-step confirm).` : t.description,
    inputSchema: t.inputSchema,
    annotations: {
      title: t.title,
      readOnlyHint: !t.write,
      destructiveHint: !!t.write,
      idempotentHint: !t.write,
      openWorldHint: false,
    },
  }));
}

const text = (s: string, isError = false) => ({ content: [{ type: "text", text: s }], isError });

async function callTool(ctx: Ctx, name: string, args: Args) {
  const tool = TOOLS.find((t) => t.name === name);
  if (!tool) return text(`Unknown tool: ${name}`, true);
  try {
    if (tool.write && args.confirm !== true) {
      const what = tool.preview ? await tool.preview(ctx, args) : `Run ${name}.`;
      return text(
        `PREVIEW — nothing has changed yet.\n${what}\n\nAsk the user to confirm. Only if they say yes, call ${name} again with the same arguments and confirm: true.`,
      );
    }
    const result = await tool.run(ctx, args);
    const out = JSON.stringify(result, null, 1);
    return {
      content: [{ type: "text", text: tool.write ? `DONE.\n${out}` : out }],
      ...(result && typeof result === "object" && !Array.isArray(result) ? { structuredContent: result } : {}),
      isError: false,
    };
  } catch (e) {
    return text(`Error: ${e instanceof Error ? e.message : String(e)}`, true);
  }
}

async function handle(ctx: Ctx, msg: { id?: unknown; method?: string; params?: Record<string, unknown> }) {
  const reply = (result: unknown) => ({ jsonrpc: "2.0", id: msg.id, result });
  const fail = (code: number, message: string) => ({ jsonrpc: "2.0", id: msg.id ?? null, error: { code, message } });
  switch (msg.method) {
    case "initialize": {
      const asked = String(msg.params?.protocolVersion ?? "");
      return reply({
        protocolVersion: PROTOCOL_VERSIONS.includes(asked) ? asked : PROTOCOL_VERSIONS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "dukania-admin", title: "Dukania Admin", version: "1.0.0" },
        instructions: INSTRUCTIONS,
      });
    }
    case "ping":
      return reply({});
    case "tools/list":
      return reply({ tools: toolList() });
    case "tools/call":
      return reply(await callTool(ctx, String(msg.params?.name ?? ""), (msg.params?.arguments ?? {}) as Args));
    case "resources/list":
      return reply({ resources: [] });
    case "prompts/list":
      return reply({ prompts: [] });
    default:
      return fail(-32601, `Method not found: ${msg.method}`);
  }
}

// ---------------------------------------------------------------- server

function unauthorized(message: string) {
  return json({ error: "unauthorized", error_description: message }, 401, {
    "WWW-Authenticate": `Bearer resource_metadata="${METADATA_URL}"`,
  });
}

/** The caller's login, or a reason it can't be used. */
async function authenticate(req: Request): Promise<Ctx | string> {
  const header = req.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ")) return "Sign in with your Dukania admin account";
  const token = header.slice(7).trim();
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) return "Your sign-in has expired — connect again";
  const { data: profile } = await db.from("profiles").select("role").eq("id", data.user.id).maybeSingle();
  if (profile?.role !== "admin") return "This account is not a Dukania admin";
  return { db, userId: data.user.id, email: data.user.email ?? "", token };
}

Deno.serve(async (req) => {
  const path = new URL(req.url).pathname;
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // OAuth protected-resource metadata (RFC 9728): where to sign in.
  if (path.endsWith("/.well-known/oauth-protected-resource")) {
    return json({
      resource: FN_URL,
      authorization_servers: [`${SUPABASE_URL}/auth/v1`],
      bearer_methods_supported: ["header"],
      resource_name: "Dukania Admin",
    });
  }

  if (req.method === "GET") {
    // No server-sent event stream in this stateless server.
    return json({ error: "Use POST (MCP Streamable HTTP)" }, 405, { Allow: "POST" });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const ctx = await authenticate(req);
  if (typeof ctx === "string") {
    return ctx.includes("not a Dukania admin") ? json({ error: "forbidden", error_description: ctx }, 403) : unauthorized(ctx);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400);
  }
  const messages = Array.isArray(body) ? body : [body];
  const replies = [];
  for (const m of messages as Array<Record<string, unknown>>) {
    // Notifications (no id) get no reply.
    if (m && m.id === undefined) continue;
    replies.push(await handle(ctx, m as never));
  }
  if (replies.length === 0) return new Response(null, { status: 202, headers: cors });
  return json(Array.isArray(body) ? replies : replies[0]);
});
