import type { Metadata } from "next";
import { Instrument_Sans, Plus_Jakarta_Sans, JetBrains_Mono } from "next/font/google";
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

const jetbrainsMono = JetBrains_Mono({
  variable: "--font-jetbrains-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Softraxa — software for businesses that don't stop moving",
  description:
    "Softraxa is a software agency building practical, offline-first business software. Dukania, our flagship product, runs billing, stock and reporting for real shops across India.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${jakarta.variable} ${instrumentSans.variable} ${jetbrainsMono.variable} h-full antialiased`}
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
