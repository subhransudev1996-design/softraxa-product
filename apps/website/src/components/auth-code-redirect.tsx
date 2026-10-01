"use client";

import { useEffect } from "react";

/**
 * Supabase sends a link to the Site URL root when the app didn't name a
 * page (e.g. `/?code=...` or `/#access_token=...&type=recovery`). This
 * guard sits on the home page: if it sees an auth link, it forwards it,
 * query and fragment, to `/auth/callback`, which finishes it (sets the new
 * password, confirms the email). Renders nothing in the normal case.
 */
export default function AuthCodeRedirect() {
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
    if (
      params.get("code") || params.get("token_hash") || params.get("error_description") ||
      hash.get("access_token") || hash.get("error_description")
    ) {
      window.location.replace(`/auth/callback${window.location.search}${window.location.hash}`);
    }
  }, []);

  return null;
}
