"use client";

import { useState } from "react";

type Status = "idle" | "sending" | "sent" | "error";

const field =
  "mt-1.5 w-full rounded-lg border border-hairline bg-paper/4 px-3.5 py-2.5 text-paper placeholder:text-dim/70 focus:border-sky";

export default function ContactForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [error, setError] = useState("");

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("sending");
    setError("");
    const fd = new FormData(e.currentTarget);

    try {
      const res = await fetch("/api/contact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          shopName: fd.get("shopName"),
          contactName: fd.get("contactName"),
          phone: fd.get("phone"),
          email: fd.get("email"),
          city: fd.get("city"),
          notes: fd.get("notes"),
          website: fd.get("website"), // honeypot — real visitors leave it empty
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error || "Something went wrong. Please try again.");
      }
      setStatus("sent");
    } catch (err) {
      setStatus("error");
      setError(err instanceof Error ? err.message : "Something went wrong. Please try again.");
    }
  }

  if (status === "sent") {
    return (
      <div className="glass rounded-2xl p-8 text-center">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-teal/15 text-teal">✓</div>
        <p className="mt-4 font-display text-xl font-semibold">Request received.</p>
        <p className="mt-2 text-dim">
          We&apos;ll reach out within one business day to set up your demo.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="glass grid gap-5 rounded-2xl p-6 sm:grid-cols-2 sm:p-8">
      {/* Honeypot: hidden from people and screen readers; bots fill it in. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label htmlFor="website">Website</label>
        <input id="website" name="website" type="text" tabIndex={-1} autoComplete="off" />
      </div>
      <div className="sm:col-span-2">
        <label htmlFor="shopName" className="block text-sm font-medium text-paper">
          Shop or business name
        </label>
        <input id="shopName" name="shopName" required className={field} placeholder="e.g. Sharma General Store" />
      </div>

      <div>
        <label htmlFor="contactName" className="block text-sm font-medium text-paper">Your name</label>
        <input id="contactName" name="contactName" className={field} placeholder="Full name" />
      </div>

      <div>
        <label htmlFor="phone" className="block text-sm font-medium text-paper">Phone number</label>
        <input id="phone" name="phone" type="tel" required className={field} placeholder="10-digit mobile number" />
      </div>

      <div>
        <label htmlFor="email" className="block text-sm font-medium text-paper">Email (optional)</label>
        <input id="email" name="email" type="email" className={field} placeholder="you@business.com" />
      </div>

      <div>
        <label htmlFor="city" className="block text-sm font-medium text-paper">City</label>
        <input id="city" name="city" className={field} placeholder="Your city" />
      </div>

      <div className="sm:col-span-2">
        <label htmlFor="notes" className="block text-sm font-medium text-paper">
          What are you looking to solve? (optional)
        </label>
        <textarea
          id="notes"
          name="notes"
          rows={3}
          className={field}
          placeholder="e.g. tracking expiry on medicines, or billing without internet"
        />
      </div>

      {status === "error" && (
        <p role="alert" className="text-sm text-red-400 sm:col-span-2">
          {error}
        </p>
      )}

      <div className="sm:col-span-2">
        <button
          type="submit"
          disabled={status === "sending"}
          className="stamp-press min-h-11 w-full rounded-lg bg-paper px-6 py-3 text-sm font-semibold text-bg hover:bg-paper/90 disabled:opacity-60 sm:w-auto"
        >
          {status === "sending" ? "Sending…" : "Request a demo"}
        </button>
      </div>
    </form>
  );
}
