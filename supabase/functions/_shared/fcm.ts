// Firebase Cloud Messaging (HTTP v1) helpers shared by the push functions:
// service-account JWT -> OAuth access token, and sending one message.

export type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

// ---------- FCM auth: service-account JWT -> OAuth access token ----------

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(pem: string): Promise<CryptoKey> {
  const raw = atob(
    pem
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s/g, ""),
  );
  const bytes = new Uint8Array([...raw].map((c) => c.charCodeAt(0)));
  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

export async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64url(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    ),
  );
  const key = await importKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    enc.encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth token exchange failed: ${await res.text()}`);
  return (await res.json()).access_token as string;
}

/** Sends one push. Returns "sent", "gone" (token no longer valid — prune
 * it) or "failed". */
export async function sendPush(
  sa: ServiceAccount,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  ttlSeconds = 86400,
): Promise<"sent" | "gone" | "failed"> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          // HIGH: deliver now, not batched under Doze.
          android: { priority: "HIGH", ttl: `${ttlSeconds}s` },
        },
      }),
    },
  );
  if (res.ok) return "sent";
  if (res.status === 404 || res.status === 410) return "gone";
  return "failed";
}
