// razorpay-webhook — Razorpay tells us about payments here (migration
// 0105), so a plan turns on even if the customer closed the page right
// after paying. Only messages signed with the webhook secret count.
//
// Setup:
//   Razorpay Dashboard → Settings → Webhooks → Add:
//     URL     https://<project>.supabase.co/functions/v1/razorpay-webhook
//     Secret  the same text as RAZORPAY_WEBHOOK_SECRET
//     Events  payment.authorized, payment.captured, payment.failed, order.paid
//   supabase secrets set RAZORPAY_WEBHOOK_SECRET=…
//   supabase functions deploy razorpay-webhook --no-verify-jwt

import { serviceDb, settle, webhookSignatureOk } from "../_shared/razorpay.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const raw = await req.text();
  if (!(await webhookSignatureOk(raw, req.headers.get("x-razorpay-signature") ?? ""))) {
    return new Response("Bad signature", { status: 401 });
  }

  let event: { event?: string; payload?: Record<string, { entity?: Record<string, unknown> }> };
  try {
    event = JSON.parse(raw);
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  const payment = event.payload?.payment?.entity ?? {};
  const orderId = String(payment.order_id ?? event.payload?.order?.entity?.id ?? "");
  const paymentId = String(payment.id ?? "");
  if (!orderId || !paymentId) return new Response("ok");   // not one of our checkouts

  // Only orders made by the pay page.
  const db = serviceDb();
  const { data: order } = await db.from("online_orders").select("id").eq("rzp_order_id", orderId).maybeSingle();
  if (!order) return new Response("ok");

  try {
    if (event.event === "payment.failed") {
      await db.rpc("online_order_failed", {
        p_rzp_order: orderId, p_error: String(payment.error_description ?? "Payment failed"),
      });
    } else if (["payment.authorized", "payment.captured", "order.paid"].includes(event.event ?? "")) {
      await settle(orderId, paymentId);
    }
  } catch (e) {
    // A 5xx makes Razorpay try again later.
    console.error("razorpay-webhook", orderId, e);
    return new Response("Try again", { status: 500 });
  }
  return new Response("ok");
});
