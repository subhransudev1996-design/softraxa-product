import type { Metadata } from "next";
import { Instrument_Sans, Plus_Jakarta_Sans, JetBrains_Mono, Caveat } from "next/font/google";
import Nav from "@/components/nav";
import Footer from "@/components/footer";
import "./globals.css";

const instrumentSans = Instrument_Sans({
  variable: "--font-instrument-sans",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
});

const jakarta = Plus_Jakarta_Sans({
  variable: "--font-jakarta",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

// Handwritten notes on the site ("No internet? No problem!").
const caveat = Caveat({
  variable: "--font-caveat",
  subsets: ["latin"],
  weight: ["600"],
});

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
});

// CMS content is re-read at least hourly; CMS saves also publish
// immediately through /api/revalidate.
export const revalidate = 3600;

// The live address; relative canonical and share-image URLs resolve against it.
const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL || "https://www.dukania.in";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Dukania — billing, stock & GST software for Indian shops",
  description:
    "Dukania runs billing, stock, GST and khata for Indian shops — on Android phones and Windows PCs, online or completely offline.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${jakarta.variable} ${instrumentSans.variable} ${jetbrainsMono.variable} ${caveat.variable} h-full antialiased`}
    >
      {/* suppressHydrationWarning: browser extensions (password managers etc.)
          inject attributes into <body> before React hydrates, causing a
          harmless dev-only hydration warning. Applies to this element's
          attributes only, not children. */}
      <body suppressHydrationWarning className="min-h-full flex flex-col bg-bg text-paper">
        <Nav />
        <main className="flex-1">{children}</main>
        <Footer />
      </body>
    </html>
  );
}
