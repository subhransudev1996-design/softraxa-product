"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Button, Card, CardBody, Input, Label, Select, Spinner, StatCard, Table } from "@/components/ui";
import { Modal, Notice } from "@/components/ops";
import { useCan } from "@/components/me";
import { dateStr, inr } from "@/lib/format";

/* eslint-disable @typescript-eslint/no-explicit-any */

const today = () => new Date(Date.now() + 5.5 * 3600000).toISOString().slice(0, 10);

/**
 * Posts and fixed fees (migration 0109), for one partner or everyone. The
 * clicks beside a post are those in the 3 days from it: posts close together
 * share them.
 */
export function PostsAndFees({ partner, partners, onChange }: { partner?: any; partners?: any[]; onChange?: () => void }) {
  const [posts, setPosts] = useState<any[] | null>(null);
  const [fees, setFees] = useState<any[] | null>(null);
  const [editPost, setEditPost] = useState<any>(null);
  const [addFee, setAddFee] = useState(false);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [refresh, setRefresh] = useState(0);
  const canMarket = useCan("marketing");
  const canPay = useCan("payments");
  const partnerId: string | undefined = partner?.id;

  useEffect(() => {
    const db = createClient();
    db.rpc("admin_partner_posts", { p_partner: partnerId ?? null }).then(({ data, error }) => {
      if (error) setNotice({ ok: false, text: error.message.includes("admin_partner_posts") ? "Migration 0109 isn't applied to this database yet." : error.message });
      setPosts((data as any[]) ?? []);
    });
    let q = db.from("partner_fees").select("*, partners(name, code)").order("paid_on", { ascending: false });
    if (partnerId) q = q.eq("partner_id", partnerId);
    q.then(({ data }) => setFees(data ?? []));
  }, [partnerId, refresh]);

  const changed = useCallback(() => {
    setRefresh((n) => n + 1);
    onChange?.();
  }, [onChange]);

  if (!posts || !fees) return <Spinner />;

  async function deletePost(o: any) {
    if (!window.confirm("Delete this post from the list?")) return;
    const { error } = await createClient().rpc("admin_delete_partner_post", { p_id: o.id });
    if (error) return setNotice({ ok: false, text: error.message });
    changed();
  }

  async function deleteFee(f: any) {
    if (!window.confirm(`Delete this ${inr(f.amount)} fee? Its expense in Accounts goes too.`)) return;
    const { error } = await createClient().rpc("admin_delete_partner_fee", { p_id: f.id });
    if (error) return setNotice({ ok: false, text: error.message });
    changed();
  }

  const chooser = partners ?? (partner ? [partner] : []);

  return (
    <div className="space-y-6">
      <Notice notice={notice} />
      {!partner && (
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-3">
          <StatCard label="Posts" value={posts.length} />
          <StatCard label="Views" value={posts.reduce((s, o) => s + Number(o.views ?? 0), 0).toLocaleString("en-IN")} />
          <StatCard label="Fixed fees paid" value={inr(fees.reduce((s, f) => s + Number(f.amount), 0))} hint="Also in Accounts, as ads" />
        </div>
      )}

      <Card>
        <CardBody className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-sm font-semibold text-zinc-700">Posts</h2>
            {canMarket && <Button variant="outline" disabled={chooser.length === 0} onClick={() => setEditPost({})}>Add post</Button>}
          </div>
          {posts.length === 0 ? <p className="text-sm text-zinc-500">No posts yet. Add each reel or story with its link and views.</p> : (
            <Table headers={[...(partner ? [] : ["Partner"]), "Date", "Post", "Views", "Clicks in 3 days", "Shops in 3 days", ""]}>
              {posts.map((o) => (
                <tr key={o.id}>
                  {!partner && <td className="px-4 py-3"><Link href={`/influencers/${o.partner_id}`} className="font-semibold text-ink hover:underline">{o.partner_name}</Link></td>}
                  <td className="whitespace-nowrap px-4 py-3">{dateStr(o.posted_on)}</td>
                  <td className="px-4 py-3 capitalize">
                    {/^https?:\/\//.test(o.url) ? <a href={o.url} target="_blank" rel="noreferrer" className="font-semibold text-brand hover:underline">{o.kind}</a> : o.kind}
                    {o.note && <span className="block text-xs normal-case text-zinc-500">{o.note}</span>}
                  </td>
                  <td className="px-4 py-3 tabular-nums">{o.views == null ? "—" : Number(o.views).toLocaleString("en-IN")}</td>
                  <td className="px-4 py-3 tabular-nums">{o.clicks_3d}</td>
                  <td className="px-4 py-3 tabular-nums">{o.signups_3d}</td>
                  <td className="px-4 py-3">
                    {canMarket && (
                      <div className="flex justify-end gap-2">
                        <Button variant="ghost" onClick={() => setEditPost(o)}>Edit</Button>
                        <Button variant="ghost" onClick={() => deletePost(o)}>Delete</Button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </Table>
          )}
        </CardBody>
      </Card>

      <Card>
        <CardBody className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="text-sm font-semibold text-zinc-700">Fixed fees</h2>
            {canPay && <Button variant="outline" disabled={chooser.length === 0} onClick={() => setAddFee(true)}>Add fee</Button>}
          </div>
          {fees.length === 0 ? <p className="text-sm text-zinc-500">No fees paid. Money paid upfront for a post goes here, so it counts against what they brought.</p> : (
            <Table headers={[...(partner ? [] : ["Partner"]), "Date", "Amount", "Reference", "Note", ""]}>
              {fees.map((f) => (
                <tr key={f.id}>
                  {!partner && <td className="px-4 py-3"><Link href={`/influencers/${f.partner_id}`} className="font-semibold text-ink hover:underline">{f.partners?.name}</Link></td>}
                  <td className="whitespace-nowrap px-4 py-3">{dateStr(f.paid_on)}</td>
                  <td className="px-4 py-3 font-semibold tabular-nums">{inr(f.amount)}</td>
                  <td className="px-4 py-3 font-mono text-xs">{f.reference || f.mode}</td>
                  <td className="px-4 py-3 text-xs text-zinc-600">{f.note}</td>
                  <td className="px-4 py-3 text-right">{canPay && <Button variant="ghost" onClick={() => deleteFee(f)}>Delete</Button>}</td>
                </tr>
              ))}
            </Table>
          )}
        </CardBody>
      </Card>

      {editPost && <PostDialog post={editPost} partner={partner} partners={chooser} onClose={() => setEditPost(null)}
        onDone={() => { setEditPost(null); changed(); }} />}
      {addFee && <FeeDialog partner={partner} partners={chooser} onClose={() => setAddFee(false)}
        onDone={() => { setAddFee(false); changed(); }} />}
    </div>
  );
}

function PostDialog({ post, partner, partners, onClose, onDone }: {
  post: any; partner?: any; partners: any[]; onClose: () => void; onDone: () => void;
}) {
  const [partnerId, setPartnerId] = useState<string>(post.partner_id ?? partner?.id ?? "");
  const [postedOn, setPostedOn] = useState<string>(post.posted_on ?? today());
  const [kind, setKind] = useState<string>(post.kind ?? "reel");
  const [url, setUrl] = useState<string>(post.url ?? "");
  const [views, setViews] = useState<string>(post.views == null ? "" : String(post.views));
  const [note, setNote] = useState<string>(post.note ?? "");
  const [error, setError] = useState<string | null>(null);

  async function save() {
    const { error: e } = await createClient().rpc("admin_save_partner_post", {
      p: { id: post.id ?? "", partner_id: partnerId, posted_on: postedOn, kind, url, views, note },
    });
    if (e) return setError(e.message);
    onDone();
  }

  return (
    <Modal title={post.id ? "Edit post" : "Add post"} onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
        {error && <p className="font-medium text-red-600">{error}</p>}
        {!partner && !post.id && (
          <div>
            <Label>Partner</Label>
            <Select required value={partnerId} onChange={(e) => setPartnerId(e.target.value)}>
              <option value="">Choose…</option>
              {partners.map((p) => <option key={p.id} value={p.id}>{p.name} ({p.code})</option>)}
            </Select>
          </div>
        )}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div>
            <Label>Date</Label>
            <Input type="date" required value={postedOn} onChange={(e) => setPostedOn(e.target.value)} />
          </div>
          <div>
            <Label>Type</Label>
            <Select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="reel">Reel</option>
              <option value="story">Story</option>
              <option value="video">Video</option>
              <option value="post">Post</option>
            </Select>
          </div>
          <div>
            <Label>Views</Label>
            <Input type="number" min={0} value={views} onChange={(e) => setViews(e.target.value)} />
          </div>
        </div>
        <div>
          <Label>Link</Label>
          <Input type="url" value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://www.instagram.com/reel/…" />
        </div>
        <div>
          <Label>Note</Label>
          <Input value={note} onChange={(e) => setNote(e.target.value)} />
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={!partnerId}>Save</Button>
        </div>
      </form>
    </Modal>
  );
}

function FeeDialog({ partner, partners, onClose, onDone }: {
  partner?: any; partners: any[]; onClose: () => void; onDone: () => void;
}) {
  const [partnerId, setPartnerId] = useState<string>(partner?.id ?? "");
  const [amount, setAmount] = useState("");
  const [paidOn, setPaidOn] = useState(today());
  const [mode, setMode] = useState("upi");
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function save() {
    const { error: e } = await createClient().rpc("admin_add_partner_fee", {
      p_partner: partnerId, p: { amount: Number(amount), paid_on: paidOn, mode, reference: reference.trim(), note },
    });
    if (e) return setError(e.message);
    onDone();
  }

  return (
    <Modal title="Add a fixed fee" onClose={onClose}>
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); save(); }}>
        {error && <p className="font-medium text-red-600">{error}</p>}
        {!partner && (
          <div>
            <Label>Partner</Label>
            <Select required value={partnerId} onChange={(e) => setPartnerId(e.target.value)}>
              <option value="">Choose…</option>
              {partners.map((p) => <option key={p.id} value={p.id}>{p.name} ({p.code})</option>)}
            </Select>
          </div>
        )}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <Label>Amount ₹</Label>
            <Input type="number" required min={1} value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div>
            <Label>Date</Label>
            <Input type="date" required value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
          </div>
          <div>
            <Label>Paid by</Label>
            <Select value={mode} onChange={(e) => setMode(e.target.value)}>
              <option value="upi">UPI</option>
              <option value="other">Bank transfer</option>
              <option value="cash">Cash</option>
            </Select>
          </div>
          <div>
            <Label>UPI / bank reference</Label>
            <Input value={reference} onChange={(e) => setReference(e.target.value)} className="font-mono" placeholder="12-digit UTR" />
          </div>
        </div>
        <div>
          <Label>Note</Label>
          <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. 2 reels in November" />
        </div>
        <p className="text-xs text-zinc-500">This is added to Accounts as an ads expense. TDS can apply to fees too — check with your CA.</p>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" disabled={!partnerId || !amount || (mode !== "cash" && !reference.trim())}>Save</Button>
        </div>
      </form>
    </Modal>
  );
}
