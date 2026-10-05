import React from "react";
import { AbsoluteFill } from "remotion";
import { TransitionSeries, springTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { Bg } from "./fx";
import { Billing, Bills, Brand, Checkout, Cta, D, Dashboard, Hook, Khata, Tray, Trust } from "./scenes";

export const TRANSITION = 12;
const timing = springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION });

type Item = { key: string; frames: number; node: React.ReactNode; into?: "fade" | "up" | "left" };

const items: Item[] = [
  { key: "hook", frames: D.hook, node: <Hook /> },
  { key: "brand", frames: D.brand, node: <Brand />, into: "fade" },
  { key: "billing", frames: D.billing, node: <Billing />, into: "up" },
  { key: "tray", frames: D.tray, node: <Tray />, into: "left" },
  { key: "checkout", frames: D.checkout, node: <Checkout />, into: "left" },
  { key: "bills", frames: D.bills, node: <Bills />, into: "left" },
  { key: "khata", frames: D.khata, node: <Khata />, into: "left" },
  { key: "dashboard", frames: D.dashboard, node: <Dashboard />, into: "left" },
  { key: "trust", frames: D.trust, node: <Trust />, into: "up" },
  {
    key: "cta",
    frames: D.cta,
    node: <Cta line1="Try" note="WhatsApp us for a free demo" />,
    into: "fade",
  },
];

export const desktopFrames = items.reduce((s, i) => s + i.frames, 0) - TRANSITION * (items.length - 1);

const presentation = (k: Item["into"]) =>
  k === "fade" ? fade() : k === "up" ? slide({ direction: "from-bottom" }) : slide({ direction: "from-right" });

export const DesktopReel: React.FC = () => (
  <AbsoluteFill>
    <Bg />
    <TransitionSeries>
      {items.flatMap((it, i) => [
        ...(i > 0
          ? [<TransitionSeries.Transition key={`t-${it.key}`} presentation={presentation(it.into)} timing={timing} />]
          : []),
        <TransitionSeries.Sequence key={it.key} durationInFrames={it.frames}>
          {it.node}
        </TransitionSeries.Sequence>,
      ])}
    </TransitionSeries>
  </AbsoluteFill>
);
