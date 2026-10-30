// Razorpay helpers shared by the razorpay and razorpay-webhook functions
// (migration 0105). Keys come from the function secrets:
//   RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET
import { createClient } from "npm:@supabase/supabase-js@2";

export const keyId = () => Deno.env.get("RAZORPAY_KEY_ID") ?? "";
const keySecret = () => Deno.env.get("RAZORPAY_KEY_SECRET") ?? "";

export const serviceDb = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

/** A call to Razorpay's API with the account's keys. */
export async function rzp(path: string, init: { method?: string; body?: unknown } = {}) {
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method: init.method ?? "GET",
    headers: {
      Authorization: "Basic " + btoa(`${keyId()}:${keySecret()}`),
      "Content-Type": "application/json",
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data?.error?.description ?? `Razorpay error ${res.status}`);
  return data;
}

async function hmacHex(secret: string, message: string) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Compares without leaking where the strings differ. */
function sameText(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** The checkout's signature: order_id|payment_id signed with the key secret. */
export async function checkoutSignatureOk(orderId: string, paymentId: string, signature: string) {
  if (!keySecret() || !signature) return false;
  return sameText(await hmacHex(keySecret(), `${orderId}|${paymentId}`), signature);
}

/** A webhook's signature: the raw body signed with the webhook secret. */
export async function webhookSignatureOk(rawBody: string, signature: string) {
  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";
  if (!secret || !signature) return false;
  return sameText(await hmacHex(secret, rawBody), signature);
}

/**
 * Makes sure a payment is captured (accounts without auto-capture leave it
 * "authorized") and turns the order on. Safe to call more than once.
 */
export async function settle(orderId: string, paymentId: string) {
  let payment = await rzp(`/payments/${paymentId}`);
  if (payment.order_id !== orderId) throw new Error("This payment is for a different order");
  if (payment.status === "authorized") {
    try {
      payment = await rzp(`/payments/${paymentId}/capture`, {
        method: "POST", body: { amount: payment.amount, currency: payment.currency ?? "INR" },
      });
    } catch {
      // The page and the webhook can capture at the same moment: look again.
      payment = await rzp(`/payments/${paymentId}`);
    }
  }
  if (payment.status !== "captured") {
    return { ok: false, pending: payment.status === "created" || payment.status === "authorized",
             error: payment.error_description ?? `Payment is ${payment.status}` };
  }
  const { data, error } = await serviceDb().rpc("online_order_paid", {
    p_rzp_order: orderId,
    p_payment: { id: payment.id, amount: payment.amount, method: payment.method, status: payment.status },
  });
  if (error) throw new Error(error.message);
  return data;
}
