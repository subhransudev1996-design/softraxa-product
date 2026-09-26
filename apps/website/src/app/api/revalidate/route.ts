import { NextResponse } from "next/server";
import { revalidatePath } from "next/cache";
import { createClient } from "@supabase/supabase-js";

/**
 * POST /api/revalidate — publishes CMS edits (PROJECT_ANALYSIS finding 17).
 *
 * Marketing pages are pre-rendered, so a CMS save alone never reached the
 * live site. The CMS calls this after every save with the editor's access
 * token; only platform admins may trigger it. Pages are also re-rendered at
 * least hourly (root layout `revalidate`) as a fallback.
 */
export async function POST(req: Request) {
  const header = req.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    }
  );

  const { data: { user } } = await supabase.auth.getUser(token);
  if (!user) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).single();
  if (profile?.role !== "admin") return NextResponse.json({ error: "Admin only" }, { status: 403 });

  revalidatePath("/", "layout");
  return NextResponse.json({ revalidated: true });
}
