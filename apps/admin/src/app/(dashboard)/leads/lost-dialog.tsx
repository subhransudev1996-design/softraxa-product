"use client";

import { useState } from "react";
import { Button, Input, Label, Select } from "@/components/ui";
import { Modal } from "@/components/ops";
import { LOST_REASONS } from "@/lib/leads";

/* eslint-disable @typescript-eslint/no-explicit-any */

/** Why a lead was lost: a reason from the list (reports count them), plus a few words. */
export function LostDialog({ lead, onClose, onLost }: { lead: any; onClose: () => void; onLost: (reason: string) => void }) {
  const [reason, setReason] = useState(LOST_REASONS[0]);
  const [more, setMore] = useState("");
  return (
    <Modal title={`Lost — ${lead.shop_name}`} onClose={onClose}>
      <form
        className="space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          onLost(more.trim() ? `${reason}: ${more.trim()}` : reason);
        }}
      >
        <div>
          <Label>Why?</Label>
          <Select value={reason} onChange={(e) => setReason(e.target.value)}>
            {LOST_REASONS.map((r) => <option key={r} value={r}>{r}</option>)}
          </Select>
        </div>
        <div>
          <Label>A few words (optional)</Label>
          <Input value={more} onChange={(e) => setMore(e.target.value)} placeholder="e.g. uses Vyapar, price ₹1,500" />
        </div>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button type="submit" variant="danger">Mark lost</Button>
        </div>
      </form>
    </Modal>
  );
}
