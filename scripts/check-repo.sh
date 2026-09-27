#!/usr/bin/env bash
# Repository hygiene checks run in CI (release criteria, LAUNCH_SPECIFICATION).
#   1. Migration version prefixes are unique (needed for tracked migrations).
#   2. No secrets are committed (the ImageKit private key once was).
# Usage: bash scripts/check-repo.sh   (from the repository root)
set -euo pipefail

status=0

# --- 1. unique migration versions --------------------------------------
dupes=$(ls supabase/migrations/*.sql | xargs -n1 basename | cut -d_ -f1 | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "✖ Duplicate migration version prefixes: $dupes"
  status=1
else
  echo "✔ Migration versions are unique"
fi

# --- 2. secret scan over tracked files ----------------------------------
# Patterns: ImageKit private keys, JWTs (anon/service-role keys), Resend
# keys, Supabase secret keys, PEM private keys, Sentry auth tokens.
# (A Sentry DSN is public by design and is not flagged.)
pattern='private_[A-Za-z0-9+/=]{20,}|eyJhbGciOi[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|re_[A-Za-z0-9]{24,}|sb_secret_[A-Za-z0-9_-]{10,}|sntrys_[A-Za-z0-9_+/=]{20,}|sntryu_[a-f0-9]{20,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----(\\n|$)'
hits=$(git ls-files -z \
  | xargs -0 grep -nIE "$pattern" -- 2>/dev/null \
  | grep -v '^scripts/check-repo.sh:' || true)
if [ -n "$hits" ]; then
  echo "✖ Possible secrets in tracked files (move them to env vars / Supabase Vault):"
  echo "$hits" | cut -c1-200
  status=1
else
  echo "✔ No secrets found in tracked files"
fi

exit $status
