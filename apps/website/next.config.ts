import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The site is Dukania's own now: the product page is the home page, and
  // the old agency pages (Softraxa) are gone. Old links land on the home page.
  async redirects() {
    return [
      { source: "/dukania", destination: "/", permanent: true },
      { source: "/products", destination: "/", permanent: true },
      { source: "/services", destination: "/", permanent: true },
      { source: "/services/:path*", destination: "/", permanent: true },
    ];
  },
};

export default nextConfig;
