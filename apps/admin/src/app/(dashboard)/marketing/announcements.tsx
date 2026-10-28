"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge, Button, Card, CardBody, Spinner } from "@/components/ui";
import { Notice } from "@/components/ops";
import { memberName, useTeam } from "@/components/me";
import { dateStr, dateTimeStr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Every announcement sent, who it went to, and ending a banner early. */
export function Announcements() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [dismissed, setDismissed] = useState<Record<string, number>>({});
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  const team = useTeam();

  useEffect(() => {
    createClient().from("announcements").select("*").order("created_at", { ascending: false }).limit(100)
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setRows(data ?? []);
        setNow(Date.now());
      });
    // How many shops closed each banner (counted in the database).
    createClient().rpc("admin_announcement_dismissals").then(({ data }) => setDismissed((data as any) ?? {}));
  }, [refresh]);

  async function end(id: string) {
    const { error } = await createClient().rpc("admin_end_announcement", { p_id: id });
    if (error) return setNotice({ ok: false, text: error.message });
    setNotice({ ok: true, text: "Banner ended — the shops won't see it any more." });
    setRefresh((n) => n + 1);
  }

  if (!rows) return <Spinner />;
  const running = (a: any) => a.banner && new Date(a.starts_at).getTime() <= now && (!a.ends_at || new Date(a.ends_at).getTime() > now);

  return (
    <div className="space-y-3">
      <Notice notice={notice} />
      {rows.map((a) => (
        <Card key={a.id}>
          <CardBody className="space-y-2">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="font-bold text-ink">{a.title}</p>
                {a.body && <p className="whitespace-pre-wrap text-sm text-zinc-600">{a.body}</p>}
                {a.button_url && (
                  <p className="mt-1 text-xs text-zinc-500">
                    Button &quot;{a.button_label}&quot; → <a href={a.button_url} target="_blank" rel="noreferrer" className="text-brand hover:underline">{a.button_url}</a>
                  </p>
                )}
              </div>
              <div className="flex flex-wrap gap-1.5">
                {a.banner && (running(a) ? <Badge color="green">Banner showing</Badge> : <Badge color="zinc">Banner ended</Badge>)}
                {a.push && <Badge color="blue">{a.push_sent_at ? `Notified ${a.push_count} phone${a.push_count === 1 ? "" : "s"}` : "Notification not sent"}</Badge>}
              </div>
            </div>
            <p className="text-xs text-zinc-500">
              {a.business_ids.length} shop{a.business_ids.length === 1 ? "" : "s"} ({a.audience || "picked"}) · {dateTimeStr(a.created_at)}
              {memberName(team, a.created_by) ? ` · by ${memberName(team, a.created_by)}` : ""}
              {a.ends_at ? ` · ends ${dateStr(a.ends_at)}` : ""}
              {a.banner && dismissed[a.id] ? ` · closed by ${dismissed[a.id]}` : ""}
            </p>
            {running(a) && (
              <div><Button variant="outline" onClick={() => end(a.id)}>End the banner now</Button></div>
            )}
          </CardBody>
        </Card>
      ))}
      {rows.length === 0 && (
        <Card><CardBody><p className="text-sm text-zinc-500">Nothing sent yet. Pick shops on &quot;Shops &amp; messages&quot; and press Announce.</p></CardBody></Card>
      )}
    </div>
  );
}
