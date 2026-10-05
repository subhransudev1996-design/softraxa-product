/** The YouTube video: one row per storyboard scene. `sec` is the picture length; once the
 *  narration is recorded these are re-timed to the voice (see narration-script.md). */
export type Sc = { n: number; sec: number; cap: string; sub: string };

export const YW = 1920;
export const YH = 1080;
export const YFPS = 30;

export const SCENES: Sc[] = [
  { n: 1, sec: 8, cap: "Register. Calculator. Raat tak hisaab.", sub: "Running a shop isn't easy. Accounts in a register, sums on a calculator, and counting stock late at night." },
  { n: 2, sec: 12, cap: "Kisne kitna udhaar liya? Kaunsa maal kam hai?", sub: "Who took how much on credit? Which item is about to run out? How much did you earn today? Often there is no answer." },
  { n: 3, sec: 10, cap: "Dukania: Billing · Stock · Udhaar", sub: "Dukania: billing, stock and credit accounts for your shop, all in one app." },
  { n: 4, sec: 10, cap: "Phone par bhi. Computer par bhi.", sub: "It works on your phone and on your computer. Grocery, mobile shop, hardware or clothes." },
  { n: 5, sec: 12, cap: "Setup: 2 minute", sub: "Getting started is easy. Enter your shop name, type and phone number. That's it." },
  { n: 6, sec: 10, cap: "Apna rate. Apna unit.", sub: "Add your products: name, rate, unit. Keep one rate for the Box and another for a single piece." },
  { n: 7, sec: 8, cap: "Excel se import", sub: "Already have a list in Excel? Import it in one go." },
  { n: 8, sec: 12, cap: "Type. Enter. Done.", sub: "A new bill: type the product name and press Enter. The bill builds in seconds." },
  { n: 9, sec: 12, cap: "Kilo, gram ya rupaye mein", sub: "Loose goods are easy too. Sell by the kilo, or when a customer asks for fifty rupees of sugar, type the amount and the quantity appears." },
  { n: 10, sec: 16, cap: "Tray ka rate alag. Piece ka rate alag.", sub: "A tray at one price, a single egg at another. Sell either way. The rate is right automatically, and stock goes down correctly." },
  { n: 11, sec: 15, cap: "Aapka profit. Customer ko nahi dikhta.", sub: "At checkout choose cash, UPI, card or credit. And you see your profit, which the customer never sees." },
  { n: 12, sec: 12, cap: "Bill ka PDF. Seedha WhatsApp par.", sub: "Make a bill PDF and send it straight to WhatsApp from your phone. Every bill carries your shop name and number." },
  { n: 13, sec: 13, cap: "A4 ya thermal printer", sub: "Print on A4, or a small thermal receipt. Whatever suits your counter." },
  { n: 14, sec: 15, cap: "Kisne kitna dena hai? Ek nazar mein.", sub: "Credit accounts live in the app, not in a register. Every customer's balance at a glance." },
  { n: 15, sec: 15, cap: "Payment lo. Purane bill apne-aap kat jaate hain.", sub: "When a payment comes, tap Receive Payment. Old bills clear automatically and the balance goes down." },
  { n: 16, sec: 12, cap: "Maal khatam hone se pehle pata chale", sub: "The app tells you which items are running low before they run out. Don't wait for the stock to finish." },
  { n: 17, sec: 18, cap: "Maal aaya? Purchase daaliye. Stock apne-aap badhta hai.", sub: "Stock arrived from the supplier? Add a purchase. Stock goes up by itself, and what you owe the supplier shows too." },
  { n: 18, sec: 12, cap: "Aaj ki kamai. Profit. Stock.", sub: "On the dashboard: today's earnings, profit and stock, at a glance." },
  { n: 19, sec: 13, cap: "Sales, profit, GST: PDF mein", sub: "Sales, profit and GST reports, as a PDF whenever you need them." },
  { n: 20, sec: 10, cap: "Phone par bhi wahi dukaan", sub: "The same shop, the same accounts, on your phone too. A computer at the counter, a phone in your pocket." },
  { n: 21, sec: 10, cap: "Internet chala jaaye? Billing chalti rahe.", sub: "Even if the internet goes, billing keeps working. As soon as the net is back, everything syncs." },
  { n: 22, sec: 10, cap: "7 din free trial", sub: "Try it free for 7 days. Then decide." },
  { n: 23, sec: 10, cap: "softraxa.in · WhatsApp +91 82609 66559", sub: "Visit softraxa.in now, or message us on WhatsApp. Dukania: shop accounts, made simple." },
];

export const TOTAL_SEC = SCENES.reduce((s, x) => s + x.sec, 0);

export const CHAPTERS: [string, string][] = [
  ["0:00", "Why shop accounts feel hard"],
  ["0:20", "Meet Dukania"],
  ["0:40", "Set up your shop"],
  ["1:10", "Billing: loose goods, boxes and trays"],
  ["2:05", "Bills: PDF, WhatsApp and printing"],
  ["2:30", "Udhaar and payments"],
  ["3:00", "Stock and purchases"],
  ["3:30", "Reports"],
  ["3:55", "On your phone, and offline"],
  ["4:15", "7-day free trial"],
];
