import type { IconName } from "@/components/site/lucide-icon";
import { desktopShots, mobileShots, type Shot } from "./shots";

/**
 * The trades Dukania is set up for (the shop types picked at sign-up,
 * migrations 0047, 0066, 0081). Only what the app does today.
 */
export type Trade = {
  slug: string;
  name: string;
  short: string;
  image: string;
  focus: string;
  title: string;
  lead: string;
  pains: string[];
  features: { icon: IconName; title: string; body: string }[];
  shot: { kind: "laptop" | "phone"; shot: Shot };
  faqs: { q: string; a: string }[];
};

export const TRADES: Trade[] = [
  {
    slug: "grocery",
    name: "Grocery & kirana",
    short: "Loose items by weight, khata for regulars, fast counter billing.",
    image: "/images/site/trade-grocery.jpg",
    focus: "65%",
    title: "Billing software for\ngrocery & kirana stores.",
    lead: "Bill loose atta and packed biscuits on the same bill, keep the khata for your regular customers, and know what to reorder before the shelf is empty.",
    pains: ["Long queues at the counter", "Loose items weighed and written by hand", "Udhaar written in a notebook", "Expired stock found too late"],
    features: [
      { icon: "Scale", title: "Loose items by weight", body: "Sell by kg and gram; read weighing-scale barcodes." },
      { icon: "ScanLine", title: "Barcode billing", body: "Scan packed goods with a scanner or the phone camera." },
      { icon: "BookUser", title: "Khata", body: "Each customer's dues, payments and credit limit." },
      { icon: "CalendarClock", title: "Expiry tracking", body: "See what expires soon and sell it first." },
      { icon: "PackageSearch", title: "Ready grocery list", body: "Common grocery products ready to tick — no typing them all." },
      { icon: "BadgePercent", title: "Discount cards & offers", body: "Bring regular customers back." },
    ],
    shot: { kind: "phone", shot: mobileShots.newBill },
    faqs: [
      { q: "Can I bill loose items by weight?", a: "Yes. Sell by kg or gram, and scan barcodes printed by a weighing scale." },
      { q: "Will it work during a power or internet cut?", a: "Billing works fully offline on the phone or PC and syncs when the internet is back." },
    ],
  },
  {
    slug: "mobile",
    name: "Mobile & electronics",
    short: "IMEI on every bill, variants, accessories and repairs.",
    image: "/images/site/trade-mobile.jpg",
    focus: "70%",
    title: "Billing software for\nmobile & electronics shops.",
    lead: "Track every handset by IMEI from purchase to sale, sell colour and storage variants, and run repairs with job cards — all in one app.",
    pains: ["IMEI numbers kept in a register", "Wrong variant sold from stock", "Repair slips lost", "Warranty questions with no record"],
    features: [
      { icon: "Smartphone", title: "IMEI & serial numbers", body: "On the purchase, in stock and on the bill." },
      { icon: "Shapes", title: "Colour & storage variants", body: "One product, every version, each with its own stock." },
      { icon: "Wrench", title: "Repair job cards", body: "Received, in repair, ready, delivered." },
      { icon: "ClipboardCheck", title: "Estimates", body: "The customer approves before you start." },
      { icon: "Undo2", title: "Returns & exchanges", body: "By bill line, with the old price." },
      { icon: "Landmark", title: "GST on every bill", body: "HSN, CGST/SGST/IGST and the return files." },
    ],
    shot: { kind: "laptop", shot: desktopShots.jobCard },
    faqs: [
      { q: "Can I search a sale by IMEI?", a: "Yes. Every handset's IMEI is recorded when you buy it and when you sell it." },
      { q: "Do you handle repairs too?", a: "Yes — job cards with status, estimates the customer approves, and parts plus labour on one bill." },
    ],
  },
  {
    slug: "hardware",
    name: "Hardware & electrical",
    short: "Sell by metre, kg or piece; cut wire and pipe from the roll.",
    image: "/images/site/trade-hardware.jpg",
    focus: "50%",
    title: "Billing software for\nhardware & electrical shops.",
    lead: "Thousands of items, sold by the piece, the box, the metre or the kg — Dukania keeps the stock right, even when you cut a length from a roll.",
    pains: ["Huge product lists", "Rolls cut into pieces and stock gone wrong", "Contractors on credit", "Different rates for different buyers"],
    features: [
      { icon: "Ruler", title: "Metre, kg, box or piece", body: "Units and packs the way you sell." },
      { icon: "Scissors", title: "Cuts from a roll", body: "Sell a length of wire or pipe; the rest stays in stock." },
      { icon: "Tags", title: "Customer prices", body: "Special rates for contractors and regular buyers." },
      { icon: "BookUser", title: "Credit & limits", body: "Khata with a limit for every customer." },
      { icon: "FileSpreadsheet", title: "Excel import", body: "Bring your whole product list in at once." },
      { icon: "FileScan", title: "Supplier bills", body: "Read a supplier's PDF or Excel bill into a purchase." },
    ],
    shot: { kind: "laptop", shot: desktopShots.products },
    faqs: [
      { q: "Can I sell part of a roll?", a: "Yes. Sell the length the customer needs; Dukania keeps the remaining piece in stock." },
      { q: "I have thousands of items. Do I type them all?", a: "No — import them from Excel, or tick them from the ready product list for hardware and electrical." },
    ],
  },
  {
    slug: "garments",
    name: "Garments & footwear",
    short: "Sizes and colours, barcode billing, easy exchanges.",
    image: "/images/site/trade-garments.jpg",
    focus: "55%",
    title: "Billing software for\ngarment & footwear stores.",
    lead: "Every size and colour with its own stock, barcode billing at the counter, and exchanges without paperwork.",
    pains: ["Size and colour stock is a guess", "Exchanges done on paper", "Slow billing in the festive rush", "Discount rules hard to remember"],
    features: [
      { icon: "Shapes", title: "Sizes & colours", body: "Variants with their own stock and barcode." },
      { icon: "ScanLine", title: "Barcode billing", body: "Fast billing in the busy season." },
      { icon: "Repeat", title: "Exchanges", body: "Take back by bill line, give the new item, settle the difference." },
      { icon: "BadgePercent", title: "Discount & privilege cards", body: "Applied on the bill by themselves." },
      { icon: "Gift", title: "Offers & scratch cards", body: "Festival offers your customers enjoy." },
      { icon: "BarChart3", title: "What sells", body: "Sales by product to plan your next purchase." },
    ],
    shot: { kind: "laptop", shot: desktopShots.newBill },
    faqs: [
      { q: "Can each size have its own barcode?", a: "Yes. Every size and colour is its own variant with stock and a barcode." },
      { q: "How do exchanges work?", a: "Pick the item on the old bill, take it back, add the new one — Dukania works out the difference." },
    ],
  },
  {
    slug: "workshops",
    name: "Car & bike workshops",
    short: "Vehicle job cards, estimates, parts and labour on one bill.",
    image: "/images/site/trade-workshop.jpg",
    focus: "40%",
    title: "Software for\ncar & bike workshops.",
    lead: "Open a job card for each vehicle, send an estimate the customer approves, and bill parts and labour together.",
    pains: ["Job slips lost on the floor", "Arguments over the final bill", "Parts used but not billed", "No history of a vehicle's service"],
    features: [
      { icon: "Wrench", title: "Vehicle job cards", body: "Status from received to delivered." },
      { icon: "ClipboardCheck", title: "Estimates first", body: "The customer approves before the work." },
      { icon: "Package", title: "Parts from stock", body: "Parts used come off stock on the bill." },
      { icon: "ListChecks", title: "Service catalog", body: "Your standard services and their prices." },
      { icon: "Receipt", title: "Parts + labour bill", body: "One GST bill for everything." },
      { icon: "BookUser", title: "Customer history", body: "Every visit and every bill." },
    ],
    shot: { kind: "laptop", shot: desktopShots.serviceCatalog },
    faqs: [
      { q: "Can the customer approve the estimate?", a: "Yes. Send the estimate, get the OK, then start the work." },
      { q: "Do parts come off my stock?", a: "Yes — parts on the job card come off stock when you bill." },
    ],
  },
  {
    slug: "book-stores",
    name: "Book & stationery stores",
    short: "Publisher and author on the bill, privilege cards, A4/A5/thermal.",
    image: "/images/site/trade-retail.jpg",
    focus: "55%",
    title: "Billing software for\nbook & stationery stores.",
    lead: "Bills with the publisher and author, regular and privilege-card discounts worked out for you, and printing on A4, A5 or thermal.",
    pains: ["Discounts calculated by hand", "Privilege cards on paper", "Long bills for school lists", "Bills that don't show the book's details"],
    features: [
      { icon: "BookOpen", title: "Publisher & author", body: "On the product and on the bill." },
      { icon: "BadgePercent", title: "Privilege cards", body: "The card's discount applies by itself." },
      { icon: "Ticket", title: "Coupons", body: "Pick a coupon at the counter." },
      { icon: "Printer", title: "A4, A5 or thermal", body: "With your shop's note at the bottom." },
      { icon: "PiggyBank", title: "You saved…", body: "Every discount shown, and the total saved." },
      { icon: "Landmark", title: "GST from the product", body: "The right rate on every line." },
    ],
    shot: { kind: "laptop", shot: desktopShots.invoices },
    faqs: [
      { q: "Can the bill show publisher and author?", a: "Yes — they're on the product and printed on the bill." },
      { q: "Can a customer's card discount apply by itself?", a: "Yes. Find the customer's privilege card and its discount goes on the bill." },
    ],
  },
  {
    slug: "retail",
    name: "Any retail counter",
    short: "GST billing from day one, stock that stays right.",
    image: "/images/site/trade-retail.jpg",
    focus: "55%",
    title: "Billing software for\nevery retail counter.",
    lead: "Cosmetics, gifts, footwear, general stores — if you sell over a counter, Dukania bills, keeps stock and does your GST.",
    pains: ["Bills in a book", "Stock you can't trust", "Month-end GST panic", "No idea of the day's profit"],
    features: [
      { icon: "ReceiptText", title: "Fast GST billing", body: "From the phone you already have." },
      { icon: "TriangleAlert", title: "Low-stock alerts", body: "Reorder before you run out." },
      { icon: "Landmark", title: "GST return files", body: "GSTR-1, 3B and 2B matching." },
      { icon: "Wallet", title: "Cashbook", body: "Close the day with the drawer counted." },
      { icon: "BarChart3", title: "Reports", body: "Sales and profit every day." },
      { icon: "Languages", title: "In your language", body: "11 languages." },
    ],
    shot: { kind: "laptop", shot: desktopShots.dashboard },
    faqs: [
      { q: "My shop isn't in the list. Will it work?", a: "Yes. Pick \"Other\" when you sign up — billing, stock, GST and khata work for any counter." },
      { q: "Do I need a computer?", a: "No. Dukania works on an Android phone; add a Windows PC whenever you like." },
    ],
  },
];

export const tradeBySlug = (slug: string) => TRADES.find((t) => t.slug === slug);
