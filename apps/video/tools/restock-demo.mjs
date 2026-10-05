// Demo shop only (Sharma General Store): tops up named products via the app's
// own adjust_stock call, signed in as the demo owner. Run from apps/admin:
//   node ../video/tools/restock-demo.mjs "Eggs=240"
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(path.resolve("package.json"));
const { createClient } = require("@supabase/supabase-js");
const env = Object.fromEntries(fs.readFileSync(".env.local", "utf8").split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1).trim().replace(/^"|"$/g, "")]));
const login = JSON.parse(fs.readFileSync(process.env.DEMO_LOGIN, "utf8"));
const db = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
const { error: e0 } = await db.auth.signInWithPassword({ email: login.email, password: login.password });
if (e0) throw new Error(e0.message);
for (const arg of process.argv.slice(2)) {
  const [name, qty] = arg.split("=");
  const { data } = await db.from("products").select("id, name, current_stock").eq("business_id", login.businessId).eq("name", name).single();
  const { error } = await db.rpc("adjust_stock", { p_product_id: data.id, p_variant_id: null, p_quantity: Number(qty), p_type: "adjustment", p_note: "Stock received" });
  console.log(name, data.current_stock, "+", qty, error ? error.message : "ok");
}
