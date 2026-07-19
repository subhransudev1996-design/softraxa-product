"use client";

import { useEffect } from "react";

/**
 * Supabase's default confirmation email redirects to the Site URL root
 * (e.g. `/?code=...`) rather than a dedicated callback path. This guard sits
 * on the home page: if it sees an auth `code` (or an auth error) on `/`, it
 * forwards to `/auth/callback` which actually exchanges the code. Renders
 * nothing in the normal case.
 */
export default function AuthCodeRedirect() {
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("code") || params.get("error_description")) {
      window.location.replace(`/auth/callback${window.location.search}`);
    }
  }, []);

  return null;
}
