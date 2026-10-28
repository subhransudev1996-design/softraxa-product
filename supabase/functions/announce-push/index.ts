// announce-push — sends an announcement's notification to the phones of
// the shops it is for (migration 0101). The banner itself is in the app;
// this push is best effort.
//
// The admin panel calls it right after admin_create_announcement:
//   POST { announcement_id }  with the team member's own login (JWT).
// claim_announcement_push() decides: only someone with the marketing area,
// only for an announcement that asked for a notification, and only once.
//
// Setup (same Firebase secret as the other push functions):
//   supabase functions deploy announce-push     (JWT verification ON)

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

  let id = "";
  try {
    id = String((await req.json()).announcement_id ?? "");
  } catch {
    return json({ error: "Bad request" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: "Bad request" }, 400);

  const asCaller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: claim, error: claimError } = await asCaller.rpc("claim_announcement_push", { p_id: id });
  if (claimError) return json({ error: claimError.message }, 400);
  if (!claim) return json({ sent: 0, skipped: "already sent, or no notification asked for" });

  const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}") as ServiceAccount;
  if (!sa.project_id) return json({ sent: 0, skipped: "push not configured" });

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const ids: string[] = claim.business_ids ?? [];
  const tokens: string[] = [];
  // In batches, so a long list of shops stays within the URL limit.
  for (let i = 0; i < ids.length; i += 200) {
    const { data } = await db.from("device_tokens").select("token").in("business_id", ids.slice(i, i + 200));
    for (const row of data ?? []) tokens.push(row.token);
  }
  if (!tokens.length) return json({ sent: 0, skipped: "none of these shops has a registered phone" });

  const accessToken = await fcmAccessToken(sa);
  const body = String(claim.body || "Open Dukania to read it.").slice(0, 240);
  let sent = 0;
  for (const token of tokens) {
    const result = await sendPush(sa, accessToken, token, String(claim.title), body);
    if (result === "sent") sent++;
    if (result === "gone") await db.from("device_tokens").delete().eq("token", token);
  }
  await db.from("announcements").update({ push_count: sent }).eq("id", id);
  return json({ sent });
});
