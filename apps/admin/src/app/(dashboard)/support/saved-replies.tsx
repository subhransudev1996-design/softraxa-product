"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Spinner } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";

/* eslint-disable @typescript-eslint/no-explicit-any */

type Editing = { id: string | null; title: string; body: string };

/** Answers the team writes again and again (migration 0099). {shop} and {owner} are filled in. */
export function SavedReplies() {
  const supabase = createClient();
  const [rows, setRows] = useState<any[] | null>(null);
  const [editing, setEditing] = useState<Editing | null>(null);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);

  useEffect(() => {
    supabase.from("saved_replies").select("*").order("title")
      .then(({ data, error }) => {
        if (error) setNotice({ ok: false, text: error.message });
        setRows(data ?? []);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refresh]);

  async function save() {
    if (!editing) return;
    const row = { title: editing.title.trim(), body: editing.body.trim() };
    const { error } = editing.id
      ? await supabase.from("saved_replies").update(row).eq("id", editing.id)
      : await supabase.from("saved_replies").insert(row);
    if (error) return setNotice({ ok: false, text: error.message });
    setEditing(null);
    setRefresh((n) => n + 1);
  }

  async function remove(r: any) {
    if (!window.confirm(`Delete the saved reply "${r.title}"?`)) return;
    const { error } = await supabase.from("saved_replies").delete().eq("id", r.id);
    if (error) return setNotice({ ok: false, text: error.message });
    setRefresh((n) => n + 1);
  }

  if (!rows) return <Spinner />;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-900">Saved replies</h1>
          <p className="text-sm text-zinc-500">
            Pick one in a request&apos;s reply box. Write <code>{"{shop}"}</code> or <code>{"{owner}"}</code> and the
            shop&apos;s name or the owner&apos;s name goes in.
          </p>
        </div>
        <Button onClick={() => setEditing({ id: null, title: "", body: "" })}>New saved reply</Button>
      </div>
      <Notice notice={notice} />
      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        {rows.map((r) => (
          <Card key={r.id}>
            <CardBody className="space-y-2">
              <p className="font-bold text-ink">{r.title}</p>
              <p className="line-clamp-4 whitespace-pre-wrap text-sm text-zinc-600">{r.body}</p>
              <div className="flex gap-2">
                <Button variant="outline" onClick={() => setEditing({ id: r.id, title: r.title, body: r.body })}>Change</Button>
                <Button variant="ghost" onClick={() => remove(r)}>Delete</Button>
              </div>
            </CardBody>
          </Card>
        ))}
        {rows.length === 0 && (
          <Card>
            <CardBody>
              <p className="text-sm text-zinc-500">
                None yet. Start with the answers you type most, like how to print a bill or how to add staff.
              </p>
            </CardBody>
          </Card>
        )}
      </div>

      {editing && (
        <Modal title={editing.id ? "Change saved reply" : "New saved reply"} onClose={() => setEditing(null)}>
          <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
            <div>
              <Label>Name (only the team sees it)</Label>
              <Input required value={editing.title} onChange={(e) => setEditing({ ...editing, title: e.target.value })} placeholder="e.g. How to print on A5" />
            </div>
            <div>
              <Label>Reply</Label>
              <textarea
                required
                rows={6}
                value={editing.body}
                onChange={(e) => setEditing({ ...editing, body: e.target.value })}
                placeholder="Namaste {owner}! …"
                className="w-full rounded-lg border border-zinc-200 px-3.5 py-2 text-sm outline-none focus:border-brand focus:ring-4 focus:ring-brand/10"
              />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
              <Button type="submit" disabled={!editing.title.trim() || !editing.body.trim()}>Save</Button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
