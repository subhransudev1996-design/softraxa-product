// razorpay — the website's pay page (dukania.in/pay) talks to this
// (migration 0105). Every call carries the shop's pay link token
// (create_pay_link, from the app or after signing in on the website).
//
//   POST { action: "context", token }                     the shop and what it can buy
//   POST { action: "quote",   token, item }               the exact amount
//   POST { action: "order",   token, item }               a Razorpay order for the checkout
//   POST { action: "confirm", token, razorpay_order_id,
//          razorpay_payment_id, razorpay_signature }       after the checkout: turn the plan on
//   POST { action: "status",  token, razorpay_order_id }  is the order paid yet?
//
// Prices are worked out in the database (online_quote); the browser only
// says what it wants. The webhook (razorpay-webhook) turns plans on too, in
// case the customer closes the page right after paying.
//
// Setup:
//   supabase secrets set RAZORPAY_KEY_ID=… RAZORPAY_KEY_SECRET=…
//   supabase functions deploy razorpay --no-verify-jwt

import { checkoutSignatureOk, keyId, rzp, serviceDb, settle } from "../_shared/razorpay.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Bad request" }, 400);
  }
  const token = String(body.token ?? "");
  if (!/^[0-9a-f]{32}$/.test(token)) return json({ error: "This payment link isn't valid — open it again" }, 401);

  const db = serviceDb();
  const { data: on } = await db.rpc("online_payments_on");
  if (!on || !keyId()) return json({ error: "Online payment is not available yet — contact Dukania", off: true }, 503);

  const { data: ctx, error: ctxError } = await db.rpc("online_context", { p_token: token });
  if (ctxError) return json({ error: ctxError.message }, 500);
  if (!ctx) return json({ error: "This payment link has expired — open it again from the app or sign in", expired: true }, 401);
  const businessId = ctx.business_id as string;

  try {
    switch (body.action) {
      case "context":
        return json(ctx);

      case "quote": {
        const { data, error } = await db.rpc("online_quote", { p_business: businessId, p: body.item ?? {} });
        if (error) return json({ error: error.message }, 400);
        return json(data);
      }

      case "order": {
        const item = (body.item ?? {}) as Record<string, unknown>;
        const { data: quote, error } = await db.rpc("online_quote", { p_business: businessId, p: item });
        if (error) return json({ error: error.message }, 400);
        const paise = Math.round(Number(quote.amount) * 100);
        const what = quote.kind === "plan" ? `${quote.plan}` : quote.addon === "ai" ? "AI assistant" : "Extra staff logins";
        const order = await rzp("/orders", {
          method: "POST",
          body: {
            amount: paise, currency: "INR",
            receipt: `dk_${Date.now().toString(36)}`,
            notes: { business_id: businessId, shop: String(ctx.shop).slice(0, 200), item: what },
          },
        });
        const { data: link } = await db.from("pay_links").select("user_id").eq("token", token).maybeSingle();
        const { error: insError } = await db.from("online_orders").insert({
          business_id: businessId, rzp_order_id: order.id, kind: quote.kind, item, quote,
          amount: quote.amount, created_by: link?.user_id ?? null,
        });
        if (insError) return json({ error: insError.message }, 500);
        return json({
          key_id: keyId(), order_id: order.id, amount: paise, currency: "INR",
          description: what, shop: ctx.shop, email: ctx.email ?? "", phone: ctx.phone ?? "",
        });
      }

      case "confirm": {
        const orderId = String(body.razorpay_order_id ?? "");
        const paymentId = String(body.razorpay_payment_id ?? "");
        if (!(await checkoutSignatureOk(orderId, paymentId, String(body.razorpay_signature ?? "")))) {
          return json({ error: "We couldn't verify this payment. If money was taken, Dukania will turn your plan on." }, 400);
        }
        const { data: own } = await db.from("online_orders").select("id").eq("rzp_order_id", orderId)
          .eq("business_id", businessId).maybeSingle();
        if (!own) return json({ error: "This order isn't for this shop" }, 403);
        return json(await settle(orderId, paymentId));
      }

      case "status": {
        const { data: o } = await db.from("online_orders").select("status, result, error")
          .eq("rzp_order_id", String(body.razorpay_order_id ?? "")).eq("business_id", businessId).maybeSingle();
        if (!o) return json({ error: "Order not found" }, 404);
        return json(o.status === "paid" ? { ...o.result, ok: true } : { ok: false, status: o.status, error: o.error });
      }
    }
    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 502);
  }
});
