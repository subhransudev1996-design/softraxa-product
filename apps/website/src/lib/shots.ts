/**
 * Manifest of the real Dukania screenshots in /public/images/dukania.
 * Dimensions are the assets' true pixel sizes — passed to next/image so
 * space is reserved and the page never shifts while they load.
 */
export type Shot = {
  src: string;
  width: number;
  height: number;
  alt: string;
};

export const desktopShots = {
  newBill: {
    src: "/images/dukania/desktop/new-bill.png",
    width: 1920,
    height: 1020,
    alt: "Dukania desktop billing screen: items as a table with quantity, rate, GST and amount, and the bill total with a Checkout button",
  },
  dashboardDark: {
    src: "/images/dukania/desktop/dashboard-dark.png",
    width: 1920,
    height: 1020,
    alt: "Dukania desktop dashboard in dark mode, showing today's sale, stock value, low stock count and recent invoices",
  },
  dashboard: {
    src: "/images/dukania/desktop/dashboard.png",
    width: 1920,
    height: 1019,
    alt: "Dukania desktop dashboard showing sales, profit, stock value and a list of recent invoices",
  },
  products: {
    src: "/images/dukania/desktop/products.png",
    width: 1920,
    height: 1020,
    alt: "Dukania product list with category, brand, price and colour-coded stock status",
  },
  reports: {
    src: "/images/dukania/desktop/reports.png",
    width: 1920,
    height: 1019,
    alt: "Dukania reports menu listing sales, profit, stock, low stock, customer due and GST reports",
  },
  salesReport: {
    src: "/images/dukania/desktop/sales-report.png",
    width: 1920,
    height: 1019,
    alt: "Dukania sales report with totals, GST collected and a daily sales bar chart",
  },
  invoices: {
    src: "/images/dukania/desktop/invoices.png",
    width: 1920,
    height: 1020,
    alt: "Dukania invoice list filtered by paid, partial, credit, estimates and cash memos",
  },
  stock: {
    src: "/images/dukania/desktop/stock.png",
    width: 1920,
    height: 1018,
    alt: "Dukania stock screen showing per-product stock levels with low and out-of-stock badges",
  },
  serviceCatalog: {
    src: "/images/dukania/desktop/service-catalog.png",
    width: 1920,
    height: 1020,
    alt: "Dukania service catalog with an add-service form including price, GST and SAC code",
  },
  jobCard: {
    src: "/images/dukania/desktop/job-card.png",
    width: 1920,
    height: 1017,
    alt: "Dukania new job card form capturing customer, device, issue and advance payment",
  },
  expenses: {
    src: "/images/dukania/desktop/expenses.png",
    width: 1920,
    height: 1019,
    alt: "Dukania expenses screen with an add-expense form for amount, category and payment mode",
  },
} satisfies Record<string, Shot>;

export const mobileShots = {
  dashboard: {
    src: "/images/dukania/mobile/dashboard.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile dashboard showing today's sale, quick actions and recent invoices",
  },
  newBill: {
    src: "/images/dukania/mobile/new-bill.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile new bill screen with a scanned product added to the cart",
  },
  newBillEmpty: {
    src: "/images/dukania/mobile/new-bill-empty.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile new bill screen ready to search or scan a product",
  },
  checkout: {
    src: "/images/dukania/mobile/checkout.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile checkout with GST, bill discount, payment modes and the Create bill button",
  },
  products: {
    src: "/images/dukania/mobile/products.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile product list with prices and low or out-of-stock badges",
  },
  productDetail: {
    src: "/images/dukania/mobile/product-detail.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile product detail showing pricing, current stock and variants",
  },
  reports: {
    src: "/images/dukania/mobile/reports.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile reports menu listing sales, profit, stock and GST reports",
  },
  serviceCatalog: {
    src: "/images/dukania/mobile/service-catalog.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile service catalog with an add-service form",
  },
  jobCard: {
    src: "/images/dukania/mobile/job-card.jpeg",
    width: 576,
    height: 1280,
    alt: "Dukania mobile new job card form capturing device details and the reported issue",
  },
} satisfies Record<string, Shot>;
