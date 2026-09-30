// support-push — tells a shop's phones that SOFTRAXA answered its support
// request. The reply itself is in the app (Support); this push is best
// effort.
//
// The admin panel calls it right after admin_reply_ticket succeeds:
//   POST { ticket_id }  with the admin's own login (JWT).
// The database decides whether anything is sent:
// claim_ticket_notification() (migration 0054) only answers for a platform
// admin, for a reply made in the last 10 minutes, and once per reply.
//
// Setup (same Firebase secret as the other push functions):
//   supabase functions deploy support-push     (JWT verification ON)

import { createClient } from "npm:@supabase/supabase-js@2";
import { fcmAccessToken, sendPush, type ServiceAccount } from "../_shared/fcm.ts";

// The admin panel is a browser on another origin.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  let ticketId = "";
  try {
    ticketId = String((await req.json()).ticket_id ?? "");
  } catch {
    return json({ error: "Bad request" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(ticketId)) return json({ error: "Bad request" }, 400);

  const asCaller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: claim, error: claimError } = await asCaller.rpc(
    "claim_ticket_notification",
    { p_ticket: ticketId },
  );
  if (claimError) return json({ error: claimError.message }, 400);
  if (!claim) return json({ sent: 0, skipped: "nothing to announce" });

  const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}") as ServiceAccount;
  if (!sa.project_id) return json({ sent: 0, skipped: "push not configured" });

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: tokens } = await db
    .from("device_tokens")
    .select("token")
    .eq("business_id", claim.business_id);
  if (!tokens?.length) return json({ sent: 0, skipped: "the shop has no registered phone" });

  const accessToken = await fcmAccessToken(sa);
  let sent = 0;
  for (const { token } of tokens) {
    const result = await sendPush(
      sa,
      accessToken,
      token,
      "SOFTRAXA replied",
      `Your support request "${claim.subject}" has an answer. Open Support in Dukania.`,
    );
    if (result === "sent") sent++;
    if (result === "gone") await db.from("device_tokens").delete().eq("token", token);
  }
  return json({ sent });
});
