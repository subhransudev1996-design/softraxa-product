"use client";

import dynamic from "next/dynamic";

// The pay page reads the browser's session storage when it starts, so it
// only renders in the browser.
const PayClient = dynamic(() => import("./pay-client"), {
  ssr: false,
  loading: () => <div className="h-40 animate-pulse rounded-3xl bg-white/60" />,
});

export default function PayLoader(props: { initialToken: string | null; whatsapp: string }) {
  return <PayClient {...props} />;
}
