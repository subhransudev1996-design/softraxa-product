import type { Metadata } from "next";
import ConsentClient from "./consent-client";

export const metadata: Metadata = {
  title: "Connect an AI app — Dukania",
  robots: { index: false, follow: false },
};

// OAuth consent for the Dukania MCP servers (supabase/functions/admin-mcp
// for the SOFTRAXA admin, shop-mcp for shops). ChatGPT or Claude sends the
// user here with ?authorization_id=… (Supabase Auth's OAuth 2.1 server,
// Authorization Path "/oauth/consent"); they sign in and allow or deny the
// connection. Shop users need the AI assistant in their plan (ai_context).
export default function OAuthConsentPage() {
  return <ConsentClient />;
}
