import type { Metadata } from "next";
import CallbackClient from "./callback-client";

export const metadata: Metadata = {
  title: "Verifying your email — Softraxa",
  robots: { index: false, follow: false },
};

// Auth callback landing page. Supabase confirmation & password-reset links
// redirect here with a `?code=...` (PKCE). The client component exchanges it
// for a session, completing verification, then tells the user to open the app.
export default function AuthCallbackPage() {
  return <CallbackClient />;
}
