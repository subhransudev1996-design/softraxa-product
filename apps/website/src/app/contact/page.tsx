import type { Metadata } from "next";
import ContactPageClient from "./contact-client";
import { getPageContentMap, getPageSeo, buildPageMetadata } from "@/lib/cms";
import { getSiteInfo } from "@/lib/site-info";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/contact");
  return buildPageMetadata(seo);
}

export default async function ContactPage() {
  const content = await getPageContentMap("contact");
  const seo = await getPageSeo("/contact");
  const info = await getSiteInfo();

  return (
    <>
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }}
        />
      )}
      <ContactPageClient content={content} info={info} />
    </>
  );
}
