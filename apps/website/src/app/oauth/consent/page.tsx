import type { Metadata } from "next";
import ConsentClient from "./consent-client";

export const metadata: Metadata = {
  title: "Connect an AI app — Dukania Admin",
  robots: { index: false, follow: false },
};

// OAuth consent for the Dukania admin MCP server (supabase/functions/
// admin-mcp). ChatGPT or Claude sends the admin here with
// ?authorization_id=… (Supabase Auth's OAuth 2.1 server, Authorization
// Path "/oauth/consent"); they sign in with their admin account and allow
// or deny the connection.
export default function OAuthConsentPage() {
  return <ConsentClient />;
}
