import type { Metadata } from "next";
import CallbackClient from "./callback-client";

export const metadata: Metadata = {
  title: "Verifying your email — Softraxa",
  robots: { index: false, follow: false },
};

// Auth callback landing page. Supabase confirmation & password-reset links
// land here as ?token_hash=… (custom email template), #access_token=… (what
// the Dukania app asks for) or ?code=…. The client component verifies the
// link, asks for the new password when it is a reset, then tells the user
// to open the app.
export default function AuthCallbackPage() {
  return <CallbackClient />;
}
