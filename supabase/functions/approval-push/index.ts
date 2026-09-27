// approval-push — tells the owner's phones that staff are waiting for an
// approval (LAUNCH_SPECIFICATION PD13). The in-app approval inbox stays
// authoritative; this push is best effort.
//
// The app calls it right after request_sale_approval succeeds:
//   POST { approval_id }  with the staff member's own login (JWT).
// The caller is checked by the database, not trusted:
// claim_approval_notification() (migration 0052) only answers for a
// pending request of the caller's own shop, made in the last 10 minutes,
// and only once — so the endpoint can't be used to spam anyone.
//
// Setup (same secret as push-alerts):
//   supabase functions deploy approval-push
//   (JWT verification stays ON for this function)
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are
// injected automatically.

import { createClient } from "npm:@supabase/supabase-js@2";
import { fcmAccessToken, sendPush, type ServiceAccount } from "../_shared/fcm.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

  let approvalId = "";
  try {
    approvalId = String((await req.json()).approval_id ?? "");
  } catch {
    return json({ error: "Bad request" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(approvalId)) return json({ error: "Bad request" }, 400);

  // As the caller: the database decides whether there is anything to send.
  const asCaller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } } },
  );
  const { data: claim, error: claimError } = await asCaller.rpc(
    "claim_approval_notification",
    { p_approval: approvalId },
  );
  if (claimError) return json({ error: claimError.message }, 400);
  if (!claim) return json({ sent: 0, skipped: "nothing to announce" });

  const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}") as ServiceAccount;
  if (!sa.project_id) return json({ sent: 0, skipped: "push not configured" });

  // Owners' devices of that shop (service role: device tokens aren't
  // readable by staff).
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: owners } = await db
    .from("profiles")
    .select("id")
    .eq("business_id", claim.business_id)
    .eq("role", "owner");
  const ownerIds = (owners ?? []).map((o: { id: string }) => o.id);
  if (ownerIds.length === 0) return json({ sent: 0 });
  const { data: tokens } = await db
    .from("device_tokens")
    .select("token")
    .eq("business_id", claim.business_id)
    .in("user_id", ownerIds);
  if (!tokens?.length) return json({ sent: 0, skipped: "owner has no registered phone" });

  const who = claim.requested_by || "Staff";
  const total = Number(claim.total ?? 0).toLocaleString("en-IN");
  const body = `${who} needs your approval for a ₹${total} sale` +
    (claim.customer ? ` to ${claim.customer}` : "") +
    ` (${claim.exceptions} issue${claim.exceptions === 1 ? "" : "s"}). Open Approvals in Dukania.`;

  const accessToken = await fcmAccessToken(sa);
  let sent = 0;
  for (const { token } of tokens) {
    // An approval request goes stale quickly: stop retrying after an hour.
    const result = await sendPush(sa, accessToken, token, "Approval needed", body, 3600);
    if (result === "sent") sent++;
    if (result === "gone") await db.from("device_tokens").delete().eq("token", token);
  }
  return json({ sent });
});
