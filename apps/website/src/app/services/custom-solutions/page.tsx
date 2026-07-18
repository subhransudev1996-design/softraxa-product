import type { Metadata } from "next";
import CustomSolutionsPageClient from "../../products/products-client";
import { getPageSeo, buildPageMetadata } from "@/lib/cms";

export async function generateMetadata(): Promise<Metadata> {
  const seo = await getPageSeo("/services/custom-solutions");
  return buildPageMetadata(seo);
}

export default async function CustomSolutionsPage() {
  const seo = await getPageSeo("/services/custom-solutions");

  return (
    <>
      {seo.structured_data && Object.keys(seo.structured_data).length > 0 && (
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(seo.structured_data) }}
        />
      )}
      <CustomSolutionsPageClient />
    </>
  );
}
