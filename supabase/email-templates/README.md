# Softraxa / Dukania — branded auth email templates

Table-based, inline-styled HTML that renders in Gmail, Outlook, Apple Mail, etc.
Brand: **Dukania by Softraxa** · primary `#7c3aed`, accent `#0284c7`, ink `#070a14`.

## How to install (Supabase Dashboard)

1. Go to **Authentication → Emails** (a.k.a. Email Templates).
2. For each template below, open it, switch the body to **HTML / source**, and
   paste the matching file's contents. Set the **Subject** as suggested.

| Supabase template | File | Suggested subject |
|---|---|---|
| Confirm signup | `confirm-signup.html` | `Confirm your Dukania account` |
| Reset password | `reset-password.html` | `Reset your Dukania password` |
| Magic Link | `magic-link.html` | `Your Dukania sign-in link` |

3. **Save** each one. Send yourself a real test signup / reset to verify.

## Important notes

- **Logo:** templates load `https://softraxa.in/images/logo.png`. That URL must
  be publicly reachable (deploy the website). If the logo 404s, inboxes show a
  broken image — verify the URL in a browser first.
- **Token-hash flow, NOT PKCE.** The links use
  `{{ .SiteURL }}/auth/callback?token_hash={{ .TokenHash }}&type=...` and the
  callback page calls `verifyOtp`. This is required because signup happens in
  the Flutter APP but the link opens in the BROWSER — a PKCE `?code=` can't be
  exchanged there (no verifier in browser storage → "PKCE code verifier not
  found"). Do **not** revert to `{{ .ConfirmationURL }}`.
- **Site URL must be set** (Auth → URL Configuration) — `{{ .SiteURL }}` uses it.
- **Don't** add `<html>`, `<head>`, or `<style>` blocks — Supabase wraps the
  body, and many clients strip `<style>`. Everything here is inline on purpose.
- Some clients block images by default; the design still reads fine with images
  off (text logo alt + colored header bar).
