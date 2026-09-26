/**
 * Email for the SOFTRAXA admin panel: the welcome / set-password invitation
 * sent to a client owner. No password is ever emailed or logged — the
 * owner sets their own through a one-time link (LAUNCH_SPECIFICATION,
 * onboarding; PROJECT_ANALYSIS finding 11).
 */

export interface WelcomeEmailParams {
  email: string;
  ownerName?: string;
  businessName: string;
  planName?: string;
  expiryDate?: string;
  /** One-time link to the website's set-password page. */
  setPasswordUrl: string;
}

export type EmailResult =
  | { sent: true; provider: "resend" }
  | { sent: false; provider: "resend" | "none"; error: string };

/** Escapes text for safe interpolation into HTML. */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export async function sendWelcomeEmail(params: WelcomeEmailParams): Promise<EmailResult> {
  const resendApiKey = process.env.RESEND_API_KEY;
  if (!resendApiKey) {
    // Report honestly instead of pretending it was sent.
    return { sent: false, provider: "none", error: "Email sending is not configured (RESEND_API_KEY is missing)." };
  }

  const ownerName = escapeHtml(params.ownerName?.trim() || "Shop Owner");
  const businessName = escapeHtml(params.businessName);
  const email = escapeHtml(params.email);
  const planName = escapeHtml(params.planName || "Trial");
  const expiry = params.expiryDate ? ` (valid until ${escapeHtml(params.expiryDate)})` : "";
  const link = escapeHtml(params.setPasswordUrl);
  const subject = `Welcome to Dukania — set up your login for ${params.businessName}`;

  const html = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>${escapeHtml(subject)}</title></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background:#f4f4f5;margin:0;padding:20px;color:#18181b;">
  <div style="max-width:580px;margin:0 auto;background:#ffffff;border-radius:12px;overflow:hidden;">
    <div style="background:#e0284a;padding:28px 24px;text-align:center;color:#ffffff;">
      <h1 style="margin:0;font-size:22px;">Dukania by SOFTRAXA</h1>
      <p style="margin:6px 0 0;font-size:14px;opacity:.9;">GST Billing &amp; Stock Management</p>
    </div>
    <div style="padding:28px 24px;">
      <p style="font-size:17px;font-weight:600;">Hello ${ownerName},</p>
      <p>Your Dukania account for <strong>${businessName}</strong> is ready.</p>
      <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:16px;margin:18px 0;">
        <div style="font-size:12px;color:#64748b;text-transform:uppercase;">Login email</div>
        <div style="font-weight:700;margin-bottom:10px;">${email}</div>
        <div style="font-size:12px;color:#64748b;text-transform:uppercase;">Plan</div>
        <div style="font-weight:700;">${planName}${expiry}</div>
      </div>
      <p>Set your password to start using the Dukania app:</p>
      <p style="text-align:center;margin:22px 0;">
        <a href="${link}" style="background:#e0284a;color:#ffffff;text-decoration:none;padding:13px 26px;border-radius:8px;font-weight:600;">Set my password</a>
      </p>
      <p style="font-size:13px;color:#64748b;">This link can be used once and expires soon. If it has expired, open the Dukania app and tap <em>Forgot password</em>.</p>
    </div>
    <div style="background:#f1f5f9;padding:14px 24px;text-align:center;font-size:12px;color:#64748b;">
      &copy; ${new Date().getFullYear()} SOFTRAXA · support@softraxa.com
    </div>
  </div>
</body>
</html>`;

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: process.env.EMAIL_FROM || "Dukania <noreply@softraxa.com>",
        to: [params.email],
        subject,
        html,
      }),
    });
    if (res.ok) return { sent: true, provider: "resend" };
    const errJson = (await res.json().catch(() => ({}))) as { message?: string };
    return { sent: false, provider: "resend", error: errJson.message || `Email provider returned ${res.status}` };
  } catch (err: unknown) {
    return { sent: false, provider: "resend", error: err instanceof Error ? err.message : String(err) };
  }
}
