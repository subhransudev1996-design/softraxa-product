"use client";

import dynamic from "next/dynamic";

// Reads the browser's sign-in and session storage, so it only renders in the browser.
const AccountClient = dynamic(() => import("./account-client"), {
  ssr: false,
  loading: () => <div className="h-96 animate-pulse rounded-3xl bg-white/60" />,
});

export default function AccountLoader(props: { initialToken: string | null; whatsapp: string }) {
  return <AccountClient {...props} />;
}
