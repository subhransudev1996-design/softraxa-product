import type { SupabaseClient } from "@supabase/supabase-js";

/* Two-step login for team members signing in on the website (migration
   0111): the database doesn't treat them as admins until the code is in. */

export async function needsTwoStep(supabase: SupabaseClient): Promise<boolean> {
  const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  return data?.nextLevel === "aal2" && data.currentLevel !== "aal2";
}

/** Checks the 6-digit code; returns a message when it fails. */
export async function verifyTwoStep(supabase: SupabaseClient, code: string): Promise<string | null> {
  const { data: factors } = await supabase.auth.mfa.listFactors();
  const factor = factors?.totp?.find((f) => f.status === "verified");
  if (!factor) return "Two-step login isn't set up on this account.";
  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: code.trim() });
  return error ? "That code didn't work. Check your authenticator app and try again." : null;
}
