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
// Phase 1 (0086): reading. Phase 2 (0087): sales, payments, expenses,
// cancelling bills, products and customers. Phase 3/4 (0088): supplier bills
// read by the AI app (enter_purchase), sale returns, stock corrections,
// suppliers. 0089: discount cards, offers and coupons on sales, split
// payments, quotations / cash memos, editing a bill; creating offers and
// giving discount cards. Every change is two-step like
// admin-mcp's actions: the first call returns a preview and changes
// nothing; only a second call with confirm: true (after the user said yes)
// saves it. A sale's preview is a dry run of the app's own create_invoice
// (ai_preview_sale). Everything saved here is marked as made by the AI
// (header X-Dukania-Source: ai -> created_via / audit source).
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
  /** Changes data: needs confirm: true, else returns preview(). */
  write?: boolean;
  preview?: (ctx: Ctx, a: Args) => Promise<string>;
  run: (ctx: Ctx, a: Args) => Promise<unknown>;
};

/** A preview that can't be confirmed (already saved, needs approval...). */
class Final extends Error {}

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

const confirmProp = {
  confirm: {
    type: "boolean",
    description:
      "Leave out (or false) first: you get a preview and nothing is saved. Only after the user has said yes in the chat, call again with confirm: true.",
  },
};
const modeProp = { type: "string", enum: ["cash", "upi", "card", "other"], default: "cash" };
const rupees = (n: unknown) => `₹${Number(n).toLocaleString("en-IN", { maximumFractionDigits: 2 })}`;

/** The signed-in user's shop id (for direct inserts; RLS checks it too). */
async function businessId(ctx: Ctx): Promise<string> {
  const r = await ctx.db.from("profiles").select("business_id").eq("id", ctx.userId).maybeSingle();
  if (!r.data?.business_id) throw new Error("No shop for this login");
  return r.data.business_id as string;
}

/** One row of the shop's table by id, or an error naming where to find it. */
async function rowOf(ctx: Ctx, table: string, id: unknown, fields: string, hint: string) {
  if (!isUuid(id)) throw new Error(`Give the id from ${hint}`);
  const r = await ctx.db.from(table).select(fields).eq("id", id).maybeSingle();
  if (!r.data) throw new Error(`Not found in your shop — look it up with ${hint}`);
  return r.data as unknown as Record<string, unknown>;
}

/** The sale input for ai_preview_sale / ai_create_sale (migration 0087). */
function saleInput(a: Args) {
  return {
    customer_id: isUuid(a.customer_id) ? a.customer_id : null,
    customer_name: str(a.customer_name),
    lines: Array.isArray(a.lines) ? a.lines : [],
    bill_discount: a.bill_discount ?? null,
    paid: a.paid ?? "full",
    payment_mode: str(a.payment_mode) || "cash",
    notes: a.notes == null ? null : str(a.notes),
    due_date: isDate(a.due_date) ? a.due_date : null,
    sale_ref: isUuid(a.sale_ref) ? a.sale_ref : null,
    expected_total: a.expected_total ?? null,
    owner_ack: a.accept_warnings === true,
    // 0089
    bill_type: str(a.bill_type) || "bill",
    card: str(a.card) || null,
    offer_code: str(a.offer_code) || null,
    offer_id: str(a.offer_id) || null,
    offer_amount: a.offer_amount ?? null,
    payments: Array.isArray(a.payments) && a.payments.length ? a.payments : null,
  };
}

const saleLinesProp = {
  type: "array", minItems: 1, maxItems: 100,
  items: obj({
    product_id: { type: "string" },
    variant_id: { type: "string" },
    quantity: { type: "number", exclusiveMinimum: 0 },
    price: { type: "number", minimum: 0, description: "Per unit incl. GST; leave out for the product's price." },
    discount: { type: "number", minimum: 0, description: "Rupees off this line." },
  }, ["product_id", "quantity"]),
};

/** One offer as get_offers returns it (the whole row, for save_offer). */
async function offerRow(ctx: Ctx, id: unknown) {
  if (!isUuid(id)) throw new Error("Give the offer_id from list_offers");
  const all = must(await ctx.db.rpc("get_offers", { p_offer: null })) as { offers: Array<Record<string, unknown>> };
  const o = all.offers.find((x) => x.id === id);
  if (!o) throw new Error("No such offer in your shop");
  return o;
}

/** A discount card type by name. */
async function cardType(ctx: Ctx, name: string) {
  const all = must(await ctx.db.rpc("get_discount_cards", { p_search: "", p_limit: 1 })) as {
    types: Array<{ id: string; name: string; discount_pct: number; is_active: boolean }>;
  };
  const t = all.types.find((x) => x.name.toLowerCase() === name.toLowerCase());
  if (!t) throw new Error(`No card type "${name}" (the shop has: ${all.types.map((x) => x.name).join(", ") || "none — add one in the app"})`);
  if (!t.is_active) throw new Error(`${t.name} cards are switched off`);
  return t;
}

const WARNING_TEXT: Record<string, string> = {
  below_cost: "selling below cost",
  credit_limit: "over the customer's credit limit",
  overdue: "the customer has overdue bills",
  discount: "more discount than allowed",
};

/** Matches a unit or category by name (or short name) in the shop. */
async function lookupName(ctx: Ctx, table: "units" | "categories" | "expense_categories", name: string) {
  if (!name) return { id: null as string | null, note: "" };
  const cols = table === "units" ? "id, name, short_name" : "id, name";
  const rows = must(await ctx.db.from(table).select(cols)) as unknown as Array<{ id: string; name: string; short_name?: string }>;
  const n = name.toLowerCase();
  const hit = rows.find((x) => x.name.toLowerCase() === n || (x.short_name ?? "").toLowerCase() === n);
  if (hit) return { id: hit.id as string | null, note: "" };
  const what = table === "units" ? "unit" : "category";
  return {
    id: null as string | null,
    note: `There is no ${what} "${name}" in the shop (it has: ${rows.map((x) => x.name).join(", ") || "none"}), so it will be saved without one.`,
  };
}

const PRODUCT_FIELDS: Record<string, string> = {
  name: "name",
  selling_price: "selling price (incl. GST)",
  mrp: "MRP",
  purchase_price: "cost price",
  gst_rate: "GST %",
  hsn: "HSN code",
  barcode: "barcode",
  low_stock_qty: "low-stock level",
};
const productColumn = (k: string) => (k === "hsn" ? "hsn_code" : k);

// The app's key for a supplier's item name (bill_reader/bill_match.dart
// billItemKey), so the AI and the app's bill reader share what the shop
// taught (supplier_bill_items, 0078).
const FILLER = new Set(["of", "the", "and", "with", "new", "pkt", "packet", "pouch", "tin", "jar", "bottle", "btl", "box",
  "pack", "pc", "pcs", "nos", "no", "each", "rs", "mrp"]);
const fmtNum = (v: number) => v.toFixed(3).replace(/\.?0+$/, "");
function billItemKey(name: string): string {
  let s = name.toLowerCase().replaceAll("&", " and ");
  s = s.replace(/[^a-z0-9.]+/g, " ");
  s = s.replace(
    /(\d+(?:\.\d+)?)\s*(kgs?|kilos?|kilograms?|gms?|grams?|grms?|g|gr|mls?|millilitres?|milliliters?|ltrs?|litres?|liters?|lt|l)(?![a-z])/g,
    (_m, n: string, u: string) => {
      let v = parseFloat(n);
      let unit = u.startsWith("k") ? "kg" : u.startsWith("g") ? "g" : u.startsWith("m") ? "ml" : "l";
      if (unit === "g" && v >= 1000) { v /= 1000; unit = "kg"; } else if (unit === "ml" && v >= 1000) { v /= 1000; unit = "l"; }
      return ` ${fmtNum(v)}${unit} `;
    },
  );
  const words = s.split(" ")
    .filter((w) => w !== "" && w !== "." && !FILLER.has(w))
    .map((w) => w.replace(/^\.+|\.+$/g, ""))
    .filter((w) => w !== "");
  let t = words.join(" ");
  if (!t) t = name.trim().toLowerCase();
  return t.length > 200 ? t.substring(0, 200) : t;
}

/** The purchase input for ai_purchase (migration 0088). */
function purchaseInput(a: Args) {
  const lines = (Array.isArray(a.lines) ? a.lines : []) as Array<Record<string, unknown>>;
  return {
    supplier_id: isUuid(a.supplier_id) ? a.supplier_id : null,
    new_supplier: a.new_supplier && typeof a.new_supplier === "object" ? a.new_supplier : null,
    bill_no: str(a.bill_no),
    bill_date: isDate(a.bill_date) ? a.bill_date : null,
    lines: lines.map((l) => ({ ...l, bill_key: str(l.bill_name) ? billItemKey(str(l.bill_name)) : null })),
    bill_discount: a.bill_discount ?? null,
    extra_charges: a.extra_charges ?? null,
    bill_total: a.bill_total ?? null,
    paid: a.paid ?? "full",
    payment_mode: str(a.payment_mode) || "cash",
    notes: str(a.notes),
    ref: isUuid(a.ref) ? a.ref : null,
  };
}

/** The return input for ai_return (migration 0088). */
function returnInput(a: Args) {
  return {
    bill_id: a.bill_id,
    lines: Array.isArray(a.lines) ? a.lines : [],
    refund: a.refund ?? "full",
    refund_mode: str(a.refund_mode) || "cash",
    late_reason: str(a.late_reason),
    notes: str(a.notes),
    ref: isUuid(a.ref) ? a.ref : null,
  };
}

/** A stock correction: the product, its stock now and the signed change. */
async function stockChange(ctx: Ctx, a: Args) {
  const p = await rowOf(ctx, "products", a.product_id, "name, current_stock, has_variants, track_serial", "find_products");
  if (p.track_serial) throw new Error(`${p.name} is tracked by IMEI / serial — correct its stock in the Dukania app`);
  let name = String(p.name);
  let now = Number(p.current_stock);
  let variantId: string | null = null;
  if (p.has_variants) {
    const v = await rowOf(ctx, "product_variants", a.variant_id, "name, current_stock, product_id", "find_products (the variant's id)");
    if (v.product_id !== a.product_id) throw new Error("That variant belongs to another product");
    name = `${name} (${v.name})`;
    now = Number(v.current_stock);
    variantId = String(a.variant_id);
  }
  const delta = a.set_to != null ? num(a.set_to) - now : num(a.change);
  if (!Number.isFinite(delta) || delta === 0) throw new Final(`${name}: nothing to change (stock is ${now}).`);
  return { name, now, delta, variantId, reason: str(a.reason) === "damage" ? "damage" : "adjustment" };
}

// One variant as the app's variant sheet saves it (VariantDraft.toRow);
// a price left out is the product's own (null = inherit).
const variantProps = {
  name: { type: "string", description: "e.g. 'Size 8', 'Red / M', '500 g'." },
  attributes: {
    type: "object", additionalProperties: { type: "string" },
    description: "Optional, e.g. {\"size\": \"8\", \"colour\": \"Black\"}.",
  },
  selling_price: { type: "number", minimum: 0, description: "Only if different from the product's price (incl. GST)." },
  mrp: { type: "number", minimum: 0 },
  purchase_price: { type: "number", minimum: 0 },
  barcode: { type: "string" },
  low_stock_qty: { type: "number", minimum: 0 },
};
const newVariantProp = {
  type: "array", minItems: 1, maxItems: 100,
  items: obj({ ...variantProps, opening_stock: { type: "number", minimum: 0 } }, ["name"]),
};

function variantRow(v: Record<string, unknown>) {
  const row: Record<string, unknown> = {};
  if (v.name !== undefined) row.name = str(v.name);
  if (v.attributes && typeof v.attributes === "object") row.attributes = v.attributes;
  for (const k of ["selling_price", "mrp", "purchase_price", "low_stock_qty"]) {
    if (v[k] !== undefined && v[k] !== null) row[k] = num(v[k]);
  }
  if (v.barcode !== undefined) row.barcode = str(v.barcode);
  return row;
}

function variantText(v: Record<string, unknown>) {
  const bits = [
    v.selling_price != null ? rupees(v.selling_price) : "",
    v.mrp != null ? `MRP ${rupees(v.mrp)}` : "",
    v.purchase_price != null ? `cost ${rupees(v.purchase_price)}` : "",
    str(v.barcode) ? `barcode ${str(v.barcode)}` : "",
    num(v.opening_stock) > 0 ? `${v.opening_stock} in stock` : "",
  ].filter(Boolean);
  return `${str(v.name)}${bits.length ? ` (${bits.join(", ")})` : ""}`;
}

function checkVariantCost(ctx: Ctx, list: unknown) {
  if (!can(ctx, "can_view_profit") && Array.isArray(list) &&
      list.some((v) => v && typeof v === "object" && (v as Record<string, unknown>).purchase_price != null)) {
    throw new Error("You don't have permission to see or set cost prices — leave the cost price out");
  }
}

/** Adds variants to a product, with their opening stock. */
async function insertVariants(ctx: Ctx, productId: string, list: Array<Record<string, unknown>>) {
  const biz = await businessId(ctx);
  const rows = must(await ctx.db.from("product_variants").insert(
    list.map((v) => ({ ...variantRow(v), product_id: productId, business_id: biz })),
  ).select("id, name")) as Array<{ id: string; name: string }>;
  for (let i = 0; i < rows.length && i < list.length; i++) {
    if (num(list[i].opening_stock) > 0) {
      must(await ctx.db.rpc("add_opening_stock", {
        p_product_id: productId, p_variant_id: rows[i].id, p_quantity: num(list[i].opening_stock),
      }));
    }
  }
  return rows;
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
    description: "A sales bill by id or bill number: customer, every item (qty, price, discount, GST; each item's id is its bill_line_id for return_items) and the payments taken.",
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
          .select("id, product_id, variant_id, product_name, variant_name, hsn_code, serial_no, quantity, unit_name, unit_price, mrp, cost_price, discount_amount, gst_rate, tax_amount, line_total")
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
  // ------------------------------------------------------------ actions
  {
    name: "make_sale",
    title: "Make a sale (bill)",
    description:
      "Bills products to a customer or a walk-in. Get product_id (and variant_id for products with variants) from find_products and customer_id from find_customers. " +
      "price (per unit, incl. GST) is only for selling at a different price than the product's; discount is rupees off a line; bill_discount is rupees off the whole bill. " +
      "paid: 'full' (default), 'none' (on credit, needs a customer) or an amount; or payments for a split (₹200 cash + ₹300 UPI). " +
      "card: a discount card's number or last digits. offer_code: a coupon / voucher / scratch-card code; offer_id: a counter offer without a code " +
      "(list_offers); offer_amount: the prize a scratch card shows. bill_type: 'bill' (default), 'cash_memo' or 'estimate' (a quotation: no stock, no payment). " +
      "The first call returns the exact bill, totals and any warnings, and a sale_ref; " +
      "nothing is saved until you call again with the same arguments plus sale_ref, expected_total and confirm: true.",
    needs: "can_create_invoice",
    write: true,
    inputSchema: obj({
      customer_id: { type: "string" },
      customer_name: { type: "string", description: "Name for a walk-in customer without an account (optional)." },
      lines: saleLinesProp,
      bill_discount: { type: "number", minimum: 0 },
      card: { type: "string", description: "Discount card number or its last digits." },
      offer_code: { type: "string", description: "Coupon / voucher / scratch-card code." },
      offer_id: { type: "string", description: "A counter offer without a code (list_offers)." },
      offer_amount: { type: "number", description: "For a scratch card: the prize it shows." },
      bill_type: { type: "string", enum: ["bill", "cash_memo", "estimate"], default: "bill" },
      paid: { type: ["string", "number"], description: "'full' (default), 'none' or an amount." },
      payment_mode: modeProp,
      payments: {
        type: "array", minItems: 2, description: "A split payment instead of paid / payment_mode.",
        items: obj({ mode: { type: "string", enum: ["cash", "upi", "card", "other"] }, amount: { type: "number", exclusiveMinimum: 0 } }, ["mode", "amount"]),
      },
      due_date: { type: "string", description: "YYYY-MM-DD, for a sale on credit." },
      notes: { type: "string" },
      sale_ref: { type: "string", description: "From the preview; required with confirm." },
      expected_total: { type: "number", description: "The total shown in the preview; required with confirm." },
      accept_warnings: { type: "boolean", description: "Owner only: true if the user accepted the warnings in the preview." },
      ...confirmProp,
    }, ["lines"]),
    preview: async (ctx, a) => {
      const ref = isUuid(a.sale_ref) ? String(a.sale_ref) : crypto.randomUUID();
      const r = must(await ctx.db.rpc("ai_preview_sale", { p: { ...saleInput(a), sale_ref: ref, expected_total: null } })) as {
        ok?: boolean; already_saved?: boolean; bill_no?: string; error?: string; needs?: string;
        summary?: { total?: number }; warnings?: Array<Record<string, unknown>>;
      };
      if (r.already_saved) throw new Final(`This sale is already saved as bill ${r.bill_no}. Nothing more to do.`);
      if (r.error) throw new Error(r.error);
      const warnings = (r.warnings ?? []).map((w) => WARNING_TEXT[String(w.kind)] ?? String(w.kind));
      const details = JSON.stringify({ ...r.summary, warnings: r.warnings?.length ? r.warnings : undefined }, null, 1);
      if (r.needs === "owner_approval") {
        throw new Final(
          `This sale needs the shop owner's approval (${warnings.join("; ")}), so it can't be made from here. ` +
            `Change it, or make it in the Dukania app to send it to the owner for approval.\n${details}`,
        );
      }
      return `${details}\n\n` +
        (warnings.length
          ? `WARNING — ${warnings.join("; ")}. Show this to the user; only if they accept it, add accept_warnings: true.\n`
          : "") +
        `To save: call make_sale again with the same arguments plus sale_ref: "${ref}", expected_total: ${r.summary?.total}, confirm: true.`;
    },
    run: async (ctx, a) => {
      if (!isUuid(a.sale_ref)) throw new Error("Preview the sale first, then confirm it with the sale_ref from the preview");
      const r = must(await ctx.db.rpc("ai_create_sale", { p: saleInput(a) })) as Record<string, unknown>;
      return { ...r, note: r.already_saved ? "This sale was already saved." : "Saved. The bill is in the Dukania app." };
    },
  },
  {
    name: "take_customer_payment",
    title: "Record money received from a customer",
    description: "Records a payment from a customer against what they owe (oldest bills first, or one bill_id). Any extra becomes their advance.",
    needs: "can_record_payments",
    write: true,
    inputSchema: obj({
      customer_id: { type: "string" },
      amount: { type: "number", exclusiveMinimum: 0 },
      payment_mode: modeProp,
      date: { type: "string", description: "YYYY-MM-DD, default today." },
      bill_id: { type: "string", description: "Only to put it against one bill." },
      note: { type: "string" },
      ...confirmProp,
    }, ["customer_id", "amount"]),
    preview: async (ctx, a) => {
      const c = await rowOf(ctx, "customers", a.customer_id, "name, due_amount, advance_amount", "find_customers");
      const due = Number(c.due_amount);
      return `Record ${rupees(a.amount)} received from ${c.name} by ${str(a.payment_mode) || "cash"}` +
        `${isDate(a.date) ? ` on ${a.date}` : " today"}. They owe ${rupees(due)} now` +
        (due > 0 ? `, ${rupees(Math.max(due - Number(a.amount), 0))} after this` : "") +
        (Number(a.amount) > due ? `; ${rupees(Number(a.amount) - due)} becomes advance.` : ".");
    },
    run: async (ctx, a) => {
      const id = must(await ctx.db.rpc("record_customer_payment", {
        p_customer_id: a.customer_id, p_amount: num(a.amount), p_mode: str(a.payment_mode) || "cash",
        p_date: isDate(a.date) ? a.date : ist(), p_note: str(a.note), p_invoice_id: isUuid(a.bill_id) ? a.bill_id : null,
      }));
      const c = await rowOf(ctx, "customers", a.customer_id, "name, due_amount, advance_amount", "find_customers");
      return { payment_id: id, customer: c.name, now_owes: c.due_amount, advance: c.advance_amount };
    },
  },
  {
    name: "pay_supplier",
    title: "Record a payment to a supplier",
    description: "Records money paid to a supplier against what the shop owes them (oldest purchases first, or one purchase_id).",
    needs: "can_manage_purchases",
    write: true,
    inputSchema: obj({
      supplier_id: { type: "string" },
      amount: { type: "number", exclusiveMinimum: 0 },
      payment_mode: modeProp,
      date: { type: "string", description: "YYYY-MM-DD, default today." },
      purchase_id: { type: "string" },
      note: { type: "string" },
      ...confirmProp,
    }, ["supplier_id", "amount"]),
    preview: async (ctx, a) => {
      const s = await rowOf(ctx, "suppliers", a.supplier_id, "name, due_amount", "find_suppliers");
      return `Record ${rupees(a.amount)} paid to ${s.name} by ${str(a.payment_mode) || "cash"}` +
        `${isDate(a.date) ? ` on ${a.date}` : " today"}. The shop owes them ${rupees(s.due_amount)} now.`;
    },
    run: async (ctx, a) => {
      const id = must(await ctx.db.rpc("record_supplier_payment", {
        p_supplier_id: a.supplier_id, p_amount: num(a.amount), p_mode: str(a.payment_mode) || "cash",
        p_date: isDate(a.date) ? a.date : ist(), p_note: str(a.note),
        p_purchase_id: isUuid(a.purchase_id) ? a.purchase_id : null,
      }));
      const s = await rowOf(ctx, "suppliers", a.supplier_id, "name, due_amount", "find_suppliers");
      return { payment_id: id, supplier: s.name, shop_now_owes: s.due_amount };
    },
  },
  {
    name: "add_expense",
    title: "Add an expense",
    description: "Records a shop expense (rent, tea, electricity, transport…), optionally under one of the shop's expense categories.",
    needs: "can_manage_expenses",
    write: true,
    inputSchema: obj({
      amount: { type: "number", exclusiveMinimum: 0 },
      category: { type: "string", description: "Name of one of the shop's expense categories." },
      payment_mode: modeProp,
      date: { type: "string", description: "YYYY-MM-DD, default today." },
      note: { type: "string" },
      ...confirmProp,
    }, ["amount"]),
    preview: async (ctx, a) => {
      const cat = await lookupName(ctx, "expense_categories", str(a.category));
      return `Add an expense of ${rupees(a.amount)}${cat.id ? ` under ${str(a.category)}` : ""}, paid by ` +
        `${str(a.payment_mode) || "cash"}${isDate(a.date) ? ` on ${a.date}` : " today"}` +
        `${str(a.note) ? ` ("${str(a.note)}")` : ""}.` + (cat.note ? `\n${cat.note}` : "");
    },
    run: async (ctx, a) => {
      const cat = await lookupName(ctx, "expense_categories", str(a.category));
      const r = await ctx.db.from("expenses").insert({
        business_id: await businessId(ctx), amount: num(a.amount), category_id: cat.id,
        payment_mode: str(a.payment_mode) || "cash", expense_date: isDate(a.date) ? a.date : ist(), note: str(a.note),
      }).select("id, amount, expense_date").single();
      return { expense: must(r) };
    },
  },
  {
    name: "cancel_bill",
    title: "Cancel a sales bill",
    description: "Cancels a bill: its stock goes back and its payments and dues are reversed. The bill stays in the list, marked cancelled.",
    needs: "can_edit_invoices",
    write: true,
    inputSchema: obj({
      bill_id: { type: "string" },
      bill_no: { type: "string", description: "The exact bill number." },
      ...confirmProp,
    }),
    preview: async (ctx, a) => {
      const b = await findBill(ctx, a);
      if (b.is_cancelled) throw new Final(`Bill ${b.invoice_no} is already cancelled.`);
      return `CANCEL bill ${b.invoice_no} of ${String(b.invoice_date).slice(0, 10)} — ${b.customer_name || "walk-in"}, ` +
        `total ${rupees(b.total)}, paid ${rupees(b.paid_amount)}. Its items go back into stock and the payment/due is reversed. ` +
        `This can't be undone.`;
    },
    run: async (ctx, a) => {
      const b = await findBill(ctx, a);
      must(await ctx.db.rpc("cancel_invoice", { p_invoice_id: b.id }));
      return { cancelled: b.invoice_no };
    },
  },
  {
    name: "add_product",
    title: "Add a new product",
    description:
      "Adds a product to the shop: name and selling price (incl. GST) are needed; MRP, cost price, GST %, HSN, barcode, unit (e.g. Piece, Kg), " +
      "category, low-stock level and opening stock are optional. Check find_products first so you don't add one that already exists. " +
      "Ask the user whether it comes in variants (sizes, colours, weights, models); if it does, give each one in variants " +
      "(name, and price / MRP / barcode / opening stock where they differ) instead of opening_stock.",
    needs: "can_manage_products",
    write: true,
    inputSchema: obj({
      name: { type: "string" },
      selling_price: { type: "number", minimum: 0 },
      mrp: { type: "number", minimum: 0 },
      purchase_price: { type: "number", minimum: 0 },
      gst_rate: { type: "number", enum: [0, 0.25, 3, 5, 12, 18, 28, 40] },
      hsn: { type: "string" },
      barcode: { type: "string" },
      unit: { type: "string" },
      category: { type: "string" },
      low_stock_qty: { type: "number", minimum: 0 },
      opening_stock: { type: "number", minimum: 0 },
      variants: newVariantProp,
      ...confirmProp,
    }, ["name", "selling_price"]),
    preview: async (ctx, a) => {
      const name = str(a.name);
      if (!name) throw new Error("Give the product a name");
      if (a.purchase_price != null && !can(ctx, "can_view_profit")) {
        throw new Error("You don't have permission to see or set cost prices — leave the cost price out");
      }
      checkVariantCost(ctx, a.variants);
      const variants = (Array.isArray(a.variants) ? a.variants : []) as Array<Record<string, unknown>>;
      if (variants.length && num(a.opening_stock) > 0) {
        throw new Error("With variants, give each variant's opening_stock instead of the product's");
      }
      const names = variants.map((v) => str(v.name).toLowerCase());
      if (names.some((n) => !n)) throw new Error("Every variant needs a name");
      if (new Set(names).size !== names.length) throw new Error("Two variants have the same name");
      const same = await ctx.db.rpc("ai_find_products", { p_search: str(a.barcode) || name, p_filter: "all", p_limit: 5 });
      const found = ((same.data as { products?: Array<{ name: string }> } | null)?.products ?? []).map((p) => p.name);
      const unit = await lookupName(ctx, "units", str(a.unit));
      const cat = await lookupName(ctx, "categories", str(a.category));
      const parts = [
        `selling price ${rupees(a.selling_price)}`,
        a.mrp != null ? `MRP ${rupees(a.mrp)}` : "",
        a.purchase_price != null ? `cost ${rupees(a.purchase_price)}` : "",
        `GST ${num(a.gst_rate) || 0}%`,
        str(a.hsn) ? `HSN ${str(a.hsn)}` : "",
        str(a.barcode) ? `barcode ${str(a.barcode)}` : "",
        unit.id ? `unit ${str(a.unit)}` : "",
        cat.id ? `category ${str(a.category)}` : "",
        a.low_stock_qty != null ? `low-stock level ${a.low_stock_qty}` : "",
        num(a.opening_stock) > 0 ? `opening stock ${a.opening_stock}` : "",
      ].filter(Boolean);
      return `Add "${name}": ${parts.join(", ")}.` +
        (variants.length ? `\nVariants (${variants.length}): ${variants.map(variantText).join("; ")}.` : "") +
        (found.length ? `\nCAREFUL — similar products already exist: ${found.join(", ")}. Make sure this isn't one of them.` : "") +
        [unit.note, cat.note].filter(Boolean).map((n) => `\n${n}`).join("");
    },
    run: async (ctx, a) => {
      if (a.purchase_price != null && !can(ctx, "can_view_profit")) {
        throw new Error("You don't have permission to see or set cost prices — leave the cost price out");
      }
      checkVariantCost(ctx, a.variants);
      const variants = (Array.isArray(a.variants) ? a.variants : []) as Array<Record<string, unknown>>;
      const unit = await lookupName(ctx, "units", str(a.unit));
      const cat = await lookupName(ctx, "categories", str(a.category));
      const r = await ctx.db.from("products").insert({
        business_id: await businessId(ctx),
        name: str(a.name),
        selling_price: num(a.selling_price),
        mrp: a.mrp != null ? num(a.mrp) : 0,
        purchase_price: a.purchase_price != null ? num(a.purchase_price) : 0,
        gst_rate: num(a.gst_rate) || 0,
        hsn_code: str(a.hsn),
        barcode: str(a.barcode),
        unit_id: unit.id,
        category_id: cat.id,
        low_stock_qty: a.low_stock_qty != null ? num(a.low_stock_qty) : 0,
        has_variants: variants.length > 0,
      }).select("id, name").single();
      const product = must(r) as { id: string; name: string };
      if (variants.length) {
        try {
          const made = await insertVariants(ctx, product.id, variants);
          return { added: product, variants: made };
        } catch (e) {
          // Don't leave a product without the variants it was meant to have.
          await ctx.db.from("products").delete().eq("id", product.id);
          throw e;
        }
      }
      if (num(a.opening_stock) > 0) {
        must(await ctx.db.rpc("add_opening_stock", {
          p_product_id: product.id, p_variant_id: null, p_quantity: num(a.opening_stock),
        }));
      }
      return { added: product, opening_stock: num(a.opening_stock) || 0 };
    },
  },
  {
    name: "update_product",
    title: "Change a product's price or details",
    description: "Changes a product's name, selling price, MRP, cost price, GST %, HSN, barcode or low-stock level. Give only what changes.",
    needs: "can_manage_products",
    write: true,
    inputSchema: obj({
      product_id: { type: "string" },
      name: { type: "string" },
      selling_price: { type: "number", minimum: 0 },
      mrp: { type: "number", minimum: 0 },
      purchase_price: { type: "number", minimum: 0 },
      gst_rate: { type: "number", enum: [0, 0.25, 3, 5, 12, 18, 28, 40] },
      hsn: { type: "string" },
      barcode: { type: "string" },
      low_stock_qty: { type: "number", minimum: 0 },
      ...confirmProp,
    }, ["product_id"]),
    preview: async (ctx, a) => {
      const p = await rowOf(ctx, "products", a.product_id,
        "name, selling_price, mrp, purchase_price, gst_rate, hsn_code, barcode, low_stock_qty", "find_products");
      const changes = Object.keys(PRODUCT_FIELDS)
        .filter((k) => a[k] !== undefined && a[k] !== null && String(a[k]) !== String(p[productColumn(k)]));
      if (!changes.length) throw new Final(`Nothing to change: ${p.name} already has these values.`);
      if (changes.includes("purchase_price") && !can(ctx, "can_view_profit")) {
        throw new Error("You don't have permission to see or change cost prices");
      }
      return `Change ${p.name}: ` +
        changes.map((k) => `${PRODUCT_FIELDS[k]} ${k === "purchase_price" || p[productColumn(k)] !== "" ? p[productColumn(k)] : "—"} → ${a[k]}`).join(", ") + ".";
    },
    run: async (ctx, a) => {
      if (!isUuid(a.product_id)) throw new Error("Give the product_id from find_products");
      if (a.purchase_price != null && !can(ctx, "can_view_profit")) {
        throw new Error("You don't have permission to see or change cost prices");
      }
      const row: Record<string, unknown> = {};
      for (const k of Object.keys(PRODUCT_FIELDS)) {
        if (a[k] === undefined || a[k] === null) continue;
        row[productColumn(k)] = ["name", "hsn", "barcode"].includes(k) ? str(a[k]) : num(a[k]);
      }
      if (!Object.keys(row).length) throw new Error("Nothing to change");
      const r = await ctx.db.from("products").update(row).eq("id", a.product_id)
        .select("id, name, selling_price, mrp, gst_rate, hsn_code, barcode, low_stock_qty");
      const rows = must(r) as unknown[];
      if (!rows.length) throw new Error("The product wasn't changed — it isn't in your shop or you may not edit it");
      return { updated: rows[0] };
    },
  },
  {
    name: "edit_variants",
    title: "Add or change a product's variants",
    description:
      "For products in sizes, colours, weights or models. add: new variants (name; price / MRP / cost / barcode / opening stock where they differ). " +
      "change: existing variants by variant_id (find_products shows them) — name, price, MRP, cost, barcode, low-stock level. " +
      "switch_off / switch_on: variant_ids no longer (or again) sold; their history stays. To change a variant's stock use adjust_stock with its variant_id.",
    needs: "can_manage_products",
    write: true,
    inputSchema: obj({
      product_id: { type: "string" },
      add: newVariantProp,
      change: {
        type: "array", minItems: 1,
        items: obj({ variant_id: { type: "string" }, ...variantProps }, ["variant_id"]),
      },
      switch_off: { type: "array", items: { type: "string" } },
      switch_on: { type: "array", items: { type: "string" } },
      ...confirmProp,
    }, ["product_id"]),
    preview: async (ctx, a) => {
      const v = await variantEdit(ctx, a);
      const lines: string[] = [];
      if (v.add.length) lines.push(`Add ${v.add.length}: ${v.add.map(variantText).join("; ")}.`);
      for (const c of v.change) {
        const old = v.byId.get(String(c.variant_id))!;
        const diff = Object.entries(variantRow(c))
          .filter(([k, val]) => k !== "attributes" && String(val) !== String(old[k] ?? ""))
          .map(([k, val]) => `${k.replace("_", " ")} ${old[k] ?? "—"} → ${val}`);
        if (diff.length) lines.push(`Change ${old.name}: ${diff.join(", ")}.`);
      }
      if (v.off.length) lines.push(`Switch off: ${v.off.map((id) => v.byId.get(id)!.name).join(", ")}.`);
      if (v.on.length) lines.push(`Switch on again: ${v.on.map((id) => v.byId.get(id)!.name).join(", ")}.`);
      if (!lines.length) throw new Final("Nothing to change.");
      if (!v.product.has_variants && Number(v.product.current_stock) !== 0) {
        lines.push(
          `NOTE: ${v.product.name} has ${v.product.current_stock} in stock that isn't in any variant yet — ` +
            "after this, put it into the right variants with adjust_stock (and take it off the product).",
        );
      }
      return `${v.product.name}:\n${lines.join("\n")}`;
    },
    run: async (ctx, a) => {
      const v = await variantEdit(ctx, a);
      const made = v.add.length ? await insertVariants(ctx, String(a.product_id), v.add) : [];
      for (const c of v.change) {
        const row = variantRow(c);
        if (Object.keys(row).length) must(await ctx.db.from("product_variants").update(row).eq("id", c.variant_id));
      }
      if (v.off.length) must(await ctx.db.from("product_variants").update({ is_active: false }).in("id", v.off));
      if (v.on.length) must(await ctx.db.from("product_variants").update({ is_active: true }).in("id", v.on));
      if (!v.product.has_variants && made.length) {
        must(await ctx.db.from("products").update({ has_variants: true }).eq("id", a.product_id));
      }
      return { product: v.product.name, added: made, changed: v.change.length, switched_off: v.off.length, switched_on: v.on.length };
    },
  },
  {
    name: "add_customer",
    title: "Add a customer",
    description: "Adds a customer (name; phone, address, GSTIN and credit limit optional). Check find_customers first.",
    write: true,
    inputSchema: obj({
      name: { type: "string" },
      phone: { type: "string" },
      address: { type: "string" },
      gstin: { type: "string" },
      credit_limit: { type: "number", minimum: 0, description: "Most they may owe; leave out for the shop's default credit limit." },
      ...confirmProp,
    }, ["name"]),
    preview: async (ctx, a) => {
      if (!str(a.name)) throw new Error("Give the customer a name");
      const phone = str(a.phone).replace(/[^0-9+]/g, "");
      let same: string[] = [];
      if (phone) {
        const r = await ctx.db.from("customers").select("name, phone").eq("is_active", true)
          .ilike("phone", `%${phone.slice(-10)}%`).limit(3);
        same = ((r.data ?? []) as Array<{ name: string; phone: string }>).map((c) => `${c.name} (${c.phone})`);
      }
      return `Add customer "${str(a.name)}"` + (phone ? `, phone ${phone}` : "") + (str(a.address) ? `, ${str(a.address)}` : "") +
        (str(a.gstin) ? `, GSTIN ${str(a.gstin).toUpperCase()}` : "") +
        (a.credit_limit != null ? `, credit limit ${rupees(a.credit_limit)}` : "") + "." +
        (same.length ? `\nCAREFUL — this phone number already belongs to: ${same.join(", ")}.` : "");
    },
    run: async (ctx, a) => {
      const r = await ctx.db.from("customers").insert({
        business_id: await businessId(ctx),
        name: str(a.name),
        phone: str(a.phone).replace(/[^0-9+]/g, ""),
        address: str(a.address),
        gst_number: str(a.gstin).toUpperCase(),
        ...(a.credit_limit != null ? { credit_limit: num(a.credit_limit), credit_unlimited: false } : {}),
      }).select("id, name, phone").single();
      return { added: must(r) };
    },
  },
  {
    name: "enter_purchase",
    title: "Enter a supplier bill (purchase)",
    description:
      "Enters a supplier's bill as a purchase: stock goes up, the cost price is updated and what is owed to the supplier is recorded. " +
      "Read the bill (photo or PDF) yourself and send every line as printed: bill_name, quantity, rate (per bill unit, before GST unless rate_includes_gst) and GST %. " +
      "Lines are matched to the shop's products by product_id (if you looked it up with find_products), by what the shop taught for that item name, or by barcode; " +
      "for an item the shop doesn't stock yet, describe new_product (name and selling price incl. GST). pack_size = how many of the shop's units are in one bill unit (a box of 12). " +
      "Give supplier_id (find_suppliers) or new_supplier from the bill, and bill_total as printed so the preview can check it adds up. " +
      "The first call previews (nothing saved) and returns a ref; save by calling again with the same arguments plus ref and confirm: true.",
    needs: "can_manage_purchases",
    write: true,
    inputSchema: obj({
      supplier_id: { type: "string" },
      new_supplier: obj({ name: { type: "string" }, phone: { type: "string" }, gstin: { type: "string" } }, ["name"]),
      bill_no: { type: "string" },
      bill_date: { type: "string", description: "YYYY-MM-DD as printed; default today." },
      lines: {
        type: "array", minItems: 1, maxItems: 300,
        items: obj({
          bill_name: { type: "string", description: "The item's name exactly as printed on the bill." },
          product_id: { type: "string" },
          variant_id: { type: "string" },
          barcode: { type: "string" },
          new_product: obj({
            name: { type: "string", description: "The shop's name for it, e.g. 'Parle-G 100 g'." },
            selling_price: { type: "number", minimum: 0, description: "Per shop unit, incl. GST — ask the user if unsure." },
            mrp: { type: "number", minimum: 0 },
            gst_rate: { type: "number" },
            hsn: { type: "string" },
            unit: { type: "string" },
            barcode: { type: "string" },
          }, ["name", "selling_price"]),
          quantity: { type: "number", exclusiveMinimum: 0, description: "In bill units (boxes, if the bill counts boxes)." },
          pack_size: { type: "number", exclusiveMinimum: 0, description: "Shop units in one bill unit; leave out if the same." },
          rate: { type: "number", minimum: 0, description: "Price of one bill unit." },
          rate_includes_gst: { type: "boolean", description: "true if the printed rate already includes GST." },
          gst_rate: { type: "number", minimum: 0, maximum: 40 },
          discount: { type: "number", minimum: 0, description: "Rupees off this line." },
        }, ["quantity", "rate"]),
      },
      bill_discount: { type: "number", minimum: 0 },
      extra_charges: { type: "number", minimum: 0, description: "Freight, loading etc. on the bill." },
      bill_total: { type: "number", description: "The bill's grand total as printed." },
      paid: { type: ["string", "number"], description: "'full' (default), 'none' (on credit) or an amount paid now." },
      payment_mode: modeProp,
      notes: { type: "string" },
      ref: { type: "string", description: "From the preview; required with confirm." },
      ...confirmProp,
    }, ["lines"]),
    preview: async (ctx, a) => {
      const ref = isUuid(a.ref) ? String(a.ref) : crypto.randomUUID();
      const r = must(await ctx.db.rpc("ai_purchase", { p: { ...purchaseInput(a), ref }, p_commit: false })) as {
        already_saved?: boolean; purchase_no?: string; ok?: boolean;
        summary?: { total?: number; not_matched?: unknown[]; matches_printed_total?: boolean; printed_total?: number };
      };
      if (r.already_saved) throw new Final(`This bill is already entered as purchase ${r.purchase_no}. Nothing more to do.`);
      const s = r.summary ?? {};
      const notes: string[] = [];
      if (s.not_matched?.length) {
        notes.push(
          "NOT READY — these lines aren't matched to a product: " + JSON.stringify(s.not_matched) +
            ". For each, look it up with find_products (then give product_id) or describe new_product, then preview again.",
        );
      }
      if (s.matches_printed_total === false) {
        notes.push(
          `WARNING — this comes to ${rupees(s.total)} but the bill says ${rupees(s.printed_total)}. Check the lines, discount and charges with the user before saving.`,
        );
      }
      const body = `${JSON.stringify(s, null, 1)}\n\n${notes.join("\n")}${notes.length ? "\n" : ""}`;
      if (s.not_matched?.length) throw new Final(`PREVIEW — nothing saved.\n${body}`);
      return body + `To save: call enter_purchase again with the same arguments plus ref: "${ref}" and confirm: true.`;
    },
    run: async (ctx, a) => {
      if (!isUuid(a.ref)) throw new Error("Preview the purchase first, then confirm it with the ref from the preview");
      const r = must(await ctx.db.rpc("ai_purchase", { p: purchaseInput(a), p_commit: true })) as Record<string, unknown>;
      return { ...r, note: r.already_saved ? "This bill was already entered." : "Saved. The purchase is in the Dukania app." };
    },
  },
  {
    name: "return_items",
    title: "Take back items from a sales bill (sale return)",
    description:
      "Customer returns items from a bill. Get the bill with get_bill and use each item's id as bill_line_id. condition: sellable (back to stock, default), " +
      "damaged, inspection or scrap (kept out of stock). refund: 'full' (default; money back now), 'none' (comes off what they owe or becomes their advance) or an amount. " +
      "The value is worked out from the bill. The first call previews; save with the same arguments plus ref and confirm: true.",
    needs: "can_manage_returns",
    write: true,
    inputSchema: obj({
      bill_id: { type: "string" },
      lines: {
        type: "array", minItems: 1,
        items: obj({
          bill_line_id: { type: "string" },
          quantity: { type: "number", exclusiveMinimum: 0 },
          condition: { type: "string", enum: ["sellable", "damaged", "inspection", "scrap"], default: "sellable" },
        }, ["bill_line_id", "quantity"]),
      },
      refund: { type: ["string", "number"], description: "'full' (default), 'none' or an amount." },
      refund_mode: modeProp,
      late_reason: { type: "string", description: "Owner only: why a return after the shop's return window is accepted." },
      notes: { type: "string" },
      ref: { type: "string", description: "From the preview; required with confirm." },
      ...confirmProp,
    }, ["bill_id", "lines"]),
    preview: async (ctx, a) => {
      const ref = isUuid(a.ref) ? String(a.ref) : crypto.randomUUID();
      const r = must(await ctx.db.rpc("ai_return", { p: { ...returnInput(a), ref }, p_commit: false })) as {
        already_saved?: boolean; return_no?: string; summary?: unknown;
      };
      if (r.already_saved) throw new Final(`This return is already saved as ${r.return_no}. Nothing more to do.`);
      return `${JSON.stringify(r.summary, null, 1)}\n\nTo save: call return_items again with the same arguments plus ref: "${ref}" and confirm: true.`;
    },
    run: async (ctx, a) => {
      if (!isUuid(a.ref)) throw new Error("Preview the return first, then confirm it with the ref from the preview");
      const r = must(await ctx.db.rpc("ai_return", { p: returnInput(a), p_commit: true })) as Record<string, unknown>;
      return { ...r, note: r.already_saved ? "This return was already saved." : "Saved. The return is in the Dukania app." };
    },
  },
  {
    name: "adjust_stock",
    title: "Correct a product's stock",
    description:
      "Corrects stock after a count, or removes damaged/expired goods. Give change (+ add, − remove) or set_to (the counted quantity). " +
      "reason 'damage' for broken or expired goods, otherwise 'adjustment'. For goods bought from a supplier use enter_purchase instead.",
    needs: "can_manage_stock",
    write: true,
    inputSchema: obj({
      product_id: { type: "string" },
      variant_id: { type: "string" },
      change: { type: "number", description: "Signed: +5 adds, -2 removes." },
      set_to: { type: "number", minimum: 0, description: "The counted stock; the change is worked out." },
      reason: { type: "string", enum: ["adjustment", "damage"], default: "adjustment" },
      note: { type: "string" },
      ...confirmProp,
    }, ["product_id"]),
    preview: async (ctx, a) => {
      const s = await stockChange(ctx, a);
      return `${s.name}: stock ${s.now} → ${s.now + s.delta} (${s.delta > 0 ? "+" : ""}${s.delta}, ${s.reason})` +
        `${str(a.note) ? `, note "${str(a.note)}"` : ""}.`;
    },
    run: async (ctx, a) => {
      const s = await stockChange(ctx, a);
      must(await ctx.db.rpc("adjust_stock", {
        p_product_id: a.product_id, p_variant_id: s.variantId, p_quantity: s.delta, p_type: s.reason, p_note: str(a.note),
      }));
      return { product: s.name, stock_before: s.now, stock_now: s.now + s.delta };
    },
  },
  {
    name: "add_supplier",
    title: "Add a supplier",
    description: "Adds a supplier (name; phone, GSTIN and address optional). Check find_suppliers first. enter_purchase can also add one from a bill.",
    needs: "can_manage_purchases",
    write: true,
    inputSchema: obj({
      name: { type: "string" },
      phone: { type: "string" },
      gstin: { type: "string" },
      address: { type: "string" },
      ...confirmProp,
    }, ["name"]),
    preview: async (ctx, a) => {
      if (!str(a.name)) throw new Error("Give the supplier a name");
      const r = await ctx.db.from("suppliers").select("name, gst_number").eq("is_active", true)
        .or(`name.ilike.${str(a.name).replace(/[%,()]/g, " ")}${str(a.gstin) ? `,gst_number.eq.${str(a.gstin).toUpperCase().replace(/[^0-9A-Z]/g, "")}` : ""}`)
        .limit(3);
      const same = ((r.data ?? []) as Array<{ name: string }>).map((x) => x.name);
      return `Add supplier "${str(a.name)}"` + (str(a.phone) ? `, phone ${str(a.phone)}` : "") +
        (str(a.gstin) ? `, GSTIN ${str(a.gstin).toUpperCase()}` : "") + (str(a.address) ? `, ${str(a.address)}` : "") + "." +
        (same.length ? `\nCAREFUL — already in the shop: ${same.join(", ")}.` : "");
    },
    run: async (ctx, a) => {
      const r = await ctx.db.from("suppliers").insert({
        business_id: await businessId(ctx),
        name: str(a.name),
        phone: str(a.phone).replace(/[^0-9+]/g, ""),
        gst_number: str(a.gstin).toUpperCase(),
        address: str(a.address),
      }).select("id, name").single();
      return { added: must(r) };
    },
  },
  {
    name: "edit_bill",
    title: "Change a sales bill",
    description:
      "Changes an existing bill's items, quantities, prices or discounts. Send the bill's COMPLETE new list of lines (get_bill shows the current ones). " +
      "Its customer, bill type and the payments already taken stay; its discount card and offer stay unless you give card / offer_code / offer_id " +
      "('none' removes them). The first call previews the new bill; save with the same arguments plus expected_total and confirm: true.",
    needs: "can_edit_invoices",
    write: true,
    inputSchema: obj({
      bill_id: { type: "string" },
      lines: saleLinesProp,
      bill_discount: { type: "number", minimum: 0 },
      card: { type: "string", description: "Discount card number or its last digits; 'none' removes the bill's card." },
      offer_code: { type: "string", description: "Coupon / voucher code; 'none' removes the bill's offer." },
      offer_id: { type: "string", description: "A counter offer without a code (list_offers)." },
      offer_amount: { type: "number", description: "For a scratch card: the prize it shows." },
      notes: { type: "string" },
      expected_total: { type: "number", description: "The total shown in the preview; required with confirm." },
      accept_warnings: { type: "boolean", description: "Owner only: true if the user accepted the warnings in the preview." },
      ...confirmProp,
    }, ["bill_id", "lines"]),
    preview: async (ctx, a) => {
      if (!isUuid(a.bill_id)) throw new Error("Give the bill_id from list_bills or get_bill");
      const r = must(await ctx.db.rpc("ai_preview_sale", { p: { ...saleInput(a), edit_bill_id: a.bill_id, expected_total: null } })) as {
        error?: string; needs?: string; summary?: { total?: number }; warnings?: Array<Record<string, unknown>>;
      };
      if (r.error) throw new Error(r.error);
      const warnings = (r.warnings ?? []).map((w) => WARNING_TEXT[String(w.kind)] ?? String(w.kind));
      const details = JSON.stringify({ ...r.summary, warnings: r.warnings?.length ? r.warnings : undefined }, null, 1);
      if (r.needs === "owner_approval") {
        throw new Final(`This change needs the shop owner's approval (${warnings.join("; ")}), so it can't be made from here.\n${details}`);
      }
      return `${details}\n\n` +
        (warnings.length ? `WARNING — ${warnings.join("; ")}. Only if the user accepts it, add accept_warnings: true.\n` : "") +
        `To save: call edit_bill again with the same arguments plus expected_total: ${r.summary?.total} and confirm: true.`;
    },
    run: async (ctx, a) => {
      if (a.expected_total == null) throw new Error("Preview the change first, then confirm it with the expected_total from the preview");
      const r = must(await ctx.db.rpc("ai_create_sale", { p: { ...saleInput(a), edit_bill_id: a.bill_id } })) as Record<string, unknown>;
      return { ...r, note: "Saved. The changed bill is in the Dukania app." };
    },
  },
  {
    name: "list_offers",
    title: "Offers, coupons and scratch cards",
    description: "The shop's offers: % or ₹ off, minimum bill, code (shared coupon code, own voucher codes, or none for a counter offer), dates, on/off, and how often each was used.",
    inputSchema: obj({ offer_id: { type: "string", description: "Also list this offer's own codes and the bills it was used on." } }),
    run: async (ctx, a) => must(await ctx.db.rpc("get_offers", { p_offer: isUuid(a.offer_id) ? a.offer_id : null })),
  },
  {
    name: "find_discount_card",
    title: "Discount cards",
    description: "Finds a discount card by its number or last digits (is it valid, whose, what %), or lists the card types and cards (search by holder or number).",
    inputSchema: obj({
      card: { type: "string", description: "The number or its last digits, to check one card." },
      search: { type: "string", description: "To list cards: part of the number or the holder's name; empty for all." },
    }),
    run: async (ctx, a) =>
      str(a.card)
        ? must(await ctx.db.rpc("find_discount_card", { p_query: str(a.card) }))
        : must(await ctx.db.rpc("get_discount_cards", { p_search: str(a.search), p_limit: 100 })),
  },
  {
    name: "create_offer",
    title: "Create an offer or coupon",
    description:
      "Owner only. kind 'percent' (percent, optional max_discount) or 'amount' (amounts: one ₹ value, or several scratch-card prizes). " +
      "code: 'none' (applied at the counter), 'shared' (one code like DIWALI10 for everyone — give shared_code) or 'unique' (own voucher codes — give code_count). " +
      "Optional: min_bill, valid_from / valid_until, needs_customer, uses_per_customer (shared code).",
    needs: "owner",
    write: true,
    inputSchema: obj({
      name: { type: "string" },
      kind: { type: "string", enum: ["percent", "amount"] },
      percent: { type: "number", exclusiveMinimum: 0, maximum: 100 },
      max_discount: { type: "number", exclusiveMinimum: 0 },
      amounts: { type: "array", items: { type: "number", exclusiveMinimum: 0 }, minItems: 1 },
      min_bill: { type: "number", minimum: 0 },
      code: { type: "string", enum: ["none", "shared", "unique"], default: "none" },
      shared_code: { type: "string" },
      code_count: { type: "integer", minimum: 1, maximum: 2000 },
      code_prefix: { type: "string", maxLength: 8 },
      valid_from: { type: "string", description: "YYYY-MM-DD" },
      valid_until: { type: "string", description: "YYYY-MM-DD" },
      needs_customer: { type: "boolean" },
      uses_per_customer: { type: "integer", minimum: 1 },
      ...confirmProp,
    }, ["name", "kind"]),
    preview: async (_ctx, a) => {
      const what = a.kind === "percent"
        ? `${a.percent}% off${a.max_discount ? `, at most ${rupees(a.max_discount)}` : ""}`
        : `${(Array.isArray(a.amounts) ? a.amounts : []).map(rupees).join(" / ")} off`;
      const code = a.code === "shared" ? `code ${str(a.shared_code)} for everyone`
        : a.code === "unique" ? `${a.code_count ?? 0} own voucher codes${str(a.code_prefix) ? ` starting ${str(a.code_prefix)}` : ""}`
        : "no code (applied at the counter)";
      return `Create offer "${str(a.name)}": ${what}; ${code}` +
        (a.min_bill ? `; bills of ${rupees(a.min_bill)} or more` : "") +
        (isDate(a.valid_from) || isDate(a.valid_until) ? `; ${a.valid_from ?? "now"} to ${a.valid_until ?? "no end"}` : "") +
        (a.needs_customer ? "; needs the customer's name and phone" : "") +
        (a.uses_per_customer ? `; ${a.uses_per_customer} use(s) per customer` : "") + ".";
    },
    run: async (ctx, a) => {
      const id = must(await ctx.db.rpc("save_offer", {
        p_id: null,
        p: {
          name: str(a.name), kind: a.kind, percent: a.percent ?? 0, max_discount: a.max_discount ?? null,
          amounts: Array.isArray(a.amounts) ? a.amounts : [], min_bill: a.min_bill ?? 0,
          code_mode: str(a.code) || "none", shared_code: str(a.shared_code),
          uses_per_customer: a.uses_per_customer ?? null, needs_customer: a.needs_customer === true,
          valid_from: isDate(a.valid_from) ? a.valid_from : null, valid_until: isDate(a.valid_until) ? a.valid_until : null,
        },
      })) as string;
      let codes = 0;
      if (a.code === "unique" && num(a.code_count) > 0) {
        codes = must(await ctx.db.rpc("add_offer_codes", {
          p_offer: id, p_count: num(a.code_count), p_prefix: str(a.code_prefix), p_codes: [], p_amount: null,
        })) as number;
      }
      return { offer_id: id, codes_made: codes, note: codes ? "See the codes with list_offers (offer_id) or print them from the app." : "Saved." };
    },
  },
  {
    name: "set_offer_active",
    title: "Switch an offer on or off",
    description: "Owner only. Stops an offer (or starts it again); its past bills stay as they are.",
    needs: "owner",
    write: true,
    inputSchema: obj({ offer_id: { type: "string" }, active: { type: "boolean" }, ...confirmProp }, ["offer_id", "active"]),
    preview: async (ctx, a) => {
      const o = await offerRow(ctx, a.offer_id);
      return `Switch the offer "${o.name}" ${a.active ? "ON" : "OFF"} (it is ${o.is_active ? "on" : "off"} now).`;
    },
    run: async (ctx, a) => {
      const o = await offerRow(ctx, a.offer_id);
      must(await ctx.db.rpc("save_offer", { p_id: o.id, p: { ...o, is_active: a.active === true } }));
      return { offer: o.name, active: a.active === true };
    },
  },
  {
    name: "give_discount_card",
    title: "Give a customer a discount card",
    description: "Adds a discount card: its printed number, the card type (e.g. Gold — see find_discount_card for the types), and the customer (customer_id) or holder's name; optional valid_until.",
    needs: "can_edit_prices",
    write: true,
    inputSchema: obj({
      card_no: { type: "string" },
      card_type: { type: "string", description: "The type's name, e.g. Gold." },
      customer_id: { type: "string" },
      holder_name: { type: "string" },
      valid_until: { type: "string", description: "YYYY-MM-DD" },
      ...confirmProp,
    }, ["card_no", "card_type"]),
    preview: async (ctx, a) => {
      const t = await cardType(ctx, str(a.card_type));
      const who = isUuid(a.customer_id)
        ? String((await rowOf(ctx, "customers", a.customer_id, "name", "find_customers")).name)
        : str(a.holder_name) || "no name";
      return `Add ${t.name} card (${t.discount_pct}% off) number ${str(a.card_no)} for ${who}` +
        (isDate(a.valid_until) ? `, valid until ${a.valid_until}` : "") + ".";
    },
    run: async (ctx, a) => {
      const t = await cardType(ctx, str(a.card_type));
      const id = must(await ctx.db.rpc("save_discount_card", {
        p_id: null,
        p: {
          card_no: str(a.card_no), card_type_id: t.id, customer_id: isUuid(a.customer_id) ? a.customer_id : null,
          holder_name: str(a.holder_name), valid_until: isDate(a.valid_until) ? a.valid_until : null,
        },
      }));
      return { card_id: id, card_no: str(a.card_no), type: t.name };
    },
  },
];

/** Checks an edit_variants request against the product's variants. */
async function variantEdit(ctx: Ctx, a: Args) {
  const product = await rowOf(ctx, "products", a.product_id, "id, name, has_variants, current_stock, track_serial", "find_products");
  const all = must(await ctx.db.from("product_variants").select("id, name, selling_price, mrp, purchase_price, barcode, low_stock_qty, is_active")
    .eq("product_id", a.product_id)) as Array<Record<string, unknown>>;
  const byId = new Map(all.map((x) => [String(x.id), x]));
  const add = (Array.isArray(a.add) ? a.add : []) as Array<Record<string, unknown>>;
  const change = (Array.isArray(a.change) ? a.change : []) as Array<Record<string, unknown>>;
  const off = (Array.isArray(a.switch_off) ? a.switch_off : []).map(String);
  const on = (Array.isArray(a.switch_on) ? a.switch_on : []).map(String);
  checkVariantCost(ctx, [...add, ...change]);
  for (const id of [...change.map((c) => String(c.variant_id)), ...off, ...on]) {
    if (!byId.has(id)) throw new Error(`Variant ${id} isn't one of ${product.name}'s — find_products shows their ids`);
  }
  const taken = new Set(all.filter((x) => x.is_active).map((x) => String(x.name).toLowerCase()));
  for (const v of add) {
    const n = str(v.name).toLowerCase();
    if (!n) throw new Error("Every new variant needs a name");
    if (taken.has(n)) throw new Error(`${product.name} already has a variant "${str(v.name)}"`);
    taken.add(n);
  }
  return { product, byId, add, change, off, on };
}

/** A bill by bill_id or exact bill_no. */
async function findBill(ctx: Ctx, a: Args) {
  let q = ctx.db.from("invoices").select("id, invoice_no, invoice_date, customer_name, total, paid_amount, is_cancelled");
  if (isUuid(a.bill_id)) q = q.eq("id", a.bill_id);
  else if (str(a.bill_no)) q = q.eq("invoice_no", str(a.bill_no));
  else throw new Error("Give bill_id or bill_no");
  const b = must(await q.maybeSingle()) as Record<string, unknown> | null;
  if (!b) throw new Error("No such bill in your shop");
  return b;
}

// ------------------------------------------------------------- protocol

const INSTRUCTIONS =
  "Dukania is a billing and stock app for Indian shops; you are helping the signed-in shop owner or staff member. " +
  "Amounts are Indian rupees (₹), dates are India time (YYYY-MM-DD). Call shop_overview first to learn the shop, " +
  "what this person may do, and today's date. Find ids with find_products / find_customers / list_bills before " +
  "using the detail tools. You can also make sales, take customer payments, pay suppliers, add expenses, cancel bills, " +
  "add or change products, customers and suppliers, correct stock, take returns, edit bills, use discount cards and coupons, " +
  "create offers, manage product variants (sizes, colours) and enter supplier bills: when the user " +
  "shares a photo or PDF of a supplier's bill, read every line carefully and use enter_purchase. Every change is two-step: the first call only previews it; show the user " +
  "the preview in plain words and call again with confirm: true ONLY after they clearly say yes. Never confirm on your own, " +
  "never accept warnings for them, and never guess a product, customer or price — look it up or ask. " +
  "If a tool says something isn't allowed, tell the user exactly that — don't try to get around it.";

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
  if (!ctx.shop.allowed) return text(ctx.shop.reason ?? "You can't use the Dukania AI assistant.", true);
  if (tool.needs && !can(ctx, tool.needs)) {
    return text("You don't have permission for this in your shop. Ask the shop owner.", true);
  }
  try {
    if (tool.write && args.confirm !== true) {
      const what = tool.preview ? await tool.preview(ctx, args) : `Run ${name}.`;
      return text(
        `PREVIEW — nothing has been saved yet.\n${what}\n\nShow this to the user. Only if they say yes, call ${name} again with confirm: true` +
          (name === "make_sale"
            ? " (and the sale_ref and expected_total above)."
            : ["enter_purchase", "return_items"].includes(name)
            ? " (and the ref above)."
            : name === "edit_bill"
            ? " (and the expected_total above)."
            : " and the same arguments."),
      );
    }
    const result = await tool.run(ctx, args);
    return {
      content: [{ type: "text", text: (tool.write ? "DONE.\n" : "") + JSON.stringify(result, null, 1) }],
      ...(result && typeof result === "object" && !Array.isArray(result) ? { structuredContent: result } : {}),
      isError: false,
    };
  } catch (e) {
    if (e instanceof Final) return text(e.message);
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
        serverInfo: { name: "dukania", title: "Dukania", version: "4.0.0" },
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
    // X-Dukania-Source marks what this saves as made by the AI (0087).
    global: { headers: { Authorization: `Bearer ${token}`, "X-Dukania-Source": "ai" } },
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
