// shop-mcp — Dukania for shop owners as an MCP server, so a shop can use
// its billing app from ChatGPT or Claude ("connectors"): ask about sales,
// stock, dues and bills in plain words.
//
// Login: Supabase Auth's OAuth 2.1 server, exactly like admin-mcp. A request
// without a token gets 401 with a link to this server's OAuth metadata; the
// AI app sends the user to www.softraxa.in/oauth/consent to sign in with
// their Dukania (shop) account and approve it. Every call runs with THAT
// login, so the database's own checks apply unchanged: own shop only, staff
// permissions, plan features, subscription.
//
// Who may use it is decided by public.ai_context() (migration 0086): the
// shop's plan must include `ai_assistant`, and staff need the owner's
// permission. Anyone else can connect but every tool answers with the
// reason (e.g. "not included in your plan").
//
// Phase 1: read only. Phase 2 adds sales and payments (two-step confirm,
// like admin-mcp's actions).
//
// Protocol: MCP over Streamable HTTP, stateless, JSON responses.
//
// Deploy (from the repo root):
//   npx supabase functions deploy shop-mcp --no-verify-jwt --project-ref <ref> --use-api
// Connector URL: https://<project-ref>.supabase.co/functions/v1/shop-mcp

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const FN_URL = `${SUPABASE_URL}/functions/v1/shop-mcp`;
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

type Shop = {
  allowed: boolean;
  reason?: string;
  shop?: Record<string, unknown>;
  user?: Record<string, unknown>;
  permissions?: Record<string, boolean>;
  subscription?: Record<string, unknown>;
  today?: string;
};
type Ctx = { db: SupabaseClient; userId: string; token: string; shop: Shop };
type Args = Record<string, unknown>;
type Tool = {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
  /** Staff permission needed (owners have all). */
  needs?: string;
  run: (ctx: Ctx, a: Args) => Promise<unknown>;
};

const str = (v: unknown) => (typeof v === "string" ? v.trim() : "");
const num = (v: unknown) => (typeof v === "number" ? v : Number(v));
const isUuid = (v: unknown) =>
  typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const ist = (d = new Date()) => new Date(d.getTime() + 5.5 * 3600e3).toISOString().slice(0, 10);
const isDate = (v: unknown) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
const addDays = (day: string, n: number) =>
  new Date(Date.parse(`${day}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10);
const can = (ctx: Ctx, perm: string) => ctx.shop.permissions?.[perm] === true;

function must<T>(r: { data: T; error: { message: string } | null }): T {
  if (r.error) throw new Error(r.error.message);
  return r.data;
}

function obj(props: Record<string, unknown>, required: string[] = []) {
  return { type: "object", properties: props, required, additionalProperties: false };
}

/** from/to (YYYY-MM-DD, IST) with defaults; to is inclusive. */
function period(a: Args, defaultDays = 0) {
  const to = isDate(a.to) ? String(a.to) : ist();
  const from = isDate(a.from) ? String(a.from) : addDays(to, -defaultDays);
  if (from > to) throw new Error("from must be on or before to");
  return { from, to };
}
/** Timestamps for an IST day range, for timestamptz columns. */
const istStart = (day: string) => `${day}T00:00:00+05:30`;
const istEnd = (day: string) => `${addDays(day, 1)}T00:00:00+05:30`;

const dateProps = {
  from: { type: "string", description: "YYYY-MM-DD (India time)." },
  to: { type: "string", description: "YYYY-MM-DD, inclusive. Default today." },
};
const limitProp = (d: number, max = 200) => ({ type: "integer", minimum: 1, maximum: max, default: d });
const lim = (v: unknown, d: number, max = 200) => Math.min(Math.max(num(v) || d, 1), max);

/** Drops cost/profit fields for users who may not see them. */
function hideCost<T>(ctx: Ctx, rows: T): T {
  if (can(ctx, "can_view_profit")) return rows;
  const strip = (o: unknown): unknown => {
    if (Array.isArray(o)) return o.map(strip);
    if (o && typeof o === "object") {
      return Object.fromEntries(
        Object.entries(o as Record<string, unknown>)
          .filter(([k]) => !["purchase_price", "cost_price", "profit"].includes(k))
          .map(([k, v]) => [k, strip(v)]),
      );
    }
    return o;
  };
  return strip(rows) as T;
}

const BILL_FIELDS =
  "id, invoice_no, invoice_type, invoice_date, customer_id, customer_name, customer_phone, subtotal, discount_amount, tax_amount, round_off, total, paid_amount, due_amount, due_date, payment_status, payment_mode, is_cancelled, notes";

const TOOLS: Tool[] = [
  {
    name: "shop_overview",
    title: "Shop today",
    description:
      "The shop, who is signed in and what they may do, the plan, and today's numbers: sales, bills, money to collect, low stock. Start here for 'how is my shop doing today?'.",
    inputSchema: obj({}),
    run: async (ctx) => {
      const { allowed: _a, ...about } = ctx.shop;
      return { ...about, today_numbers: must(await ctx.db.rpc("get_dashboard_stats")) };
    },
  },
  {
    name: "find_products",
    title: "Find products and stock",
    description:
      "Search products by name, SKU or barcode, with selling price, MRP, GST rate and stock (and variants). filter 'low' = at or below the low-stock level, 'out' = none left. Leave search empty to list.",
    inputSchema: obj({
      search: { type: "string" },
      filter: { type: "string", enum: ["all", "low", "out"], default: "all" },
      limit: limitProp(50),
    }),
    run: async (ctx, a) =>
      must(
        await ctx.db.rpc("ai_find_products", {
          p_search: str(a.search), p_filter: str(a.filter) || "all", p_limit: lim(a.limit, 50),
        }),
      ),
  },
  {
    name: "get_product",
    title: "One product in detail",
    description: "A product with its variants and its latest stock movements (sales, purchases, returns, adjustments).",
    inputSchema: obj({ product_id: { type: "string", description: "From find_products." } }, ["product_id"]),
    run: async (ctx, a) => {
      if (!isUuid(a.product_id)) throw new Error("product_id must be an id from find_products");
      const [p, variants, moves] = await Promise.all([
        ctx.db.from("products").select("*, categories(name), units(name)").eq("id", a.product_id).maybeSingle(),
        ctx.db.from("product_variants").select("id, name, sku, barcode, attributes, selling_price, mrp, purchase_price, current_stock, low_stock_qty")
          .eq("product_id", a.product_id).eq("is_active", true).order("name"),
        ctx.db.from("stock_movements").select("movement_type, quantity, note, reference_type, created_at, variant_id")
          .eq("product_id", a.product_id).order("created_at", { ascending: false }).limit(20),
      ]);
      if (!p.data) throw new Error("No product with that id in your shop");
      return hideCost(ctx, { product: p.data, variants: variants.data, recent_stock_movements: moves.data });
    },
  },
  {
    name: "find_customers",
    title: "Find customers and dues",
    description:
      "Search customers by name or phone with what they owe (due_amount) and any advance. owes_money: only customers with dues, biggest first — 'who owes me money?'.",
    inputSchema: obj({
      search: { type: "string" },
      owes_money: { type: "boolean" },
      limit: limitProp(50),
    }),
    run: async (ctx, a) => {
      let q = ctx.db.from("customers")
        .select("id, name, phone, address, gst_number, due_amount, advance_amount, credit_limit, is_wholesale", { count: "exact" })
        .eq("is_active", true).limit(lim(a.limit, 50));
      const s = str(a.search).replace(/[%,()]/g, " ");
      if (s) q = q.or(`name.ilike.%${s}%,phone.ilike.%${s}%`);
      if (a.owes_money === true) q = q.gt("due_amount", 0).order("due_amount", { ascending: false });
      else q = q.order("name");
      const r = await q;
      const rows = must(r) as Array<{ due_amount: number }>;
      return {
        total: r.count,
        shown: rows.length,
        ...(a.owes_money === true ? { total_due_shown: rows.reduce((t, c) => t + Number(c.due_amount), 0) } : {}),
        customers: rows,
      };
    },
  },
  {
    name: "get_customer",
    title: "One customer with their bills",
    description: "A customer's details, dues and advance, and their latest bills.",
    inputSchema: obj({ customer_id: { type: "string" }, bills: limitProp(15, 100) }, ["customer_id"]),
    run: async (ctx, a) => {
      if (!isUuid(a.customer_id)) throw new Error("customer_id must be an id from find_customers");
      const [c, bills] = await Promise.all([
        ctx.db.from("customers").select("*").eq("id", a.customer_id).maybeSingle(),
        ctx.db.from("invoices").select(BILL_FIELDS).eq("customer_id", a.customer_id)
          .order("invoice_date", { ascending: false }).limit(lim(a.bills, 15, 100)),
      ]);
      if (!c.data) throw new Error("No customer with that id in your shop");
      return { customer: c.data, latest_bills: bills.data };
    },
  },
  {
    name: "list_bills",
    title: "Sales bills",
    description:
      "Sales bills between two dates (default today), newest first, with totals. Filter by customer, unpaid only, or bill number. Cancelled bills are marked is_cancelled and left out of the totals.",
    inputSchema: obj({
      ...dateProps,
      customer_id: { type: "string" },
      unpaid_only: { type: "boolean" },
      bill_no: { type: "string", description: "Part of the bill number." },
      limit: limitProp(50),
    }),
    run: async (ctx, a) => {
      const { from, to } = period(a);
      let q = ctx.db.from("invoices").select(BILL_FIELDS, { count: "exact" })
        .gte("invoice_date", istStart(from)).lt("invoice_date", istEnd(to))
        .order("invoice_date", { ascending: false }).limit(lim(a.limit, 50));
      if (isUuid(a.customer_id)) q = q.eq("customer_id", a.customer_id);
      if (a.unpaid_only === true) q = q.gt("due_amount", 0).eq("is_cancelled", false);
      if (str(a.bill_no)) q = q.ilike("invoice_no", `%${str(a.bill_no).replace(/[%,()]/g, "")}%`);
      const r = await q;
      const rows = must(r) as Array<{ total: number; paid_amount: number; is_cancelled: boolean }>;
      const live = rows.filter((b) => !b.is_cancelled);
      return {
        from, to, total_bills: r.count, shown: rows.length,
        shown_totals: {
          sales: live.reduce((t, b) => t + Number(b.total), 0),
          received: live.reduce((t, b) => t + Number(b.paid_amount), 0),
        },
        bills: rows,
      };
    },
  },
  {
    name: "get_bill",
    title: "One bill with items and payments",
    description: "A sales bill by id or bill number: customer, every item (qty, price, discount, GST) and the payments taken.",
    inputSchema: obj({
      bill_id: { type: "string" },
      bill_no: { type: "string", description: "The exact bill number, e.g. INV/26-27/0061." },
    }),
    run: async (ctx, a) => {
      let q = ctx.db.from("invoices").select("*");
      if (isUuid(a.bill_id)) q = q.eq("id", a.bill_id);
      else if (str(a.bill_no)) q = q.eq("invoice_no", str(a.bill_no));
      else throw new Error("Give bill_id or bill_no");
      const bill = must(await q.maybeSingle()) as { id: string } | null;
      if (!bill) throw new Error("No such bill in your shop");
      const [items, pays] = await Promise.all([
        ctx.db.from("invoice_items")
          .select("product_id, variant_id, product_name, variant_name, hsn_code, serial_no, quantity, unit_name, unit_price, mrp, cost_price, discount_amount, gst_rate, tax_amount, line_total")
          .eq("invoice_id", bill.id),
        ctx.db.from("invoice_payments").select("amount, payment_mode, payment_date, note, is_advance, reversed")
          .eq("invoice_id", bill.id).order("payment_date"),
      ]);
      return hideCost(ctx, { bill, items: items.data, payments: pays.data });
    },
  },
  {
    name: "find_suppliers",
    title: "Find suppliers and what you owe",
    description: "Search suppliers by name or phone with what the shop owes them. owes_money: only suppliers you still have to pay.",
    needs: "can_manage_purchases",
    inputSchema: obj({ search: { type: "string" }, owes_money: { type: "boolean" }, limit: limitProp(50) }),
    run: async (ctx, a) => {
      let q = ctx.db.from("suppliers").select("id, name, phone, address, gst_number, due_amount, credit_limit", { count: "exact" })
        .eq("is_active", true).limit(lim(a.limit, 50));
      const s = str(a.search).replace(/[%,()]/g, " ");
      if (s) q = q.or(`name.ilike.%${s}%,phone.ilike.%${s}%`);
      if (a.owes_money === true) q = q.gt("due_amount", 0).order("due_amount", { ascending: false });
      else q = q.order("name");
      const r = await q;
      return { total: r.count, suppliers: must(r) };
    },
  },
  {
    name: "list_purchases",
    title: "Purchase bills",
    description: "Purchases (supplier bills entered) between two dates (default last 30 days), newest first. Filter by supplier or unpaid.",
    needs: "can_manage_purchases",
    inputSchema: obj({ ...dateProps, supplier_id: { type: "string" }, unpaid_only: { type: "boolean" }, limit: limitProp(50) }),
    run: async (ctx, a) => {
      const { from, to } = period(a, 30);
      let q = ctx.db.from("purchases")
        .select("id, purchase_no, bill_no, supplier_id, supplier_name, purchase_date, subtotal, discount_amount, tax_amount, extra_charges, total, paid_amount, due_amount, payment_status", { count: "exact" })
        .gte("purchase_date", from).lte("purchase_date", to)
        .order("purchase_date", { ascending: false }).limit(lim(a.limit, 50));
      if (isUuid(a.supplier_id)) q = q.eq("supplier_id", a.supplier_id);
      if (a.unpaid_only === true) q = q.gt("due_amount", 0);
      const r = await q;
      return { from, to, total: r.count, purchases: must(r) };
    },
  },
  {
    name: "get_purchase",
    title: "One purchase with items",
    description: "A purchase (supplier bill) with every item, quantity, price and GST.",
    needs: "can_manage_purchases",
    inputSchema: obj({ purchase_id: { type: "string" } }, ["purchase_id"]),
    run: async (ctx, a) => {
      if (!isUuid(a.purchase_id)) throw new Error("purchase_id must be an id from list_purchases");
      const [p, items] = await Promise.all([
        ctx.db.from("purchases").select("*").eq("id", a.purchase_id).maybeSingle(),
        ctx.db.from("purchase_items")
          .select("product_id, variant_id, product_name, quantity, unit_price, discount_amount, gst_rate, tax_amount, line_total, serial_nos")
          .eq("purchase_id", a.purchase_id),
      ]);
      if (!p.data) throw new Error("No purchase with that id in your shop");
      return { purchase: p.data, items: items.data };
    },
  },
  {
    name: "report",
    title: "Reports",
    description:
      "Shop reports between two dates (default this month so far): sales (totals by day and payment mode), top_products (best sellers), profit (owner or staff allowed to see profit), gst (GST collected, for filing), expenses, purchases (purchase register).",
    inputSchema: obj({
      kind: { type: "string", enum: ["sales", "top_products", "profit", "gst", "expenses", "purchases"] },
      ...dateProps,
      limit: { ...limitProp(20, 100), description: "top_products only." },
    }, ["kind"]),
    run: async (ctx, a) => {
      const to = isDate(a.to) ? String(a.to) : ist();
      const from = isDate(a.from) ? String(a.from) : `${to.slice(0, 8)}01`;
      if (from > to) throw new Error("from must be on or before to");
      const p = { p_from: from, p_to: to };
      switch (a.kind) {
        case "sales":
          return { from, to, report: must(await ctx.db.rpc("get_sales_report", p)) };
        case "top_products": {
          const rows = must(await ctx.db.rpc("get_product_sales_report", p)) as Array<{ revenue: number }>;
          const top = [...rows].sort((x, y) => Number(y.revenue) - Number(x.revenue)).slice(0, lim(a.limit, 20, 100));
          return hideCost(ctx, { from, to, products_sold: rows.length, top });
        }
        case "profit":
          return { from, to, report: must(await ctx.db.rpc("get_profit_report", p)) };
        case "gst":
          return { from, to, report: must(await ctx.db.rpc("get_gst_report", p)) };
        case "expenses":
          return { from, to, report: must(await ctx.db.rpc("get_expense_report", p)) };
        case "purchases":
          return { from, to, report: must(await ctx.db.rpc("get_purchase_register", p)) };
        default:
          throw new Error("kind must be sales, top_products, profit, gst, expenses or purchases");
      }
    },
  },
  {
    name: "cashbook",
    title: "Cash book for a day",
    description: "Cash in the drawer for one day (default today): opening, cash sales, payments in and out, expenses, closing.",
    needs: "can_manage_cash",
    inputSchema: obj({ date: { type: "string", description: "YYYY-MM-DD, default today." } }),
    run: async (ctx, a) =>
      must(await ctx.db.rpc("get_cashbook", { p_date: isDate(a.date) ? a.date : ist() })),
  },
];

// ------------------------------------------------------------- protocol

const INSTRUCTIONS =
  "Dukania is a billing and stock app for Indian shops; you are helping the signed-in shop owner or staff member. " +
  "Amounts are Indian rupees (₹), dates are India time (YYYY-MM-DD). Call shop_overview first to learn the shop, " +
  "what this person may do, and today's date. Find ids with find_products / find_customers / list_bills before " +
  "using the detail tools. This version can only read; to make bills or record payments, use the Dukania app. " +
  "If a tool says something isn't allowed, tell the user exactly that — don't try to get around it.";

function toolList() {
  return TOOLS.map((t) => ({
    name: t.name,
    title: t.title,
    description: t.description,
    inputSchema: t.inputSchema,
    annotations: { title: t.title, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  }));
}

const text = (s: string, isError = false) => ({ content: [{ type: "text", text: s }], isError });

async function callTool(ctx: Ctx, name: string, args: Args) {
  const tool = TOOLS.find((t) => t.name === name);
  if (!tool) return text(`Unknown tool: ${name}`, true);
  if (!ctx.shop.allowed) return text(ctx.shop.reason ?? "You can't use the Dukania AI assistant.", true);
  if (tool.needs && !can(ctx, tool.needs)) {
    return text("You don't have permission for this in your shop. Ask the shop owner.", true);
  }
  try {
    const result = await tool.run(ctx, args);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 1) }],
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
        serverInfo: { name: "dukania", title: "Dukania", version: "1.0.0" },
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

/** The caller's login, or why it can't be used (→ 401). */
async function authenticate(req: Request): Promise<Omit<Ctx, "shop"> | string> {
  const header = req.headers.get("Authorization") ?? "";
  if (!header.startsWith("Bearer ")) return "Sign in with your Dukania account";
  const token = header.slice(7).trim();
  const db = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) return "Your sign-in has expired — connect again";
  return { db, userId: data.user.id, token };
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
      resource_name: "Dukania",
    });
  }

  if (req.method === "GET") {
    return json({ error: "Use POST (MCP Streamable HTTP)" }, 405, { Allow: "POST" });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const login = await authenticate(req);
  if (typeof login === "string") return unauthorized(login);

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400);
  }
  const messages = (Array.isArray(body) ? body : [body]) as Array<Record<string, unknown>>;

  // Who may use the assistant, and with what rights — only needed for tool calls.
  let shop: Shop = { allowed: false };
  if (messages.some((m) => m?.method === "tools/call")) {
    const r = await login.db.rpc("ai_context");
    shop = r.error ? { allowed: false, reason: `Error: ${r.error.message}` } : (r.data as Shop);
  }
  const ctx: Ctx = { ...login, shop };

  const replies = [];
  for (const m of messages) {
    // Notifications (no id) get no reply.
    if (m && m.id === undefined) continue;
    replies.push(await handle(ctx, m as never));
  }
  if (replies.length === 0) return new Response(null, { status: 202, headers: cors });
  return json(Array.isArray(body) ? replies : replies[0]);
});
